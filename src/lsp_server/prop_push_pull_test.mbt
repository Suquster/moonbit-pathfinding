// prop_push_pull_test.mbt —— push/pull 诊断等价属性测试（任务 13.4，Property 18）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 18「push/pull 诊断等价」：
//
//   *对任意* 由生成器产出的 DSL 文档 doc，经 **push 路径**
//   （`on_did_change` 产出 `Array[Diagnostic]`，并由
//   `publish_diagnostics_notification` 嵌入 `textDocument/publishDiagnostics`
//   通知）与 **pull 路径**（`pull_diagnostics` 对 `textDocument/diagnostic`
//   请求的响应）获取的诊断集合**彼此相等**——长度相等、且对应下标处诊断
//   （range / severity / message）完全一致。
//
// **Validates: Requirements 6.3**
//
// 设计依据：push 路径 `on_did_change` 与 pull 路径 `pull_diagnostics` 均复用同一
// 纯函数投影 `analyze(doc).diagnostics`（server.mbt / diagnostics.mbt），无 IO、
// 无全局可变状态，故对同一文档二者产出的诊断序列逐条相等，且 wasm-gc / js /
// native 三后端逐位一致。本属性除直接比较两路径返回的诊断序列外，还经由
// `publish_diagnostics_notification` 构造的 push 通知 params 中嵌入的诊断 JSON
// 数组，与 pull 诊断逐条经 `diagnostic_to_json` 编码所得数组对照，确保「push 实际
// 发布的载荷」与「pull 响应集合」在序列化层面同样等价。
//
// ── 「随机 DSL 文档」生成策略 ───────────────────────────────────────────
// 本文件为黑盒测试，仅依赖公开 API：`on_did_change` / `pull_diagnostics` /
// `analyze` / `publish_diagnostics_notification` / `diagnostic_to_json`、
// `TextDocument`（dsl.mbt）、`Diagnostic`（types.mbt，`derive(Eq)`）以及
// @lsp_binding 的 `Json` / `JsonRpcMessage`。
//
// 为让等价测试**非平凡**（确保诊断序列大概率非空且涵盖多种诊断），生成器
// `p18_gen_doc` 主动混入会触发各类诊断的行：合法赋值（含 `${ref}` 引用）、
// 缺少 '=' 行、非法键名行、重复定义、未闭合引用、空行 / 注释行。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增的 helper 均以 `p18_` 前缀命名，与同包既有测试 helper
// （`p10_*` / `p17_*` / `dsl_key_pool` 等）不重名。

// ---------------------------------------------------------------------------
// 随机 DSL 文档生成器（刻意混入多类诊断触发行）
// ---------------------------------------------------------------------------

///|
/// 合法键集合（小集合，便于在同一文档内重复出现以触发「重复定义」诊断）。
let p18_key_pool : Array[String] = ["k0", "k1", "key", "a", "name_1"]

///|
/// 值中字面片段池：不含 '$' / '{' / '}' / '=' / '\n' / 行首 '#'，避免误构成
/// 引用 / 第二个等号 / 注释 / 换行而破坏既定行结构。
let p18_literal_pool : Array[String] = ["x", "1", "val", "foo", "", "hi"]

///|
/// 引用名池：混合已声明键与未定义键（如 "zzz"），以制造「未定义引用」诊断。
let p18_ref_pool : Array[String] = ["k0", "k1", "zzz", "und", "a"]

///|
/// 生成一段含 0..2 处 `${ref}` 引用的 value 文本。
///
/// 注：经 `Char::from_int` 在**运行期**构造 `$` / `{` / `}`，避免源码中出现
/// 被常量折叠成字面 `${` 的片段（JS 后端会把悬空的 `${` 当作模板字符串插值起始，
/// 导致生成代码语法错误）；运行期仍得到 `${name}`。
fn p18_gen_value(rng : @infra_pbt.Rng) -> String {
  let dollar = Int::unsafe_to_char(0x24).to_string() // '$'
  let lbrace = Int::unsafe_to_char(0x7B).to_string() // '{'
  let rbrace = Int::unsafe_to_char(0x7D).to_string() // '}'
  let mut v = p18_literal_pool[rng.next_below(p18_literal_pool.length())]
  let refs = rng.next_below(3) // 0..2 处引用
  let mut i = 0
  while i < refs {
    let name = p18_ref_pool[rng.next_below(p18_ref_pool.length())]
    v = v +
      dollar +
      lbrace +
      name +
      rbrace +
      p18_literal_pool[rng.next_below(p18_literal_pool.length())]
    i = i + 1
  }
  v
}

