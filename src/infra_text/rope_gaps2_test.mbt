// rope_gaps2_test.mbt —— Rope 叶切分/切片/WTF-8 前缀边界收口
// （INFRA 第二十四批）。

///|
test "Rope：叶边界代理对不被切半" {
  // 511 个 'a' + 一个代理对（占位 511/512）+ 10 个 'b'：
  // 叶上限 512 恰好落在代理对中间，切分点应回退 1。
  let sb = StringBuilder::new()
  for _i in 0..<511 {
    sb.write_char('a')
  }
  sb.write_string("😀")
  for _i in 0..<10 {
    sb.write_char('b')
  }
  let s = sb.to_string()
  let r = Rope::from_string(s)
  assert_eq(r.len(), s.length())
  assert_eq(r.to_string(), s)
  assert_true(r.leaf_count() >= 2)
  // 跨叶切片与整段一致。
  assert_eq(r.slice(500, 520).length(), 20)
  assert_eq(r.slice(0, s.length()), s)
  assert_eq(r.slice(511, 513), "😀")
}

///|
test "Rope：空串构造为空叶" {
  let r = Rope::from_string("")
  assert_eq(r.len(), 0)
  assert_eq(r.to_string(), "")
  assert_eq(r.leaf_count(), 1)
}

///|
test "Rope：孤立高代理后接普通字符的 UTF-8 前缀计数" {
  let sb = StringBuilder::new()
  sb.write_char((0xD800).unsafe_to_char())
  sb.write_char('a')
  let r = Rope::from_string(sb.to_string())
  // WTF-8：孤立高代理计 3 字节，'a' 计 1 字节。
  assert_eq(r.utf16_to_utf8(2), 4)
  assert_eq(r.utf16_to_utf8(1), 3)
}
