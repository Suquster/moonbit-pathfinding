// position_encoding_test.mbt —— 位置编码单元测试（任务 6.2）。
//
// 针对 position_encoding.mbt 的协商与码元换算，覆盖 Requirement 4.1 / 4.4 的
// **具体见证**：
//   * 协商回退（R4.1）：客户端无声明（空列表）回退 UTF-16；有声明取首选。
//   * 代理对列号（R4.4）：emoji（U+1F600）与 CJK 扩展 B 区（U+20000）等
//     BMP 外码位，在三种编码下分别占
//       - UTF-16：2 个码元（代理对）
//       - UTF-8 ：4 个字节
//       - UTF-32：1 个码元
//     并以含 emoji 行的 Position↔offset 列号见证收尾。
//
// 断言策略：
//   * `PositionEncoding` 派生 Show，协商结果与 `code_units` 返回的 Int 直接
//     用 `assert_eq`。
//   * `Position` 仅派生 Eq（无 Show），故对 Position 一律用
//     `assert_true(actual == expected)` 或 pattern match 提取 line/character
//     后对 Int 用 `assert_eq`，避免对无 Show 类型使用 assert_eq。

// ───────────────────────────── R4.1 协商回退 ──────────────────────────

///|
/// 客户端无声明（空列表）时回退到 UTF-16（LSP 默认）。
test "negotiate_encoding: empty client list falls back to Utf16" {
  assert_eq(negotiate_encoding([]), Utf16)
}

///|
/// 客户端有声明时取其声明列表中的首选（服务端支持全部三种编码）。
test "negotiate_encoding: picks client's first declared encoding" {
  assert_eq(negotiate_encoding([Utf8, Utf16, Utf32]), Utf8)
  assert_eq(negotiate_encoding([Utf32, Utf8]), Utf32)
  assert_eq(negotiate_encoding([Utf16]), Utf16)
}

// ───────────────────── R4.4 代理对码元数（emoji / CJK 扩展区）─────────

///|
/// emoji U+1F600（😀，BMP 外，UTF-16 需代理对）在三编码下的码元数见证：
/// UTF-16 = 2、UTF-8 = 4、UTF-32 = 1。
test "code_units: emoji U+1F600 occupies 2 / 4 / 1 across utf16/utf8/utf32" {
  assert_eq(code_units(0x1F600, Utf16), 2)
  assert_eq(code_units(0x1F600, Utf8), 4)
  assert_eq(code_units(0x1F600, Utf32), 1)
}

///|
/// CJK 扩展 B 区 U+20000（𠀀，BMP 外）在三编码下的码元数见证：
/// UTF-16 = 2、UTF-8 = 4、UTF-32 = 1。
test "code_units: CJK ext-B U+20000 occupies 2 / 4 / 1 across utf16/utf8/utf32" {
  assert_eq(code_units(0x20000, Utf16), 2)
  assert_eq(code_units(0x20000, Utf8), 4)
  assert_eq(code_units(0x20000, Utf32), 1)
}

///|
/// 对照见证：BMP 内字符的码元数。
///   * ASCII 'a'(U+0061)：UTF-16=1 / UTF-8=1 / UTF-32=1。
///   * CJK '中'(U+4E2D，BMP 内但 UTF-8 占 3 字节)：UTF-16=1 / UTF-8=3 / UTF-32=1。
///   * 拉丁补充 'é'(U+00E9，UTF-8 占 2 字节)：UTF-16=1 / UTF-8=2 / UTF-32=1。
test "code_units: BMP characters across encodings" {
  // ASCII 'a'
  assert_eq(code_units(0x61, Utf16), 1)
  assert_eq(code_units(0x61, Utf8), 1)
  assert_eq(code_units(0x61, Utf32), 1)
  // CJK '中'（BMP 内，UTF-8 三字节）
  assert_eq(code_units(0x4E2D, Utf16), 1)
  assert_eq(code_units(0x4E2D, Utf8), 3)
  assert_eq(code_units(0x4E2D, Utf32), 1)
  // 'é'（UTF-8 两字节）
  assert_eq(code_units(0x00E9, Utf16), 2 - 1) // 1 码元
  assert_eq(code_units(0x00E9, Utf8), 2)
  assert_eq(code_units(0x00E9, Utf32), 1)
}

// ───────────── 含 emoji 行的 Position↔offset 列号见证（R4.4）──────────

///|
/// 文本 "a😀b"（单行，依次：'a' / 😀 U+1F600 / 'b'）中，'b' 的列号随编码而变：
///   * UTF-16：1（a）+ 2（emoji）= 3
///   * UTF-8 ：1（a）+ 4（emoji）= 5
///   * UTF-32：1（a）+ 1（emoji）= 2
/// 以 position_to_offset / offset_to_position 往返验证。
/// （Position 无 Show，故用 assert_true(... == ...) 比较。）
test "position_to_offset: column of 'b' after emoji differs per encoding" {
  let text = "a\u{1F600}b"

  // UTF-16：'b' 在 character = 3。
  let pos16 : Position = { line: 0, character: 3 }
  assert_eq(position_to_offset(text, pos16, Utf16), Some(3))
  assert_true(offset_to_position(text, 3, Utf16) == Some(pos16))

  // UTF-8：'b' 在 character = 5。
  let pos8 : Position = { line: 0, character: 5 }
  assert_eq(position_to_offset(text, pos8, Utf8), Some(5))
  assert_true(offset_to_position(text, 5, Utf8) == Some(pos8))

  // UTF-32：'b' 在 character = 2。
  let pos32 : Position = { line: 0, character: 2 }
  assert_eq(position_to_offset(text, pos32, Utf32), Some(2))
  assert_true(offset_to_position(text, 2, Utf32) == Some(pos32))
}

///|
/// 同一字符边界（"a😀b" 中的 'b'）在不同编码间换算：
/// UTF-16 列号 3 ↔ UTF-8 列号 5 ↔ UTF-32 列号 2，互为逆。
test "convert_position: 'b' after emoji converts across encodings" {
  let text = "a\u{1F600}b"
  let pos16 : Position = { line: 0, character: 3 }
  let pos8 : Position = { line: 0, character: 5 }
  let pos32 : Position = { line: 0, character: 2 }

  // UTF-16 → UTF-8 / UTF-32
  assert_true(convert_position(text, pos16, from=Utf16, to=Utf8) == Some(pos8))
  assert_true(
    convert_position(text, pos16, from=Utf16, to=Utf32) == Some(pos32),
  )
  // 逆向：UTF-8 / UTF-32 → UTF-16
  assert_true(convert_position(text, pos8, from=Utf8, to=Utf16) == Some(pos16))
  assert_true(
    convert_position(text, pos32, from=Utf32, to=Utf16) == Some(pos16),
  )
}

///|
/// 落在 emoji 代理对「中间」的列号非法：UTF-16 下 character = 2 落在 😀 的
/// 两个码元之间，应返回 None（既不可换算为 offset，也不是合法 Position）。
test "position_to_offset: column inside a surrogate pair is rejected" {
  let text = "a\u{1F600}b"
  // UTF-16 下 character=2 落在 emoji 两码元中间。
  assert_eq(position_to_offset(text, { line: 0, character: 2 }, Utf16), None)
}