///|
/// 生成一份随机 DSL 文档，逐行随机产出多种行型以覆盖各类诊断路径。
fn p18_gen_doc(rng : @infra_pbt.Rng) -> TextDocument {
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
      let key = p18_key_pool[rng.next_below(p18_key_pool.length())]
      text = text + key + " = " + p18_gen_value(rng) + "\n"
    }
    li = li + 1
  }
  { uri: "file:///prop18.dsl", text }
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn p18_gen_samples() -> @infra_pbt.Gen[TextDocument] {
  @infra_pbt.Gen::new(fn(rng) { p18_gen_doc(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词（Property 18）
// ---------------------------------------------------------------------------

///|
/// 逐条比较两个诊断序列：长度相等且对应下标处诊断完全相同（`Diagnostic`
/// `derive(Eq)`，故 `==` 同时比较 range / severity / message）。
fn p18_diagnostics_equal(
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
/// 从 `publish_diagnostics_notification` 构造的 push 通知中取出其携带的诊断
/// JSON 数组（params 对象的 `diagnostics` 字段）。形态不符（理论上不会发生）
/// 返回空数组以使后续比较失败。
fn p18_diagnostics_json_of_notification(
  msg : @lsp_binding.JsonRpcMessage,
) -> Array[@lsp_binding.Json] {
  match msg {
    @lsp_binding.Notification(params~, ..) =>
      match params {
        @lsp_binding.JObj(fields) => {
          for kv in fields {
            let (k, v) = kv
            if k == "diagnostics" {
              match v {
                @lsp_binding.JArr(arr) => return arr
                _ => return []
              }
            }
          }
          []
        }
        _ => []
      }
    _ => []
  }
}

///|
/// 将一组诊断逐条经 `diagnostic_to_json` 编码为 JSON 数组（与 push 通知内嵌入
/// 的诊断 JSON 同一编码路径）。
fn p18_encode_diagnostics(ds : Array[Diagnostic]) -> Array[@lsp_binding.Json] {
  let arr : Array[@lsp_binding.Json] = []
  for d in ds {
    arr.push(diagnostic_to_json(d))
  }
  arr
}

///|
/// 逐条比较两个诊断 JSON 数组（`Json` `derive(Eq)`）。
fn p18_json_array_equal(
  xs : Array[@lsp_binding.Json],
  ys : Array[@lsp_binding.Json],
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
/// 对文档 doc 判定「push/pull 诊断等价」是否成立：
///   (1) push 路径 `on_did_change(doc)` 与 pull 路径 `pull_diagnostics(doc)`
///       返回的诊断序列逐条相等；
///   (2) 由 push 诊断构造的 `publish_diagnostics_notification` 实际嵌入的诊断
///       JSON 数组，与 pull 诊断逐条经 `diagnostic_to_json` 编码所得数组相等
///       （序列化载荷层面的等价见证）。
fn p18_push_pull_equivalent(doc : TextDocument) -> Bool {
  let pushed = on_did_change(doc)
  let pulled = pull_diagnostics(doc)
  // (1) 诊断序列逐条相等。
  if !(p18_diagnostics_equal(pushed, pulled)) {
    return false
  }
  // (2) push 通知嵌入的诊断 JSON 与 pull 诊断编码数组相等。
  let notification = publish_diagnostics_notification(doc.uri, pushed)
  let pushed_json = p18_diagnostics_json_of_notification(notification)
  let pulled_json = p18_encode_diagnostics(pulled)
  p18_json_array_equal(pushed_json, pulled_json)
}

// ---------------------------------------------------------------------------
// 属性测试（Property 18）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 18: push/pull 诊断等价
///
/// 对任意由生成器产出的 DSL 文档：push 路径（`on_did_change` /
/// `publish_diagnostics_notification`）与 pull 路径（`pull_diagnostics`）得到的
/// 诊断集合彼此相等。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代
/// 100 次（≥100 基线）。
///
/// **Validates: Requirements 6.3**
test "Feature: lsp, Property 18: push and pull diagnostic paths yield equal diagnostic sets" {
  let ok = @infra_pbt.holds_for_all(p18_gen_samples(), fn(doc) {
    p18_push_pull_equivalent(doc)
  })
  assert_true(ok)
}
