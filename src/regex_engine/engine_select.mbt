// engine_select.mbt —— 引擎自动选择（T2.3）：按模式特征在字面量直扫 /
// 惰性 DFA / Pike VM 间自动择优，对调用方透明。
//
// 对标 Rust `regex` crate 的 meta engine：`Pattern::compile` 在编译期检查
// 程序特征（捕获组数、零宽断言 / 前瞻、纯字面量可得性、匹配策略），把每次
// 查询路由到语义等价的最廉价引擎：
//
//   * `EngLiteralScan` —— 模式是**纯字面量串**（无捕获 / 断言 / 选择 / 量词
//     残留，程序恰为 `ISave(0); IChar…; ISave(1); IMatch`）：匹配退化为子串
//     搜索，直接复用 `AcAutomaton` 单模式扫描，无需任何 VM 模拟。
//   * `EngLazyDfa` —— 无捕获组、无零宽断言 / 前瞻、最左最长策略：走按需
//     确定化的惰性 DFA（状态 = 待消费 pc 集，转移逐字符记忆），把重复转移
//     摊还为 O(1) 查表；状态缓存达到上限后无记忆继续（空间受限，永不爆炸）。
//     无优先级的 DFA 对无捕获程序天然给出「同起点最长」端点，与 Pike VM 的
//     LeftmostLongest 语义逐位一致。
//   * `EngPikeVm` —— 其余情形（需要捕获寄存器 / 位置相关 ε 转移 / 最左优先
//     剪枝语义）：回到 Pike VM 全功能路径。
//
// 决策可观测：`Pattern` 公开 `engine` 字段（`Show`），`without_auto_engine`
// 返回强制 Pike VM 的等价模式，供差分测试证明「路由不改变任何匹配语义」。

///|
/// 查询引擎选择结果（编译期确定，随 `Pattern` 携带）。
pub enum EngineChoice {
  /// 纯字面量子串直扫（AC 单模式）。
  EngLiteralScan
  /// 容量受限惰性 DFA（无捕获、无位置相关 ε 转移）。
  EngLazyDfa
  /// Pike VM 全功能路径。
  EngPikeVm
} derive(Eq)

///|
/// 惰性 DFA 状态缓存的状态数上限：达到后不再分配新状态，转移退化为
/// 逐次重算（空间换确定性，杜绝病态模式下的状态爆炸）。
const LAZY_DFA_STATE_CAP : Int = 512

///|
/// 若程序恰为「`ISave(0)`，若干 `IChar`，`ISave(1)`，`IMatch`」则提取其
/// 字面量字符序列（长度 ≥ 1）；否则返回 `None`。
fn program_literal(prog : Program) -> Array[Char]? {
  let m = prog.insts.length()
  if m < 4 {
    return None
  }
  if !(prog.insts[0] is ISave(0)) {
    return None
  }
  if !(prog.insts[m - 2] is ISave(1)) || !(prog.insts[m - 1] is IMatch) {
    return None
  }
  let lit : Array[Char] = []
  for k in 1..<(m - 2) {
    match prog.insts[k] {
      IChar(c) => lit.push(c)
      _ => return None
    }
  }
  if lit.length() == 0 {
    None
  } else {
    Some(lit)
  }
}

///|
/// 程序是否含位置相关 ε 转移（零宽断言 / 前瞻）——含则惰性 DFA 的
/// 「状态 = pc 集」身份不再成立，必须回 Pike VM。
fn program_has_positional(prog : Program) -> Bool {
  for inst in prog.insts {
    match inst {
      IAssert(_) | ILook(..) => return true
      _ => ()
    }
  }
  false
}

///|
/// 编译期引擎决策（T2.3 决策函数，`Pattern::compile` 调用一次）。
fn select_engine(prog : Program, kind : MatchKind) -> EngineChoice {
  match program_literal(prog) {
    // 纯字面量：两种最左策略对单一定长串给出同一「首次出现」，均可直扫。
    Some(_) => EngLiteralScan
    None =>
      if prog.num_groups == 0 &&
        !program_has_positional(prog) &&
        kind is LeftmostLongest {
        EngLazyDfa
      } else {
        EngPikeVm
      }
  }
}

///|
/// 惰性 DFA（Pike VM 程序版）：状态 = 排序去重的待消费 pc 集；`trans` 逐
/// 字符记忆后继状态 id。仅服务无捕获、无位置相关 ε 的程序（选择器保证）。
priv struct PvLazyDfa {
  prog : Program
  core_id : Map[String, Int]
  cores : Array[Array[Int]]
  accepts : Array[Bool]
  trans : Array[Map[Int, Int]]
}

///|
/// 新建空缓存的惰性 DFA。
fn PvLazyDfa::new(prog : Program) -> PvLazyDfa {
  { prog, core_id: Map([]), cores: [], accepts: [], trans: [] }
}

///|
/// pc 集的 ε 闭包：展开 `IJmp` / `ISplit`，穿透 `ISave`（无捕获路径下写槽
/// 是无操作），在 `IChar` / `ISet` / `IMatch` 处终结；按 pc 去重后排序，
/// 保证状态身份规范化。
fn PvLazyDfa::closure(self : PvLazyDfa, pcs : Array[Int]) -> Array[Int] {
  let seen = Array::make(self.prog.insts.length(), false)
  let out : Array[Int] = []
  let stack : Array[Int] = []
  for pc in pcs {
    stack.push(pc)
  }
  while stack.length() > 0 {
    let pc = stack.unsafe_pop()
    if seen[pc] {
      continue
    }
    seen[pc] = true
    match self.prog.insts[pc] {
      IJmp(x) => stack.push(x)
      ISplit(a, b) => {
        stack.push(a)
        stack.push(b)
      }
      ISave(_) => stack.push(pc + 1)
      _ => out.push(pc)
    }
  }
  out.sort()
  out
}

