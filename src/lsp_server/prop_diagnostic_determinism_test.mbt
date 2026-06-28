// prop_diagnostic_determinism_test.mbt —— 诊断确定性属性测试（任务 13.3，Property 10）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 10「诊断确定性」：
//
//   *对任意* 由生成器产出的 DSL 文档 doc，对同一文档**多次**分析（无论经
//   `analyze(doc).diagnostics` 还是 `pull_diagnostics(doc)`）所得诊断序列
//   **逐条相同**——即长度相等、且对应下标处的诊断（range / severity / message）
//   完全一致，**顺序与内容均不变**。
//
// **Validates: Requirements 6.5, 9.2**
//
// 设计依据：`analyze` 为纯函数（无 IO / 无全局可变状态），其诊断收集顺序由
// 源文本的行/列出现顺序唯一决定（dsl.mbt：第一遍逐行收集语法/重复定义/未闭合
// 引用诊断，第二遍按引用出现顺序收集未定义引用诊断）。因此对同一文档多次调用
// 必产出逐条相同的诊断序列，且 wasm-gc / js / native 三后端逐位一致。
//
// ── 「随机 DSL 文档」生成策略（保证属性非平凡且可靠）─────────────────────
// 本文件为黑盒测试，仅依赖 dsl.mbt 的公开 API（`analyze` / `TextDocument` /
// `Analysis`）、diagnostics.mbt 的 `pull_diagnostics`，以及 types.mbt 的
// `Diagnostic`（`derive(Eq)`，谓词以 `==` 逐条比较）。
//
// 为让确定性测试**非平凡**（确保诊断序列大概率非空且涵盖多种诊断），生成器
// `p10_gen_doc` 主动混入会触发各类诊断的行：
//   * 合法赋值行 `key = value`（含 `${ref}` 引用，可触发「未定义引用」Warning）；
//   * 缺少 '=' 的行（触发「缺少 '='」Error）；
//   * 非法键名行（如以数字开头，触发「非法的键名」Error）；
//   * 重复定义同名键（触发「重复定义键」Warning）；
//   * 未闭合引用 `${name`（触发「未闭合或非法的引用」Error）；
//   * 空行 / 注释行（覆盖忽略路径）。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增的 helper 均以 `p10_` 前缀命名，与同包既有测试 helper
// （`dsl_key_pool` / `gen_dsl_doc` / `p17_*` 等）不重名。

// ---------------------------------------------------------------------------
// 随机 DSL 文档生成器（刻意混入多类诊断触发行）
// ---------------------------------------------------------------------------

///|
/// 合法键集合（小集合，便于在同一文档内重复出现以触发「重复定义」诊断）。
let p10_key_pool : Array[String] = ["k0", "k1", "key", "a", "name_1"]

///|
/// 值中字面片段池：不含 '$' / '{' / '}' / '=' / '\n' / 行首 '#'，避免误构成
/// 引用 / 第二个等号 / 注释 / 换行而破坏既定行结构。
let p10_literal_pool : Array[String] = ["x", "1", "val", "foo", "", "hi"]

///|
/// 引用名池：混合已声明键与未定义键（如 "zzz"），以制造「未定义引用」诊断。
let p10_ref_pool : Array[String] = ["k0", "k1", "zzz", "und", "a"]

///|
/// 生成一段含 0..2 处 `${ref}` 引用的 value 文本。
///
/// 注：经 `Char::from_int` 在**运行期**构造 `$` / `{` / `}`，避免源码中出现
/// 被常量折叠成字面 `${` 的片段（JS 后端会把悬空的 `${` 当作模板字符串插值起始，
/// 导致生成代码语法错误）；运行期仍得到 `${name}`。
fn p10_gen_value(rng : @infra_pbt.Rng) -> String {
  let dollar = Int::unsafe_to_char(0x24).to_string() // '$'
  let lbrace = Int::unsafe_to_char(0x7B).to_string() // '{'
  let rbrace = Int::unsafe_to_char(0x7D).to_string() // '}'
  let mut v = p10_literal_pool[rng.next_below(p10_literal_pool.length())]
  let refs = rng.next_below(3) // 0..2 处引用
  let mut i = 0
  while i < refs {
    let name = p10_ref_pool[rng.next_below(p10_ref_pool.length())]
    v = v +
      dollar +
      lbrace +
      name +
      rbrace +
      p10_literal_pool[rng.next_below(p10_literal_pool.length())]
    i = i + 1
  }
  v
}

