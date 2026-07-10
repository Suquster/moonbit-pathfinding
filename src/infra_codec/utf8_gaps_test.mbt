// utf8_gaps_test.mbt —— UTF-8 严格解码畸形续字节/截断分支收口
// （INFRA 第四十四批）。

///|
test "string_of_utf8_bytes：各长度畸形续字节拒绝" {
  // 2 字节序列续字节非法。
  assert_true(@infra_codec.string_of_utf8_bytes([0xC3, 0x28]) is None)
  // 3 字节序列截断与续字节非法。
  assert_true(@infra_codec.string_of_utf8_bytes([0xE2, 0x82]) is None)
  assert_true(@infra_codec.string_of_utf8_bytes([0xE2, 0x28, 0xA1]) is None)
  // 4 字节序列截断与续字节非法。
  assert_true(@infra_codec.string_of_utf8_bytes([0xF0, 0x90, 0x8D]) is None)
  assert_true(
    @infra_codec.string_of_utf8_bytes([0xF0, 0x28, 0x8C, 0xBC]) is None,
  )
}
