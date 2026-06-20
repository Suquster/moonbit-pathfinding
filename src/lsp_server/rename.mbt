// rename.mbt —— 重命名（WorkspaceEdit / TextEdit）与编辑应用（任务 10.1）。
//
// 设计依据（design.md §3.5「扩展语言能力」，Requirement 5.4）：
// 本文件为**旁路新增**，不改 `analyze`/`dsl.mbt`/`types.mbt` 既有行为，全部能力
// 复用既有 `Analysis` 的 `symbols`/`references` 投影：
//
//   * rename（5.4） —— 将某符号的全部出现一致改名，产出 `WorkspaceEdit`；
//   * apply_workspace_edit —— 把一组 `TextEdit` 应用到单文档文本（供
//     Property 9「重命名完整性」验证）。
//
// paper-to-code 追溯：LSP §「Language Features」之 `textDocument/rename` 与
// `WorkspaceEdit`/`TextEdit`。
//
// ── 关键语义（务必正确） ─────────────────────────────────────────────
// 既有 `dsl.mbt` 对符号与引用范围的约定不同：
//   * `Symbol.range` 覆盖**裸键 token**（`key`），故定义处替换文本为裸 `new_name`；
//   * `Reference.range` 覆盖 `${name}` **整体**（含 `${` 与 `}`，见
//     `scan_references`：`range = span(li, start, j + 1)`，`start` 指向 '$'、
//     `j + 1` 在 '}' 之后），故引用处替换文本须为 `${new_name}`（保留 `${}`
//     包裹），否则破坏 DSL 引用语法。
// 因此 `rename` 生成的 `TextEdit`：
//   * 定义：`{ range: symbol.range, new_text: new_name }`；
//   * 每个同名引用：`{ range: ref.range, new_text: "${" + new_name + "}" }`。
//
// 注：`${` / `{` / `}` 一律经 `Char::from_int` 在**运行期**构造，避免源码中出现
// 字面 `${` 片段（JS 后端会把悬空 `${` 当作模板字符串插值起始，导致生成代码语法
// 错误）；运行期仍得到正确的 `${new_name}`。
//
// ── 编码约定 ─────────────────────────────────────────────────────────
// `dsl.mbt` 的列号以 `line_chars`（按 Unicode 码位/字符遍历）计量，即**每码位 1
// 列**。故 `apply_workspace_edit` 在把 `Range` 解析回码位线性索引时，复用同包
// `sync.mbt` 的私有 `position_to_cp_index`（同 package 可见）并以
// `PositionEncoding::Utf32`（每码位 1 码元）解释列号，与 `dsl.mbt` 列号语义一致。
//
// 确定性约定（design.md §「三后端一致性」）：编辑顺序由源文本出现顺序决定
// （定义在前、引用按出现顺序追加），`apply_workspace_edit` 按起点升序拼接，
// 保证 wasm-gc / js / native 三后端逐位一致。

// ───────────────────────────── 编辑模型 ───────────────────────────────

///|
/// 一处文本编辑：作用范围 `range` + 替换文本 `new_text`。
///
/// 注：`Range`（同包 `types.mbt`）仅 `derive(Eq)`（无 `Show`），故本结构同样
/// 仅 `derive(Eq)`。
pub(all) struct TextEdit {
  range : Range
  new_text : String
} derive(Eq)

///|
/// 工作区编辑：按文档归类的编辑集合 `changes`，每项为 `(uri, edits)`。
/// 本方向为单工作区内存多文档；`rename` 产出单文档项 `[(a.uri, edits)]`。
pub(all) struct WorkspaceEdit {
  changes : Array[(String, Array[TextEdit])]
} derive(Eq)

// ───────────────────────────── 引用包裹文本构造 ───────────────────────

///|
/// 在运行期构造 `${name}`（避免源码字面 `${`）。
fn wrap_reference(name : String) -> String {
  let dollar = Char::from_int(0x24).to_string() // '$'
  let lbrace = Char::from_int(0x7B).to_string() // '{'
  let rbrace = Char::from_int(0x7D).to_string() // '}'
  dollar + lbrace + name + rbrace
}

// ───────────────────────────── rename（5.4） ──────────────────────────

///|
/// 将某符号 `name` 的全部出现改名为 `new_name`，产出 `WorkspaceEdit`
/// （Requirement 5.4）。
///
///   * 若存在该名定义，则对其裸键 token 生成一条替换为 `new_name` 的编辑；
///   * 对每个同名引用（token 覆盖 `${name}`），生成一条替换为 `${new_name}`
///     的编辑（保留 `${}` 包裹）。
///
/// 编辑顺序：定义在前，随后按 `references` 的源文本出现顺序追加同名引用；
/// 全部归入单文档项 `(a.uri, edits)`。
pub fn rename(a : Analysis, name : String, new_name : String) -> WorkspaceEdit {
  let edits : Array[TextEdit] = []
  // 定义处：替换裸键 token 为裸 new_name。
  match lookup_symbol(a, name) {
    Some(s) => edits.push({ range: s.range, new_text: new_name })
    None => ()
  }
  // 引用处：替换 ${name} 整体为 ${new_name}。
  let replacement = wrap_reference(new_name)
  for r in a.references {
    if r.name == name {
      edits.push({ range: r.range, new_text: replacement })
    }
  }
  { changes: [(a.uri, edits)] }
}

// ───────────────────────────── apply_workspace_edit ───────────────────

///|
/// 把一组互不重叠的 `TextEdit` 应用到单文档文本 `text`，返回新文本
/// （供 Property 9「重命名完整性」验证）。
///
/// 实现：
///   1. 将 `text` 解析为码位序列；
///   2. 用 `position_to_cp_index`（`Utf32` 列号语义，与 `dsl.mbt` 一致）把每条
///      编辑的 `range.start`/`range.end` 解析为码位线性索引 `[si, ei)`；
///      无法解析（越界 / 非码位边界 / start > end）的编辑被跳过；
///   3. 按起点 `si` 升序排序（插入排序，编辑数少）；
///   4. 顺序拼接：未编辑区间原样保留、编辑区间替换为 `new_text`。
///
/// 编辑互不重叠（同一文档不同 token），升序拼接即可正确且确定性地重建文本。
pub fn apply_workspace_edit(text : String, edits : Array[TextEdit]) -> String {
  let cps = to_codepoints(text)
  let total = cps.length()
  // 解析每条编辑为码位区间 (si, ei, new_text)。
  let resolved : Array[(Int, Int, String)] = []
  for e in edits {
    match position_to_cp_index(cps, e.range.start, Utf32) {
      Some(si) =>
        match position_to_cp_index(cps, e.range.end, Utf32) {
          Some(ei) => if si <= ei { resolved.push((si, ei, e.new_text)) }
          None => ()
        }
      None => ()
    }
  }
  // 插入排序：按起点 si 升序。
  let n = resolved.length()
  let mut i = 1
  while i < n {
    let cur = resolved[i]
    let mut j = i - 1
    while j >= 0 && resolved[j].0 > cur.0 {
      resolved[j + 1] = resolved[j]
      j = j - 1
    }
    resolved[j + 1] = cur
    i = i + 1
  }
  // 顺序拼接：原样区间 + 替换文本。
  let mut out = ""
  let mut pos = 0
  for item in resolved {
    let si = item.0
    let ei = item.1
    let nt = item.2
    if si >= pos {
      out = out + rebuild(cps, pos, si) + nt
      pos = ei
    }
  }
  out + rebuild(cps, pos, total)
}
