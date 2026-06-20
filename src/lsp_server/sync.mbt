// sync.mbt —— 增量文档同步：同步类别、内容变更与变更应用
// （旗舰深化，任务 7.1 旁路新增）。
//
// paper-to-code 追溯（design.md §3.3 / Requirement 3）：
//   * LSP 规范 `textDocument/didChange` 与 `TextDocumentSyncKind`：
//       - `Full`（每次发送全文）：`contentChanges` 单条 `text` 即变更后全文，
//         `range` 省略（本模块以 `range = None` 表达）；以该全文整体替换文档。
//       - `Incremental`（每次发送变更区间）：每条 `contentChanges` 含变更范围
//         `range`（闭开区间 [start, end)）与替换文本 `text`，按出现顺序逐条
//         作用于「上一条变更后的文本」。
//     <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange>
//
// 关键实现策略（与 position_encoding.mbt 一致、三后端逐位一致）：
//   `range` 的 `start`/`end` 列号单位由 `PositionEncoding` 决定（任务 6），但
//   **替换文本必须按 Unicode 码位（codepoint）切割字符串**，不能直接用编码码元
//   offset 去切（否则会切在多码元字符中间、且不同编码语义不一致）。因此本模块：
//     1. 把当前文本解析为「码位序列」`Array[Int]`（MoonBit `for c in text` 按
//        Unicode 码位迭代，BMP 外字符给出单个 `Char`，`c.to_int()` 得真实码位）。
//     2. 用 `PositionEncoding` 把 `range.start` / `range.end` 各解析为「全局码位
//        线性索引」si / ei（遍历码位、按 enc 累计列号匹配 Position；'\n' 计 1 码元
//        并换行）。仅当 Position 恰好落在某码位边界（含行首 / 行尾 / 文末）时成功。
//     3. 切割重建：new = codepoints[0:si] ++ change.text ++ codepoints[ei:]。
//   多条变更按顺序应用，每条作用于上一条结果（重新解析码位）。
//
// 越界 / 非码位边界 / start > end 一律返回携带定位信息的
// `Err(@lsp_binding.invalid_params_code, ..)`，且**不返回部分应用结果**：在累积
// 过程中一遇错误即返回 `Err`，调用方观察不到任何中间文本（Requirement 3.5）。

///|
/// 文档同步类别（LSP `TextDocumentSyncKind`）。
pub(all) enum TextDocumentSyncKind {
  Full // 每次发送全文
  Incremental // 每次发送变更区间
} derive(Eq, Show)

///|
/// 一条内容变更（LSP `TextDocumentContentChangeEvent`）：
///   * `Incremental` 时 `range = Some(..)`，`text` 为该范围的替换文本；
///   * `Full` 时 `range = None`，`text` 即变更后全文。
///
/// 注：`Range`（同包 `types.mbt`）仅 `derive(Eq)`（无 `Show`），故 `ContentChange`
/// 亦只能 `derive(Eq)`。
pub(all) struct ContentChange {
  range : Range?
  text : String
} derive(Eq)

///|
/// 带版本号的文档（旁路扩展，**不改既有 `TextDocument` 字段**）：
/// 资源标识 `uri` + 全文 `text` + 单调版本号 `version`。
///
/// 含 `String`/`Int` 字段，无 `Range`，故 `derive(Eq)`（与设计一致，无 `Show`）。
pub(all) struct VersionedDocument {
  uri : String
  text : String
  version : Int
} derive(Eq)

// ───────────────────────────── 内部码位工具 ─────────────────────────────

///|
/// 将文本解析为 Unicode 码位序列。
fn to_codepoints(text : String) -> Array[Int] {
  let cps : Array[Int] = []
  for c in text {
    cps.push(c.to_int())
  }
  cps
}

///|
/// 由码位序列的子区间 `[from, to)` 重建字符串。
fn rebuild(cps : Array[Int], from : Int, to : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = from
  while i < to {
    sb.write_char(cps[i].unsafe_to_char())
    i = i + 1
  }
  sb.to_string()
}

///|
/// 把 `Position`（列号单位为 `enc` 码元）解析为「全局码位线性索引」。
///
/// 遍历码位序列，维护当前 (line, col) —— `col` 以 `enc` 码元计量；当抵达目标
/// `(pos.line, pos.character)` 时返回当前码位索引。仅当 Position 恰好落在某码位
/// 边界（含行首、行尾、文末）时成功；越界 / 落在多码元字符中间返回 `None`。
fn position_to_cp_index(
  cps : Array[Int],
  pos : Position,
  enc : PositionEncoding,
) -> Int? {
  if pos.line < 0 || pos.character < 0 {
    return None
  }
  let n = cps.length()
  let mut line = 0
  let mut col = 0
  let mut idx = 0
  while idx < n {
    if line == pos.line && col == pos.character {
      return Some(idx)
    }
    // 已越过目标位置（同一行列号超出，或行号已超出）→ 非码位边界 / 越界。
    if line == pos.line && col > pos.character {
      return None
    }
    if line > pos.line {
      return None
    }
    let cp = cps[idx]
    if cp == 0x0A {
      line = line + 1
      col = 0
    } else {
      col = col + code_units(cp, enc)
    }
    idx = idx + 1
  }
  // 文末位置（在消费完全部码位之后）。
  if line == pos.line && col == pos.character {
    return Some(n)
  }
  None
}

// ───────────────────────────── 变更应用 ─────────────────────────────────

///|
/// 按序应用内容变更得到新文本（Requirement 3.1 / 3.2 / 3.4）。
///
///   * `range = None`（Full）：以该条 `text` 整体替换当前文本。
///   * `range = Some(r)`（Incremental）：把 `r` 解析为码位区间 `[si, ei)`，
///     用 `text` 替换该区间；多条变更按出现顺序依次作用于上一条结果。
///
/// 任一变更的范围越界、落在多码元字符中间或 `start > end` 时，立即返回携带定位
/// 信息的 `Err(@lsp_binding.invalid_params_code, ..)`，**不返回部分应用结果**
/// （Requirement 3.5）。
pub fn apply_changes(
  text : String,
  changes : Array[ContentChange],
  encoding : PositionEncoding,
) -> Result[String, @lsp_binding.RpcError] {
  let mut cur = text
  for change in changes {
    match change.range {
      // Full：全文替换。
      None => cur = change.text
      // Incremental：按范围替换。
      Some(r) => {
        let cps = to_codepoints(cur)
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
        cur = rebuild(cps, 0, si) + change.text + rebuild(cps, ei, cps.length())
      }
    }
  }
  Ok(cur)
}

///|
/// 把一次 `didChange` 应用到带版本号文档：成功则文本更新且 `version` 更新为通知
/// 携带的版本 `new_version`（Requirement 3.3）；变更失败（越界等）按 `apply_changes`
/// 语义返回 `Err` 且文档不变（不返回部分应用结果）。
pub fn VersionedDocument::apply(
  self : VersionedDocument,
  changes : Array[ContentChange],
  new_version : Int,
  encoding : PositionEncoding,
) -> Result[VersionedDocument, @lsp_binding.RpcError] {
  match apply_changes(self.text, changes, encoding) {
    Ok(new_text) => Ok({ uri: self.uri, text: new_text, version: new_version })
    Err(e) => Err(e)
  }
}
