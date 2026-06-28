// prefilter.mbt —— 字面量预过滤（literal prefilter，旗舰深化 T2.1）。
//
// 对标 Rust `regex` / RE2 的生产级提速手段：在 Pike VM 播种线程前，先用快速
// 扫描把搜索位置跳到「下一个可能成为匹配起点」的位置，避免在绝大多数不可能
// 起点上启动 NFA 线程。在「稀疏命中的长文本」场景（如在 1MB 日志里找少量
// 关键字）可带来数量级提速。本文件为**新增**，不改任何既有公开 API。
//
// 正确性核心：预过滤只允许**跳过绝不可能成为匹配起点的位置**。为此，从 AST
// 提取的「首字符集」必须是真实可能首字符的**超集**（over-approximation）：
//   * 任何非空匹配都至少消费一个字符，且该字符必落在首字符集内；
//   * 若正则可在某位置以零宽（空串）方式起步（nullable），则首字符约束不可靠，
//     退化为 `PfNone`（不跳过任何位置）。
// 由此 `find` / `find_all` / `is_match` 在开启预过滤后的结果与关闭时**逐位
// 相等**——这一不变量由 `prop_prefilter_test.mbt` 的差分属性测试守护。

///|
/// 预过滤策略（从编译期 AST 推导，随 `Program` 携带）。
pub enum Prefilter {
  /// 无可用预过滤：任意位置都可能是匹配起点（保守，等价于不跳过）。
  PfNone
  /// 匹配必以该字符集合中某字符开头（真实首字符的超集，已按 case-fold 归一）。
  PfFirstSet(CharSet)
} derive(Eq)

///|
/// 计算 AST 的 `(nullable, firstset)`：
///   * `nullable` —— 该子表达式是否可匹配空串（零宽起步）；
///   * `firstset` —— 任意**非空**匹配首字符的**超集**。
///
/// 当 `nullable` 为真时，调用方应忽略 `firstset`（可在任意位置零宽起步，
/// 首字符约束不成立）。
fn ast_first_set(ast : Ast) -> (Bool, CharSet) {
  match ast {
    Empty => (true, { intervals: [] })
    Lit(c) => (false, char_set_of_char(c))
    Set(cs) => (false, cs)
    Concat(xs) => {
      // 顺序累计「可空前缀」的首字符集：只要前一节点可空，下一节点的首字符
      // 也可能成为整体首字符；一旦遇到不可空节点即终止累计。
      let mut acc : CharSet = { intervals: [] }
      let mut nullable = true
      for x in xs {
        let (xn, xs_set) = ast_first_set(x)
        acc = acc.union(xs_set)
        if !xn {
          nullable = false
          break
        }
      }
      (nullable, acc)
    }
    Alt(branches) => {
      // 选择：首字符集取各分支并集；任一分支可空则整体可空。
      let mut acc : CharSet = { intervals: [] }
      let mut nullable = false
      for b in branches {
        let (bn, bs) = ast_first_set(b)
        acc = acc.union(bs)
        if bn {
          nullable = true
        }
      }
      (nullable, acc)
    }
    Repeat(node~, min~, ..) => {
      let (nn, ns) = ast_first_set(node)
      // `min == 0`（如 `*`、`?`、`{0,k}`）可匹配空串 => 整体可空；
      // `min >= 1` 则至少取一次，首字符与可空性同被重复节点。
      if min == 0 {
        (true, ns)
      } else {
        (nn, ns)
      }
    }
    Group(body~, ..) => ast_first_set(body)
    // 零宽断言（`^`/`$`/`\b` 等）不消费字符：视为可空，首字符集为空，
    // 让 `Concat` 继续向后累计真正消费字符的节点。
    Assert(_) => (true, { intervals: [] })
    // 前瞻/环视零宽且可能引入此处未消费的约束：保守视为可空、空首字符集。
    Look(..) => (true, { intervals: [] })
  }
}

///|
/// 从 AST 与编译标志推导预过滤策略（在 `compile_program` 中调用一次）。
///
/// 关键：当正则可空（nullable）时退化为 `PfNone`；启用忽略大小写时对首字符集
/// 施加 `case_fold`（折叠只会**扩大**集合，保持超集不变量），与 `emit_node`
/// 对 `IChar`/`ISet` 的折叠行为一致，从而保证预过滤永不漏过合法起点。
pub fn compute_prefilter(ast : Ast, flags : Flags) -> Prefilter {
  let (nullable, set) = ast_first_set(ast)
  if nullable {
    return PfNone
  }
  let folded = if flags.ignore_case { set.case_fold() } else { set }
  // 非可空但首字符集为空 => 该正则不可能匹配任何输入；保守返回 PfNone，
  // 交由 Pike VM 自然得出 `None`（不依赖预过滤做正确性判定）。
  if folded.intervals.length() == 0 {
    return PfNone
  }
  PfFirstSet(folded)
}

///|
/// 预过滤推进：返回首个 `>= pos` 的候选起点；无候选时返回 `n`。
///
/// 仅当上层 Pike VM 处于「尚未命中且无在飞线程」状态时调用本函数才安全——
/// 此时跳过中间位置不会丢弃任何处于匹配中途的线程（见 `exec_chars`）。
pub fn Prefilter::next_candidate(
  self : Prefilter,
  chars : Array[Char],
  n : Int,
  pos : Int,
) -> Int {
  match self {
    PfNone => pos
    PfFirstSet(set) => {
      let mut p = pos
      while p < n && !set.contains(chars[p].to_int()) {
        p = p + 1
      }
      p
    }
  }
}
