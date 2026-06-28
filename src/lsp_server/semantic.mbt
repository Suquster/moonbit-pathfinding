// semantic.mbt —— 签名帮助 / 语义着色 / 折叠区间（任务 12.1）。
//
// 设计依据（design.md §3.5「扩展语言能力」，Requirement 5.7）：
// 本文件为**旁路新增**，不改 `analyze` / `dsl.mbt` / `types.mbt` 既有行为，全部
// 能力复用既有 `Analysis` 投影与同包私有 helper（`symbol_at` / `reference_at` /
// `lookup_symbol` / `split_lines` / `line_chars` / `is_ws`）：
//
//   * signatureHelp（5.7）  —— 当 pos 落在某符号定义或引用上时，返回该键的签名
//                              信息（形如 `key = value`），否则 None；
//   * semanticTokens（5.7） —— 对每个符号定义与每个引用生成一个 token，按出现
//                              顺序（行、列）排序后做 LSP 5-tuple 增量编码；
//   * foldingRange（5.7）   —— 把文档中连续的「内容行」（非空、非注释）块作为一
//                              个折叠范围（至少跨 2 行才折叠）。
//
// paper-to-code 追溯：LSP §「Language Features」之 `textDocument/signatureHelp`、
// `textDocument/semanticTokens`（5-tuple 增量编码 `[deltaLine, deltaStartChar,
// length, tokenType, tokenModifiers]`）与 `textDocument/foldingRange`。
//
// 确定性约定（design.md §「三后端一致性」）：全部输出顺序由**源文本出现顺序**
// 决定——semanticTokens 以 (line, startChar) 升序稳定排序后增量编码，
// foldingRange 以行号升序产出，均不依赖任何哈希遍历顺序，保证 wasm-gc / js /
// native 三后端逐位一致。

// ───────────────────────────── signatureHelp（5.7） ───────────────────

///|
/// 签名信息：单一展示标签 `label`（如 `key = value`）。
///
/// 仅含 `String`，故可安全 `derive(Eq, Show)`。
pub(all) struct SignatureInfo {
  label : String
} derive(Eq, Show)

///|
/// 在位置 `pos` 处给出签名帮助（Requirement 5.7）。
///
/// 判定规则（复用 `dsl.mbt` 同包私有 helper）：
///   * 若 `pos` 落在某符号定义上 → 返回 `Some({ label: "name = value" })`；
///   * 否则若 `pos` 落在某引用上 → 查其定义：
///       - 定义存在 → `Some({ label: "name = value" })`；
///       - 定义不存在（引用未定义键）→ `Some({ label: "name" })`；
///   * 否则（`pos` 不在任何符号 / 引用上）→ `None`。
pub fn signature_help(a : Analysis, pos : Position) -> SignatureInfo? {
  match symbol_at(a, pos) {
    Some(s) => Some({ label: s.name + " = " + s.value })
    None =>
      match reference_at(a, pos) {
        Some(r) =>
          match lookup_symbol(a, r.name) {
            Some(s) => Some({ label: s.name + " = " + s.value })
            None => Some({ label: r.name })
          }
        None => None
      }
  }
}

// ───────────────────────────── semanticTokens（5.7） ──────────────────

///|
/// token 类型常量：符号定义 = 0，引用 = 1（固定小整数）。
let token_type_symbol : Int = 0

///|
let token_type_reference : Int = 1

///|
/// 一个待编码的语义 token（同行 token）：行号 `line`、起始列 `start`、字符长度
/// `length`、类型 `ttype`。
priv struct SemTok {
  line : Int
  start : Int
  length : Int
  ttype : Int
}

///|
/// 收集 `Analysis` 中全部语义 token：每个符号定义与每个引用各生成一个。
///
/// `length = range.end.character - range.start.character`（同行 token）。
fn collect_tokens(a : Analysis) -> Array[SemTok] {
  let toks : Array[SemTok] = []
  for s in a.symbols {
    toks.push({
      line: s.range.start.line,
      start: s.range.start.character,
      length: s.range.end.character - s.range.start.character,
      ttype: token_type_symbol,
    })
  }
  for r in a.references {
    toks.push({
      line: r.range.start.line,
      start: r.range.start.character,
      length: r.range.end.character - r.range.start.character,
      ttype: token_type_reference,
    })
  }
  toks
}

