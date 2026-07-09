// position_encoding_gaps_test.mbt —— 位置换算负值/越界防御收口
// （INFRA 第二十六批）。

///|
test "position_to_offset / offset_to_position：负值与越界拒绝" {
  let text = "ab\ncd"
  assert_true(
    position_to_offset(text, { line: -1, character: 0 }, Utf16) is None,
  )
  assert_true(
    position_to_offset(text, { line: 9, character: 0 }, Utf16) is None,
  )
  assert_true(
    position_to_offset(text, { line: 0, character: -1 }, Utf16) is None,
  )
  assert_true(offset_to_position(text, -1, Utf16) is None)
}

///|
test "convert_position：负字符位拒绝" {
  let text = "ab"
  assert_true(
    convert_position(text, { line: 0, character: -2 }, from=Utf16, to=Utf8)
    is None,
  )
}
