// incremental_sync.mbt —— 单条增量文档变更的 O(N) 应用
// （旗舰深化，任务 11.2 旁路新增）。
//
// paper-to-code 追溯（design.md §「LSP 协议鲁棒性设计」/ Requirement 10.4 / 10.5）：
//   * LSP 规范 `textDocument/didChange`：`Incremental` 模式下，单条
//     `TextDocumentContentChangeEvent` 含变更范围 `range`（闭开区间 [start, end)）
//     与替换文本 `text`，将该范围对应的字符区间替换为 `text`；`Full` 模式
//     （`range = None`）则以 `text` 整体替换全文。
//     <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange>
//
// 与既有 `apply_changes`（sync.mbt）的一致性保证（AC4）：
//   本函数**复用与 `apply_changes` 单条变更分支完全相同的换算与切片工具**——
//   `to_codepoints`（文本→Unicode 码位序列）、`position_to_cp_index`
//   （`Position` + `PositionEncoding` → 全局码位线性索引，与编码口径一致）、
//   `rebuild`（码位子区间→字符串）。因此对同一 `(doc, change, enc)`，
//   `apply_incremental(doc, change, enc)` 的结果与 `apply_changes(doc, [change], enc)`
//   逐字符一致：二者走的是同一段换算逻辑，避免重新实现编码换算导致的偏差。
//
// 复杂度（AC5，目标 O(N)，N 为文档码位数）：
//   1. `to_codepoints` 单趟遍历文本：O(N)。
//   2. `position_to_cp_index` 对 start / end 各一趟线性遍历码位：O(N)。
//   3. 切片重建 `prefix ++ text ++ suffix`：`rebuild` 各 O(N)，仅两次单点 `+`
//      （非循环内拼接），整体 O(N + M)（M 为替换文本长度）。
//   故单条增量变更对文档长度 N 呈线性 O(N)，优于逐字符串 `+` 的 O(n²)。
//
// 错误处理：范围越界、列号落在多码元字符中间、或 `start > end` 时，返回携带
// 定位信息的 `Err(@lsp_binding.invalid_params_code, ..)`，与 `apply_changes`
// 语义一致；不返回任何部分应用结果。

///|
/// 对单条基于范围的增量变更求新文本（Requirement 10.4 / 10.5）。
///
///   * `change.range = None`（Full）：等价于全量替换，结果为 `change.text`。
///   * `change.range = Some(r)`（Incremental）：把 `r` 对应的码位区间 `[si, ei)`
///     替换为 `change.text`，其余原样保留。
///
/// 结果与既有 `apply_changes(doc, [change], enc)` 对单条变更的结果一致（复用
/// `to_codepoints` / `position_to_cp_index` / `rebuild`）。范围越界、非码位边界
/// 或 `start > end` 返回 `Err(@lsp_binding.invalid_params_code, ..)`。
pub fn apply_incremental(
  doc : String,
  change : ContentChange,
  encoding : PositionEncoding,
) -> Result[String, @lsp_binding.RpcError] {
  match change.range {
    // Full：整个文档替换为 change.text。
    None => Ok(change.text)
    // Incremental：仅替换受影响范围。
    Some(r) => {
      // 一次性把文档物化为码位序列（O(N)）。
      let cps = to_codepoints(doc)
      // 起点 / 终点换算（复用 apply_changes 的同一换算，保证一致）。
      let si = match position_to_cp_index(cps, r.start, encoding) {
        Some(s) => s
        None =>
          return Err(
            @lsp_binding.RpcError::new(
              @lsp_binding.invalid_params_code,
              "content change range.start out of bounds at line \{r.start.line}, character \{r.start.character}",
            ),
          )
      }
      let ei = match position_to_cp_index(cps, r.end, encoding) {
        Some(e) => e
        None =>
          return Err(
            @lsp_binding.RpcError::new(
              @lsp_binding.invalid_params_code,
              "content change range.end out of bounds at line \{r.end.line}, character \{r.end.character}",
            ),
          )
      }
      if si > ei {
        return Err(
          @lsp_binding.RpcError::new(
            @lsp_binding.invalid_params_code,
            "content change range.start (line \{r.start.line}, character \{r.start.character}) is after range.end (line \{r.end.line}, character \{r.end.character})",
          ),
        )
      }
      // 切片拼接 prefix ++ text ++ suffix（两次单点 `+`，非循环拼接）：O(N)。
      Ok(rebuild(cps, 0, si) + change.text + rebuild(cps, ei, cps.length()))
    }
  }
}
