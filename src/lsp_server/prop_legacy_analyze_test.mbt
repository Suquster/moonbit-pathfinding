// prop_legacy_analyze_test.mbt —— 既有分析不变属性测试（任务 15.1，Property 11）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 11「既有分析不变」：
//
//   *对任意* 仅使用**既有 DSL 文法**（`key = value`，含 `${ref}` 引用与 `#`
//   整行注释）的文档 doc，深化后的 `analyze` 产出的符号、引用与诊断与 `0.1.0`
//   行为**相等**——即以一份「冻结黄金基线」（frozen golden baseline）对照，
//   逐项一致。
//
// **Validates: Requirements 10.8**
//
// ── 黄金基线（golden baseline）的取得方式 ──────────────────────────────
// 为使「不变性」成为**非平凡**且**独立**的对照（而非把 `analyze` 自我比较的
// 平凡恒等），本文件不调用 `analyze` 来构造期望值，而是在**生成文档的同时**，
// 依 `0.1.0` 既有文法语义（见 moon.pkg 文法声明与 dsl.mbt 文档注释）**独立
// 地、按结构地**重新推导出期望的 `Analysis`（符号 / 引用 / 诊断，含精确的
// 行列范围 `Range`）。随后断言 `analyze(doc)` 与该独立重导出的黄金基线逐项
// 相等。
//
// 这样得到的对照满足任务要求的「最稳健做法」：生成器知道自己产出了什么，于是
// 由生成结构直接计算期望的符号 / 引用 / 诊断，与 `analyze` 输出比较。任何对
// 既有文法分析语义的回归（符号表、引用范围、诊断种类/顺序/范围/文案）都会令该
// 属性失败。
//
// ── 仅使用既有文法的随机文档生成策略 ──────────────────────────────────
// 生成器 `p11_gen_expected` 逐行随机产出**既有文法**覆盖的各类行型，并同步记录
// 期望产物（行列范围按 dsl.mbt 既有列算法精确推导）：
//   * 空行 / `#` 注释行（忽略路径，无产物）；
//   * 合法赋值 `key = value`（plain 值，产出符号 / 重复定义 Warning）；
//   * 合法赋值含闭合引用 `key = ${ref}`（产出符号 + 引用；未定义引用 Warning）；
//   * 缺 '=' 的裸 token（「缺少 '='」Error）；
//   * 非法键名（数字开头，「非法的键名」Error）；
//   * 未闭合引用 `key = ${ref`（「未闭合或非法的引用」Error，仍产出符号）。
//
// 列号说明：所有行内容均为 ASCII（键 / 字面 / 引用名 / `=` / 空格 / `${}`），
// 故按 `String::length()`（UTF-16 码元数）推导的列号与 dsl.mbt 的码位列号一致。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增的 helper 均以 `p11_` 前缀命名，与同包既有测试 helper
// （`p10_*` / `p17_*` 等）不重名。

// ---------------------------------------------------------------------------
// 池与小工具
// ---------------------------------------------------------------------------

///|
/// 合法键集合（小集合，便于在同一文档内重复出现以触发「重复定义」诊断；亦使
/// 引用命中已定义键的概率提升，从而覆盖「已定义引用」与「未定义引用」两条路径）。
let p11_key_pool : Array[String] = ["k0", "k1", "key", "a", "name_1"]

///|
/// 值中字面片段池：不含 '$' / '{' / '}' / '=' / '\n' / 空白 / 行首 '#'，避免
/// 误构成引用 / 第二个等号 / 注释 / 换行 / 被 trim 而扰乱既定列结构。
let p11_literal_pool : Array[String] = ["x", "1", "val", "foo", "hi", ""]

///|
/// 引用名池：混合已声明键与必然未定义键（"zzz" / "und"），制造「未定义引用」诊断。
let p11_ref_pool : Array[String] = ["k0", "k1", "zzz", "und", "a"]