///|
/// pc 集编码为缓存键。
fn encode_pcs(core : Array[Int]) -> String {
  let sb = @infra_text.TextBuilder::new()
  for pc in core {
    sb.push_str(pc.to_string())
    sb.push_char(',')
  }
  sb.build()
}

///|
/// 物化状态：命中复用；未命中且未达 `LAZY_DFA_STATE_CAP` 则分配新 id；
/// 容量已满返回 -1（调用方转入无记忆路径）。
fn PvLazyDfa::intern(self : PvLazyDfa, core : Array[Int]) -> Int {
  let key = encode_pcs(core)
  match self.core_id.get(key) {
    Some(id) => id
    None =>
      if self.cores.length() >= LAZY_DFA_STATE_CAP {
        -1
      } else {
        let id = self.cores.length()
        self.core_id[key] = id
        self.cores.push(core)
        let mut acc = false
        for pc in core {
          if self.prog.insts[pc] is IMatch {
            acc = true
          }
        }
        self.accepts.push(acc)
        self.trans.push(Map([]))
        id
      }
  }
}

///|
/// pc 集是否含 `IMatch`（无记忆路径的接受判定）。
fn PvLazyDfa::core_accepts(self : PvLazyDfa, core : Array[Int]) -> Bool {
  for pc in core {
    if self.prog.insts[pc] is IMatch {
      return true
    }
  }
  false
}

///|
/// 状态（id `sid` 或裸核 `core`）消费码点 `code` 的后继核；死路返回空数组。
/// 双方均有稳定 id 时记忆转移。
fn PvLazyDfa::step(
  self : PvLazyDfa,
  sid : Int,
  core : Array[Int],
  code : Int,
) -> (Int, Array[Int]) {
  if sid >= 0 {
    match self.trans[sid].get(code) {
      Some(t) => return (t, self.cores[t])
      None => ()
    }
  }
  let moved : Array[Int] = []
  for pc in core {
    match self.prog.insts[pc] {
      IChar(ch) => if ch.to_int() == code { moved.push(pc + 1) }
      ISet(cs) => if cs.contains(code) { moved.push(pc + 1) }
      _ => ()
    }
  }
  if moved.length() == 0 {
    return (-1, [])
  }
  let next = self.closure(moved)
  let nsid = self.intern(next)
  if sid >= 0 && nsid >= 0 {
    self.trans[sid][code] = nsid
  }
  (nsid, next)
}

///|
/// 自锚定起点 `start` 模拟，返回最长接受端点；不可达返回 `None`。
fn PvLazyDfa::match_at(
  self : PvLazyDfa,
  chars : Array[Char],
  n : Int,
  start : Int,
) -> Int? {
  let start_core = self.closure([0])
  let mut sid = self.intern(start_core)
  let mut core = start_core
  let mut best : Int? = None
  let mut pos = start
  while true {
    let acc = if sid >= 0 { self.accepts[sid] } else { self.core_accepts(core) }
    if acc {
      best = Some(pos)
    }
    if pos >= n {
      break
    }
    let (nsid, ncore) = self.step(sid, core, chars[pos].to_int())
    if ncore.length() == 0 {
      break
    }
    sid = nsid
    core = ncore
    pos = pos + 1
  }
  best
}

///|
/// 惰性 DFA 最左最长搜索：自 `from` 起逐起点尝试（预过滤跳过不可能起点），
/// 首个可匹配起点取其最长端点。状态缓存跨起点共享。
fn PvLazyDfa::find_from(
  self : PvLazyDfa,
  chars : Array[Char],
  n : Int,
  from : Int,
) -> Match? {
  let mut s = from
  while s <= n {
    match self.prog.prefilter {
      PfNone => ()
      PfFirstSet(_) | PfLiterals(_) => {
        let np = self.prog.prefilter.next_candidate(chars, n, s)
        // 预过滤只在非可空程序上启用（compute_prefilter 保证），故无候选
        // 起点（np >= n）即不可能再有匹配。
        if np >= n {
          return None
        }
        s = np
      }
    }
    match self.match_at(chars, n, s) {
      Some(endp) => return Some({ start: s, end: endp })
      None => s = s + 1
    }
  }
  None
}

///|
/// 字面量直扫：`AcAutomaton` 单模式定位首次出现（保守候选逐一验证）。
fn literal_find_from(
  lit : Array[Char],
  ac : AcAutomaton,
  chars : Array[Char],
  n : Int,
  from : Int,
) -> Match? {
  let m = lit.length()
  let mut s = from
  while s + m <= n {
    let cand = ac.next_candidate(chars, n, s)
    if cand + m > n {
      return None
    }
    let mut eq = true
    for k in 0..<m {
      if chars[cand + k] != lit[k] {
        eq = false
        break
      }
    }
    if eq {
      return Some({ start: cand, end: cand + m })
    }
    s = cand + 1
  }
  None
}
