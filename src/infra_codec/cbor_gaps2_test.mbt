// cbor_gaps2_test.mbt —— CBOR 解码截断/超限分支收口
// （INFRA 第二十四批）。

///|
fn cg2_none(bytes : Array[Int]) -> Unit raise {
  assert_true(cbor_decode(bytes) is None)
}

///|
test "cbor_decode：负整数头部截断拒绝" {
  cg2_none([0x38]) // major 1, info 24, 缺后续字节
}

///|
test "cbor_decode：字节串长度越界与头部截断拒绝" {
  cg2_none([0x42, 0x01]) // 声称 2 字节，仅 1 字节
  cg2_none([0x58]) // info 24 头部截断
  // 长度 2^63 > Int 上限。
  cg2_none([0x5B, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
}

///|
test "cbor_decode：文本串头部截断拒绝" {
  cg2_none([0x78])
}

///|
test "cbor_decode：数组/映射长度超 Int 上限拒绝" {
  cg2_none([0x9B, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
  cg2_none([0xBB, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
}

///|
test "cbor_decode：映射键/值缺失拒绝" {
  cg2_none([0xA1]) // 1 对，键缺失
  cg2_none([0xA1, 0x01]) // 键为 1，值缺失
}

///|
test "cbor_decode：数组/映射长度头截断拒绝（INFRA 第七十五批）" {
  cg2_none([0x98]) // major 4, info 24 长度字节缺失
  cg2_none([0xB8]) // major 5, info 24 长度字节缺失
}
