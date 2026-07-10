// cbor_simple_test.mbt —— simple 值全量收口（INFRA 第四十八批）：
// 0..19 内联、0xF8 扩展 32..255、扩展形式 0..31 畸形拒绝。

///|
test "cbor simple：内联 0..19 编解码 roundtrip" {
  assert_true(
    @infra_codec.cbor_decode([0xF0]) == Some(@infra_codec.CborSimple(16)),
  )
  let enc = @infra_codec.cbor_encode(@infra_codec.CborSimple(0))
  assert_eq(enc, [0xE0])
  assert_true(@infra_codec.cbor_decode(enc) == Some(@infra_codec.CborSimple(0)))
}

///|
test "cbor simple：0xF8 扩展 32..255 与畸形拒绝" {
  // 0xf8ff → simple(255)。
  assert_true(
    @infra_codec.cbor_decode([0xF8, 0xFF]) == Some(@infra_codec.CborSimple(255)),
  )
  let enc = @infra_codec.cbor_encode(@infra_codec.CborSimple(32))
  assert_eq(enc, [0xF8, 0x20])
  assert_true(
    @infra_codec.cbor_decode(enc) == Some(@infra_codec.CborSimple(32)),
  )
  // 扩展形式载荷 0..31 畸形（RFC 8949 §3.3）。
  assert_true(@infra_codec.cbor_decode([0xF8, 0x00]) == None)
  assert_true(@infra_codec.cbor_decode([0xF8, 0x18]) == None)
  // 截断的扩展 simple。
  assert_true(@infra_codec.cbor_decode([0xF8]) == None)
}
