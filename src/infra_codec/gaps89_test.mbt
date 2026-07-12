// gaps89_test.mbt —— MsgView 惰性视图余臂（第八十九批）。

///|
/// zigzag_field：字段缺失回传 None。
test "MsgView::zigzag_field：字段缺失" {
  let v = MsgView::over([0x08, 0x02]) // 字段 1 varint=2
  assert_true(v.zigzag_field(2) is None)
  assert_eq(v.zigzag_field(1), Some(1L)) // zigzag(2)=1
}

///|
/// locate 跳过未命中 varint 字段时载荷截断 → None。
test "MsgView::locate：跳过 varint 字段截断" {
  // 字段 1 (wire 0) 的值 varint 0x80 截断（继续位无后续字节），再找字段 2。
  let v = MsgView::over([0x08, 0x80])
  assert_true(v.varint_field(2) is None)
}

///|
/// string_field：码点超出合法标量值（如孤立代理项）→ None。
test "MsgView::string_field：非法码点拒绝" {
  // 字段 1 (wire 2) len=3，码点 varint = 0xD800（孤立代理项）。
  let v = MsgView::over([0x0A, 0x03, 0x80, 0xB0, 0x03])
  assert_true(v.string_field(1) is None)
}