///|
/// 构造单行范围 `[a, b)`（同一行 `li`）。本地实现，避免依赖 dsl.mbt 的私有
/// `span`（黑盒测试不可见私有项）；`Position` / `Range` 均为 `pub(all)`。
fn p11_span(li : Int, a : Int, b : Int) -> Range {
  { start: { line: li, character: a }, end: { line: li, character: b } }
}

///|
/// 线性判定字符串是否已在已定义键集合中（避免依赖 Map API，逻辑等价于
/// dsl.mbt 的 `defined.get(key)` 命中判定）。
fn p11_contains(xs : Array[String], s : String) -> Bool {
  for x in xs {
    if x == s {
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// 随机既有文法文档生成器 + 同步独立重导出的黄金基线
// ---------------------------------------------------------------------------

///|
/// 生成一份仅含既有文法的随机 DSL 文档，并依 `0.1.0` 既有语义独立、按结构地
/// 重新推导出期望的 `Analysis`（符号 / 引用 / 诊断，含精确范围）。
///
/// 返回 (文档, 黄金基线 Analysis)。属性谓词据此断言 `analyze(doc)` 与基线相等。
///
/// 诊断顺序严格对齐 dsl.mbt：第一遍逐行收集（语法错误 / 重复定义 / 未闭合引用，
/// 同一行内「重复定义」先于「未闭合引用」），第二遍按引用出现顺序收集「未定义
/// 引用」诊断。
fn p11_gen_expected(rng : @infra_pbt.Rng) -> (TextDocument, Analysis) {
  // 运行期构造 '$' / '{' / '}'，避免源码出现被常量折叠的悬空 `${`（JS 后端会
  // 误判为模板字符串插值起始）；运行期仍得到 `${name}`。
  let dollar = Char::from_int(0x24).to_string() // '$'
  let lbrace = Char::from_int(0x7B).to_string() // '{'
  let rbrace = Char::from_int(0x7D).to_string() // '}'
  let symbols : Array[Symbol] = []
  let references : Array[Reference] = []
  // 第一遍诊断（行顺序）。
  let diags1 : Array[Diagnostic] = []
  // 已定义键（首次定义为权威；用于重复定义判定与第二遍未定义引用判定）。
  let defined : Array[String] = []
  let mut text = ""
  let n_lines = rng.next_range(2, 9) // 2..8 行
  let mut li = 0
  while li < n_lines {
    let kind = rng.next_below(7)
    if kind == 0 {
      // 空行（忽略路径）。
      text = text + "\n"
    } else if kind == 1 {
      // 注释行（忽略路径）。
      let lit = p11_literal_pool[rng.next_below(p11_literal_pool.length())]
      text = text + "#" + lit + "\n"
    } else if kind == 2 {
      // 缺少 '=' 的裸 token → 「缺少 '='」Error，范围 [0, n)。
      let tok = "bareword"
      diags1.push({
        range: p11_span(li, 0, tok.length()),
        severity: Error,
        message: "缺少 '='：期望形如 key = value 的赋值",
      })
      text = text + tok + "\n"
    } else if kind == 3 {
      // 非法键名（数字开头）→ 「非法的键名」Error，范围 [0, eq)。
      let body = "9bad"
      let val = "val"
      let eq = body.length() + 1 // '=' 位于 body 后空格之后
      diags1.push({
        range: p11_span(li, 0, eq),
        severity: Error,
        message: "非法的键名（须为标识符 [A-Za-z_][A-Za-z0-9_]*）",
      })
      text = text + body + " = " + val + "\n"
    } else if kind == 4 {
      // 合法赋值，plain 值（无引用）。
      let key = p11_key_pool[rng.next_below(p11_key_pool.length())]
      let lit = p11_literal_pool[rng.next_below(p11_literal_pool.length())]
      let k = key.length()
      let key_range = p11_span(li, 0, k)
      if p11_contains(defined, key) {
        diags1.push({
          range: key_range,
          severity: Warning,
          message: "重复定义键：" + key,
        })
      } else {
        defined.push(key)
        symbols.push({ name: key, range: key_range, value: lit })
      }
      text = text + key + " = " + lit + "\n"
    } else if kind == 5 {
      // 合法赋值，含一处闭合引用 `${ref}`。
      let key = p11_key_pool[rng.next_below(p11_key_pool.length())]
      let refn = p11_ref_pool[rng.next_below(p11_ref_pool.length())]
      let k = key.length()
      let key_range = p11_span(li, 0, k)
      let value = dollar + lbrace + refn + rbrace // "${ref}"
      if p11_contains(defined, key) {
        diags1.push({
          range: key_range,
          severity: Warning,
          message: "重复定义键：" + key,
        })
      } else {
        defined.push(key)
        symbols.push({ name: key, range: key_range, value })
      }
      // 引用范围：行内容 `key = ${ref}` 中 '$' 位于列 k+3，'}' 位于 k+3+(refn+2)，
      // end 排他 = 起点 + len(refn) + 3。
      let c = k + 3
      references.push({
        name: refn,
        range: p11_span(li, c, c + refn.length() + 3),
      })
      text = text + key + " = " + value + "\n"
    } else {
      // kind == 6：未闭合引用 `key = ${ref`（行尾缺 '}'）→ 「未闭合或非法的引用」
      // Error；该行仍是合法赋值，故照常产出符号 / 重复定义诊断。
      let key = p11_key_pool[rng.next_below(p11_key_pool.length())]
      let refn = p11_ref_pool[rng.next_below(p11_ref_pool.length())]
      let k = key.length()
      let key_range = p11_span(li, 0, k)
      let value = dollar + lbrace + refn // "${ref"（无闭合花括号）
      if p11_contains(defined, key) {
        diags1.push({
          range: key_range,
          severity: Warning,
          message: "重复定义键：" + key,
        })
      } else {
        defined.push(key)
        symbols.push({ name: key, range: key_range, value })
      }
      // 未闭合诊断范围：'$' 列 k+3 至行尾 n（标识符扫描止于行尾）。
      let line_text = key + " = " + value
      let n = line_text.length()
      diags1.push({
        range: p11_span(li, k + 3, n),
        severity: Error,
        message: "未闭合或非法的引用（期望 " +
        dollar +
        lbrace +
        "name" +
        rbrace +
        "）",
      })
      text = text + line_text + "\n"
    }
    li = li + 1
  }
  // 第二遍：按引用出现顺序收集「未定义引用」诊断（对照最终 defined 集合）。
  let diagnostics : Array[Diagnostic] = []
  for d in diags1 {
    diagnostics.push(d)
  }
  for r in references {
    if not(p11_contains(defined, r.name)) {
      diagnostics.push({
        range: r.range,
        severity: Warning,
        message: "引用了未定义的键：" + r.name,
      })
    }
  }
  let doc : TextDocument = { uri: "file:///prop11_legacy.dsl", text }
  let expected : Analysis = { uri: doc.uri, symbols, references, diagnostics }
  (doc, expected)
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn p11_gen_samples() -> @infra_pbt.Gen[(TextDocument, Analysis)] {
  @infra_pbt.Gen::new(fn(rng) { p11_gen_expected(rng) })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 11）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 11: 既有分析不变
///
/// 对任意仅含既有文法的随机 DSL 文档，`analyze` 产出的符号 / 引用 / 诊断与按
/// `0.1.0` 语义独立重导出的冻结黄金基线逐项相等（`Analysis` `derive(Eq)`，故
/// `==` 同时比较 uri / symbols / references / diagnostics）。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 10.8**
test "Feature: lsp, Property 11: legacy analyze invariance against a frozen golden baseline" {
  let ok = @infra_pbt.holds_for_all(p11_gen_samples(), fn(pair) {
    let (doc, expected) = pair
    analyze(doc) == expected
  })
  assert_true(ok)
}
