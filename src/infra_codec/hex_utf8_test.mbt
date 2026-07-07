// hex_utf8_test.mbt —— hex（RFC 4648 §8）与严格 UTF-8（RFC 3629）测试。

///|
test "hex encode decode roundtrip and known vectors" {
  assert_eq(@infra_codec.hex_encode([]), "")
  assert_eq(@infra_codec.hex_encode([0x00, 0xFF, 0x10, 0xAB]), "00ff10ab")
  assert_true(
    @infra_codec.hex_decode("00ff10ab") == Some([0x00, 0xFF, 0x10, 0xAB]),
  )
  // 大写同样接受。
  assert_true(
    @infra_codec.hex_decode("00FF10AB") == Some([0x00, 0xFF, 0x10, 0xAB]),
  )
  // 奇数长度 / 非法字符拒绝。
  assert_true(@infra_codec.hex_decode("abc") == None)
  assert_true(@infra_codec.hex_decode("zz") == None)
}

///|
test "hex pbt roundtrip 100 random buffers" {
  let rng = @infra_pbt.rng_new(77UL)
  for _ in 0..<100 {
    let bs : Array[Int] = []
    for _ in 0..<rng.next_below(32) {
      bs.push(rng.next_below(256))
    }
    assert_true(
      @infra_codec.hex_decode(@infra_codec.hex_encode(bs)) == Some(bs),
    )
  }
}

///|
test "utf8 known encodings" {
  assert_true(@infra_codec.utf8_bytes_of_string("A") == [0x41])
  assert_true(@infra_codec.utf8_bytes_of_string("ü") == [0xC3, 0xBC])
  assert_true(@infra_codec.utf8_bytes_of_string("水") == [0xE6, 0xB0, 0xB4])
  assert_true(
    @infra_codec.utf8_bytes_of_string("\u{1F600}") == [0xF0, 0x9F, 0x98, 0x80],
  )
}

///|
test "utf8 strict decode rejects malformed sequences" {
  // 孤立续字节。
  assert_true(@infra_codec.string_of_utf8_bytes([0x80]) == None)
  // 截断的两字节序列。
  assert_true(@infra_codec.string_of_utf8_bytes([0xC3]) == None)
  // overlong："/" 的两字节 overlong 编码 C0 AF（安全考虑经典用例）。
  assert_true(@infra_codec.string_of_utf8_bytes([0xC0, 0xAF]) == None)
  // 代理区 U+D800 → ED A0 80。
  assert_true(@infra_codec.string_of_utf8_bytes([0xED, 0xA0, 0x80]) == None)
  // 超出 U+10FFFF → F4 90 80 80。
  assert_true(
    @infra_codec.string_of_utf8_bytes([0xF4, 0x90, 0x80, 0x80]) == None,
  )
  // 非法首字节 0xFF。
  assert_true(@infra_codec.string_of_utf8_bytes([0xFF]) == None)
}

///|
test "utf8 roundtrip on multilingual text" {
  let samples = [
    "", "hello", "路径规划", "δοκιμή", "emoji \u{1F600}\u{1F680}", "混合 mix ü水",
  ]
  for s in samples {
    assert_true(
      @infra_codec.string_of_utf8_bytes(@infra_codec.utf8_bytes_of_string(s)) ==
      Some(s),
    )
  }
}
