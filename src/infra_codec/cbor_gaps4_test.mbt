// cbor_gaps4_test.mbt —— CBOR 余支防御测试（INFRA 第五十七批）：
// CborSimple Show 渲染与 float32 正负无穷。

///|
test "cbor 余支：Show 渲染 Simple" {
  assert_eq("\{@infra_codec.CborSimple(16)}", "CborSimple(16)")
}

///|
test "cbor 余支：float32 正负无穷" {
  match @infra_codec.cbor_decode([0xFA, 0x7F, 0x80, 0x00, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d > 1.0e308)
    _ => fail("float32 +inf 解码失败")
  }
  match @infra_codec.cbor_decode([0xFA, 0xFF, 0x80, 0x00, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d < -1.0e308)
    _ => fail("float32 -inf 解码失败")
  }
}
