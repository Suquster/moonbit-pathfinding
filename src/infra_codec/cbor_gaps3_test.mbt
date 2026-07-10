// cbor_gaps3_test.mbt —— CBOR 余支防御测试（INFRA 第五十四批）：
// Show 渲染余支、float16 无穷、截断与保留 info 拒绝。

///|
test "cbor 余支：Show 渲染 Undefined/Tag" {
  assert_eq("\{@infra_codec.CborUndefined}", "CborUndefined")
  assert_eq(
    "\{@infra_codec.CborTag(1UL, @infra_codec.CborUInt(2UL))}",
    "CborTag(1, CborUInt(2))",
  )
}

///|
test "cbor 余支：float16 正负无穷" {
  match @infra_codec.cbor_decode([0xF9, 0x7C, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d > 1.0e308)
    _ => fail("float16 +inf 解码失败")
  }
  match @infra_codec.cbor_decode([0xF9, 0xFC, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d < -1.0e308)
    _ => fail("float16 -inf 解码失败")
  }
}

///|
test "cbor 余支：截断与保留 additional info 拒绝" {
  // 不定长字节串：块载荷越界 / 块头缺失。
  assert_true(@infra_codec.cbor_decode([0x5F, 0x42, 0x01]) is None)
  assert_true(@infra_codec.cbor_decode([0x5F]) is None)
  // 定长数组元素缺失。
  assert_true(@infra_codec.cbor_decode([0x82, 0x01]) is None)
  // 不定长映射：键解码失败。
  assert_true(@infra_codec.cbor_decode([0xBF, 0x1C]) is None)
  // 定长映射：值缺失。
  assert_true(@infra_codec.cbor_decode([0xA1, 0x01]) is None)
  // tag：头部长度字段截断。
  assert_true(@infra_codec.cbor_decode([0xD8]) is None)
  // float64 载荷截断。
  assert_true(@infra_codec.cbor_decode([0xFB, 0x00, 0x00]) is None)
  // major 7 保留 info（28..30）。
  assert_true(@infra_codec.cbor_decode([0xFC]) is None)
}
