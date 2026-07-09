// rope_gaps_test.mbt —— Rope UTF-8/UTF-16 偏移换算与行列定位覆盖收口
// （INFRA 第十七批）：多字节/代理对/孤立代理项、行偏移、深树重建的
// 确定性见证。

///|
/// 含 1/2/3/4 字节序列的混合文本："a¢中𐍈\nb"。
fn rg_mixed() -> String {
  "a¢中𐍈\nb"
}

///|
test "rope utf16↔utf8 偏移换算全谱" {
  let r = Rope::from_string(rg_mixed())
  // UTF-16 长度 7（𐍈 占两码元）；UTF-8 长度 1+2+3+4+1+1=12。
  assert_true(r.len() == 7)
  assert_true(r.utf8_len() == 12)
  // 逐字符边界换算。
  assert_true(r.utf16_to_utf8(0) == 0)
  assert_true(r.utf16_to_utf8(1) == 1)
  assert_true(r.utf16_to_utf8(2) == 3)
  assert_true(r.utf16_to_utf8(3) == 6)
  assert_true(r.utf16_to_utf8(5) == 10)
  assert_true(r.utf16_to_utf8(7) == 12)
  // 夹取：负偏移 / 越界。
  assert_true(r.utf16_to_utf8(-3) == 0)
  assert_true(r.utf16_to_utf8(99) == 12)
  // 反向换算与夹取。
  assert_true(r.utf8_to_utf16(0) == 0)
  assert_true(r.utf8_to_utf16(3) == 2)
  assert_true(r.utf8_to_utf16(6) == 3)
  assert_true(r.utf8_to_utf16(10) == 5)
  assert_true(r.utf8_to_utf16(-1) == 0)
  assert_true(r.utf8_to_utf16(99) == 7)
  // 落在字符中间：向下取整到字符起点。
  assert_true(r.utf8_to_utf16(4) == 2)
  assert_true(r.utf8_to_utf16(8) == 3)
}

///|
test "rope 孤立代理项按 WTF-8 三字节计" {
  // 高代理项后跟非低代理项 → 3 字节。
  let lone = (0xD800).unsafe_to_char().to_string() + "a"
  let r = Rope::from_string(lone)
  assert_true(r.utf8_len() == 4)
  assert_true(r.utf16_to_utf8(1) == 3)
  assert_true(r.utf8_to_utf16(3) == 1)
  // 末尾孤立高代理项（i+1 越界分支）。
  let tail = "x" + (0xDBFF).unsafe_to_char().to_string()
  let r2 = Rope::from_string(tail)
  assert_true(r2.utf8_len() == 4)
}

///|
test "rope 行偏移与行列定位" {
  let r = Rope::from_string("ab\ncd\n\nef")
  assert_true(r.line_count() == 4)
  assert_true(r.offset_of_line(0) == 0)
  assert_true(r.offset_of_line(1) == 3)
  assert_true(r.offset_of_line(2) == 6)
  assert_true(r.offset_of_line(3) == 7)
  // 夹取：负行 / 越界行。
  assert_true(r.offset_of_line(-1) == 0)
  assert_true(r.offset_of_line(99) == 7)
  // 行列定位与夹取。
  assert_true(r.line_col_at(0) == (0, 0))
  assert_true(r.line_col_at(4) == (1, 1))
  assert_true(r.line_col_at(6) == (2, 0))
  assert_true(r.line_col_at(8) == (3, 1))
  assert_true(r.line_col_at(-2) == (0, 0))
  assert_true(r.line_col_at(99) == (3, 2))
}

///|
test "rope 深树重建与切片边界" {
  // 大量零散插入制造深树，触发 rebuild 后不变量保持。
  let r = Rope::new()
  for i in 0..<200 {
    r.insert(r.len(), "ab\n")
    r.insert(0, "x")
    ignore(i)
  }
  assert_true(r.len() == 800)
  assert_true(r.line_count() == 201)
  assert_true(r.is_leaf_balanced())
  // 切片夹取：空区间 / 负下界 / 越上界。
  assert_true(r.slice(5, 5) == "")
  assert_true(r.slice(-3, 1) == "x")
  assert_true(r.slice(799, 999) == "\n")
  // 删除全部后为空叶。
  r.delete(0, r.len())
  assert_true(r.len() == 0)
  assert_true(r.to_string() == "")
  assert_true(Rope::from_string("").leaf_count() == 1)
  // charcode_at 边界。
  let s = Rope::from_string("ab")
  assert_true(s.charcode_at(1) == Some(98))
  assert_true(s.charcode_at(2) is None)
  assert_true(s.charcode_at(-1) is None)
}
