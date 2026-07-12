// gaps81_test.mbt —— Rope 大树右子树偏移换算与叶界代理对切分收口（第八十一批）。

///|
/// 叶切分边界恰落在代理对中缝：切点回退一位，代理对保持完整。
test "rope：叶界代理对不被切半" {
  let sb = StringBuilder::new()
  for _i in 0..<511 {
    sb.write_char('a')
  }
  sb.write_char('😀') // 代理对占位 511-512，恰跨 512 叶界。
  for _i in 0..<8 {
    sb.write_char('b')
  }
  let s = sb.to_string()
  let r = Rope::from_string(s)
  assert_eq(r.len(), s.length())
  assert_eq(r.to_string(), s)
  // 代理对完整：charcode 在 511/512 处分别是高/低代理项。
  assert_true(r.charcode_at(511) == Some(0xD83D))
  assert_true(r.charcode_at(512) == Some(0xDE00))
}

///|
/// 多叶大绳的 UTF-16 → UTF-8 偏移换算：命中右子树需累计左子树字节量。
test "rope：utf16_to_utf8 右子树累计" {
  let sb = StringBuilder::new()
  for _i in 0..<600 {
    sb.write_char('中') // 每字符 UTF-16 1 码元 / UTF-8 3 字节。
  }
  let r = Rope::from_string(sb.to_string())
  assert_eq(r.utf16_to_utf8(0), 0)
  assert_eq(r.utf16_to_utf8(550), 550 * 3)
  assert_eq(r.utf16_to_utf8(600), 600 * 3)
}

///|
/// 多叶大绳的 UTF-8 → UTF-16 偏移换算：命中右子树需累计左子树码元量。
test "rope：utf8_to_utf16 右子树累计" {
  let sb = StringBuilder::new()
  for _i in 0..<600 {
    sb.write_char('中')
  }
  let r = Rope::from_string(sb.to_string())
  assert_eq(r.utf8_to_utf16(0), 0)
  assert_eq(r.utf8_to_utf16(550 * 3), 550)
  assert_eq(r.utf8_to_utf16(600 * 3), 600)
}