///|
/// 生成一份随机 DSL 文档，逐行随机产出多种行型以覆盖各类诊断路径。
fn p10_gen_doc(rng : @infra_pbt.Rng) -> TextDocument {
  let n_lines = rng.next_range(2, 8) // 2..7 行
  let dollar = Int::unsafe_to_char(0x24).to_string() // '$'
  let lbrace = Int::unsafe_to_char(0x7B).to_string() // '{'
  let mut text = ""
  let mut li = 0
  while li < n_lines {
    let kind = rng.next_below(7)
    if kind == 0 {
      // 空行（忽略路径）。
      text = text + "\n"
    } else if kind == 1 {
      // 注释行（忽略路径）。
      text = text + "# comment line\n"
    } else if kind == 2 {
      // 缺少 '=' 的非空行 → 「缺少 '='」Error。
      text = text + "bare_token_here\n"
    } else if kind == 3 {
      // 非法键名（数字开头）→ 「非法的键名」Error。
      text = text + "9bad = value\n"
    } else if kind == 4 {
      // 未闭合引用 → 「未闭合或非法的引用」Error。
      text = text + "ref_line = " + dollar + lbrace + "k0\n"
    } else {
      // 合法赋值行（可能含已定义/未定义引用）。
      let key = p10_key_pool[rng.next_below(p10_key_pool.length())]
      text = text + key + " = " + p10_gen_value(rng) + "\n"
    }
    li = li + 1
  }
  { uri: "file:///prop10.dsl", text }
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn p10_gen_samples() -> @infra_pbt.Gen[TextDocument] {
  @infra_pbt.Gen::new(fn(rng) { p10_gen_doc(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词（Property 10）
// ---------------------------------------------------------------------------

///|
/// 逐条比较两个诊断序列：长度相等且对应下标处诊断完全相同（`Diagnostic`
/// `derive(Eq)`，故 `==` 同时比较 range / severity / message）。
fn p10_diagnostics_equal(
  xs : Array[Diagnostic],
  ys : Array[Diagnostic],
) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let mut i = 0
  while i < xs.length() {
    if xs[i] != ys[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 对文档 doc 判定「诊断确定性」是否成立：对同一文档多次分析所得诊断序列彼此
/// 逐条相同。同时跨 `analyze(doc).diagnostics` 与 `pull_diagnostics(doc)` 两条
/// 入口验证（二者均复用同一 `analyze` 投影），以基线序列对照后续每一次重分析。
fn p10_diagnostics_deterministic(doc : TextDocument) -> Bool {
  let baseline = analyze(doc).diagnostics
  // 多次重分析（≥3 次）：每次都应与基线逐条相同（顺序与内容一致）。
  let mut round = 0
  while round < 4 {
    let again = analyze(doc).diagnostics
    if !p10_diagnostics_equal(baseline, again) {
      return false
    }
    // pull 入口同样走 analyze 投影，亦应与基线逐条相同。
    let pulled = pull_diagnostics(doc)
    if !p10_diagnostics_equal(baseline, pulled) {
      return false
    }
    round = round + 1
  }
  true
}

// ---------------------------------------------------------------------------
// 属性测试（Property 10）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 10: 诊断确定性
///
/// 对任意由生成器产出的 DSL 文档：对同一文档多次分析得到逐条相同（顺序与内容
/// 一致）的诊断序列。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代
/// 100 次（≥100 基线）。
///
/// **Validates: Requirements 6.5, 9.2**
test "Feature: lsp, Property 10: diagnostics are deterministic across repeated analysis of the same document" {
  let ok = @infra_pbt.holds_for_all(p10_gen_samples(), fn(doc) {
    p10_diagnostics_deterministic(doc)
  })
  assert_true(ok)
}