///|
/// 按 (line, startChar) 升序稳定排序（插入排序，三后端行为确定）。
///
/// 稳定性：相等键（同 line 同 start）保持原插入顺序，从而当符号定义与引用恰好
/// 起始列相同时，编码顺序由收集顺序（先符号、后引用）确定。
fn sort_tokens(toks : Array[SemTok]) -> Array[SemTok] {
  let arr = toks
  let n = arr.length()
  let mut i = 1
  while i < n {
    let cur = arr[i]
    let mut j = i - 1
    // 仅当前驱严格大于 cur 时右移，保证稳定。
    while j >= 0 &&
          (
            arr[j].line > cur.line ||
            (arr[j].line == cur.line && arr[j].start > cur.start)
          ) {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = cur
    i = i + 1
  }
  arr
}

///|
/// 生成 LSP semanticTokens 的 5-tuple 增量编码（Requirement 5.7）。
///
/// 对每个符号定义与每个引用各生成一个 token，按 (line, startChar) 升序排序后做
/// 增量编码——每个 token 推入 5 个 `Int`：
///   `[deltaLine, deltaStartChar, length, tokenType, tokenModifiers]`
/// 其中：
///   * 第一个 token：`deltaLine = line`、`deltaStartChar = startChar`；
///   * 后续 token：`deltaLine = line - prevLine`；若 `deltaLine == 0` 则
///     `deltaStartChar = startChar - prevStartChar`，否则 `deltaStartChar = startChar`；
///   * `tokenModifiers` 恒为 0。
pub fn semantic_tokens(a : Analysis) -> Array[Int] {
  let toks = sort_tokens(collect_tokens(a))
  let out : Array[Int] = []
  let mut prev_line = 0
  let mut prev_start = 0
  let mut first = true
  for t in toks {
    let delta_line = if first { t.line } else { t.line - prev_line }
    let delta_start = if first {
      t.start
    } else if delta_line == 0 {
      t.start - prev_start
    } else {
      t.start
    }
    out.push(delta_line)
    out.push(delta_start)
    out.push(t.length)
    out.push(t.ttype)
    out.push(0)
    prev_line = t.line
    prev_start = t.start
    first = false
  }
  out
}

// ───────────────────────────── foldingRange（5.7） ────────────────────

///|
/// 判定一行是否为「内容行」：去前导空白后非空，且首个非空白字符不是 `#`。
///
/// 空行与注释行均非内容行（与 `dsl.mbt` 的忽略规则一致）。
fn is_content_line(line : String) -> Bool {
  let cs = line_chars(line)
  let n = cs.length()
  let mut start = 0
  while start < n && is_ws(cs[start]) {
    start = start + 1
  }
  if start >= n {
    return false
  }
  cs[start] != '#'
}

///|
/// 计算折叠区间（Requirement 5.7）。
///
/// 将文档中**连续的内容行**（非空、非注释）聚成块；凡跨 ≥2 行的块产出一个折叠
/// 范围 `Range { start: {block_start, 0}, end: {block_end, 该行字符数} }`。
/// 空文档 / 单行 / 全部为单行块时返回空数组。遍历按行号升序，结果确定。
pub fn folding_ranges(doc : TextDocument) -> Array[Range] {
  let lines = split_lines(doc.text)
  let n = lines.length()
  let result : Array[Range] = []
  let mut i = 0
  while i < n {
    if is_content_line(lines[i]) {
      // 扩展当前内容行块 [block_start, block_end]。
      let block_start = i
      let mut block_end = i
      while block_end + 1 < n && is_content_line(lines[block_end + 1]) {
        block_end = block_end + 1
      }
      // 仅当块跨 ≥2 行才折叠。
      if block_end > block_start {
        let last_len = line_chars(lines[block_end]).length()
        result.push({
          start: { line: block_start, character: 0 },
          end: { line: block_end, character: last_len },
        })
      }
      i = block_end + 1
    } else {
      i = i + 1
    }
  }
  result
}
