// semantic_test.mbt —— 语义能力单元测试（任务 12.2）。
//
// 针对 semantic.mbt 的 `signature_help` / `semantic_tokens` / `folding_ranges`，
// 覆盖 Requirement 5.7 的**具体见证**：
//   * signatureHelp：pos 落在定义上 → Some({label:"name = value"})；落在引用上时
//     按其定义是否存在分别给出 "name = value" / "name"；不在任何符号/引用上 → None。
//   * semanticTokens：LSP 5-tuple 增量编码 [deltaLine, deltaStartChar, length,
//     tokenType(symbol=0/reference=1), tokenModifiers(=0)]，按 (line,startChar) 排序。
//   * foldingRange：连续内容行块跨 ≥2 行 → 一个 Range；单行/空文档 → 空。
//
// 断言策略：
//   * `SignatureInfo` 派生 Eq+Show，`Array[Int]` 有 Show → 直接 `assert_eq`。
//   * `Range` 仅派生 Eq（无 Show）→ 以 Int 字段（line/character，有 Show）逐项见证。
//   * 源码禁止裸美元-花括号引用前缀（部分后端报错）：需要引用文本时以
//     `Int::unsafe_to_char(36)`（'$'）拼接构造，避免在字面量中直接书写。

// ───────────────────────── signatureHelp（5.7） ───────────────────────

///|
/// pos 落在符号定义上 → 返回 Some({label:"k = 1"})。
/// 文档 "k = 1\n"：symbol k 的定义范围为第 0 行 [0,1)，pos=(0,0) 落在其上。
test "signature_help on a definition yields 'name = value'" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "k = 1\n" }
  let a = analyze(doc)
  let sig = signature_help(a, { line: 0, character: 0 })
  assert_eq(sig, Some({ label: "k = 1" }))
}

///|
/// pos 不在任何符号/引用上 → None。
/// 文档 "k = 1\n"：第 0 行 char 4 落在值 "1" 上（非键 token、非引用）。
test "signature_help off any symbol yields None" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "k = 1\n" }
  let a = analyze(doc)
  let sig = signature_help(a, { line: 0, character: 4 })
  assert_eq(sig, None)
}

///|
/// pos 落在引用上、且其定义存在 → 返回定义的 "name = value"。
/// 文档 "k = 1\nv = ${k}\n"：第 1 行引用 ${k} 范围为 [4,8)，pos=(1,5) 落在其内，
/// 键 k 已定义为 1，故签名为 "k = 1"。
test "signature_help on a reference to a defined key yields its definition" {
  let dollar = Int::unsafe_to_char(36).to_string()
  let text = "k = 1\nv = " + dollar + "{k}\n"
  let doc : TextDocument = { uri: "file:///a.conf", text }
  let a = analyze(doc)
  let sig = signature_help(a, { line: 1, character: 5 })
  assert_eq(sig, Some({ label: "k = 1" }))
}

///|
/// pos 落在引用上、但其定义不存在 → 仅返回引用名 "name"。
/// 文档 "v = ${x}\n"：第 0 行引用 ${x} 范围为 [4,8)，键 x 未定义，签名为 "x"。
test "signature_help on a reference to an undefined key yields just the name" {
  let dollar = Int::unsafe_to_char(36).to_string()
  let text = "v = " + dollar + "{x}\n"
  let doc : TextDocument = { uri: "file:///a.conf", text }
  let a = analyze(doc)
  let sig = signature_help(a, { line: 0, character: 5 })
  assert_eq(sig, Some({ label: "x" }))
}

// ───────────────────────── semanticTokens（5.7） ──────────────────────

///|
/// 两个单 symbol 行验证 deltaLine 编码。
/// 文档 "a = 1\nb = 2\n"：
///   * a：line0 char0 len1 type0(symbol) → 首 token [0,0,1,0,0]；
///   * b：line1 char0 len1 type0(symbol) → deltaLine=1、deltaStart=0 → [1,0,1,0,0]。
/// 合并为 [0,0,1,0,0, 1,0,1,0,0]。
test "semantic_tokens encodes two symbol rows with delta line" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "a = 1\nb = 2\n" }
  let a = analyze(doc)
  let tokens = semantic_tokens(a)
  assert_eq(tokens, [0, 0, 1, 0, 0, 1, 0, 1, 0, 0])
}

///|
/// 含引用的文档验证 reference token(type=1) 与同行 deltaStartChar 编码。
/// 文档 "k = 1\nv = ${k}\n"：
///   * k：line0 char0 len1 type0 → 首 token [0,0,1,0,0]；
///   * v：line1 char0 len1 type0 → deltaLine=1、deltaStart=0 → [1,0,1,0,0]；
///   * ${k} 引用：line1 char4 len4 type1 → 同行 deltaLine=0、deltaStart=4 → [0,4,4,1,0]。
/// 合并为 [0,0,1,0,0, 1,0,1,0,0, 0,4,4,1,0]。
test "semantic_tokens encodes a reference token with type 1 and same-line delta" {
  let dollar = Int::unsafe_to_char(36).to_string()
  let text = "k = 1\nv = " + dollar + "{k}\n"
  let doc : TextDocument = { uri: "file:///a.conf", text }
  let a = analyze(doc)
  let tokens = semantic_tokens(a)
  assert_eq(tokens, [0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 4, 4, 1, 0])
}

///|
/// 空文档（无符号、无引用）→ 空 token 数组。
test "semantic_tokens on empty document yields empty array" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "" }
  let a = analyze(doc)
  assert_eq(semantic_tokens(a), [])
}

// ───────────────────────── foldingRange（5.7） ────────────────────────

///|
/// 三连续内容行 → 一个折叠区间。
/// 文档 "a = 1\nb = 2\nc = 3\n"：内容行 0..2 聚为一块，跨 3 行（≥2）→ 一个 Range
/// {start:{0,0}, end:{2,5}}（末行 "c = 3" 含 5 个字符）。
test "folding_ranges folds a block of contiguous content lines" {
  let doc : TextDocument = {
    uri: "file:///a.conf",
    text: "a = 1\nb = 2\nc = 3\n",
  }
  let ranges = folding_ranges(doc)
  assert_eq(ranges.length(), 1)
  // Range 无 Show：以 Int 字段逐项见证 [ (0,0), (2,5) )。
  let r = ranges[0]
  assert_eq(r.start.line, 0)
  assert_eq(r.start.character, 0)
  assert_eq(r.end.line, 2)
  assert_eq(r.end.character, 5)
}

///|
/// 单行文档不折叠（块未跨 ≥2 行）→ 空数组。
test "folding_ranges yields nothing for a single content line" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "a = 1\n" }
  let ranges = folding_ranges(doc)
  assert_eq(ranges.length(), 0)
}

///|
/// 空行/注释行打断块：两个单行内容块均不跨 ≥2 行 → 空数组。
/// 文档 "a = 1\n\nb = 2\n"：第 1 行为空行，将内容行 0 与 2 分隔为两个单行块。
test "folding_ranges does not fold blocks broken by a blank line" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "a = 1\n\nb = 2\n" }
  let ranges = folding_ranges(doc)
  assert_eq(ranges.length(), 0)
}
