// cbor_full_test.mbt —— RFC 8949 全量特性收口（INFRA 第四十七批）：
// tag、undefined、float16/float32 与不定长字节串/文本/数组/映射，
// 向量取自 RFC 8949 附录 A。

///|
fn cff_hex(bytes : Array[Int]) -> String {
  let sb = StringBuilder::new()
  let digits = "0123456789abcdef"
  for b in bytes {
    sb.write_char(digits.get_char((b >> 4) & 0xF).unwrap())
    sb.write_char(digits.get_char(b & 0xF).unwrap())
  }
  sb.to_string()
}

///|
test "cbor tag：附录 A 向量与编码 roundtrip" {
  // 0xc11a514b67b0 → 1(1363896240)。
  let bytes = [0xC1, 0x1A, 0x51, 0x4B, 0x67, 0xB0]
  let v = @infra_codec.CborTag(1UL, @infra_codec.CborUInt(1363896240UL))
  assert_true(@infra_codec.cbor_decode(bytes) == Some(v))
  assert_eq(cff_hex(@infra_codec.cbor_encode(v)), "c11a514b67b0")
  // 嵌套 tag：0xd8 0x18（tag 24）包裹字节串。
  match @infra_codec.cbor_decode([0xD8, 0x18, 0x41, 0x07]) {
    Some(@infra_codec.CborTag(24UL, @infra_codec.CborBytes(bs))) =>
      assert_true(bs == [7])
    _ => assert_true(false)
  }
}

///|
test "cbor undefined：simple 23 编解码 roundtrip" {
  assert_true(
    @infra_codec.cbor_decode([0xF7]) == Some(@infra_codec.CborUndefined),
  )
  assert_eq(cff_hex(@infra_codec.cbor_encode(@infra_codec.CborUndefined)), "f7")
}

///|
test "cbor float16：附录 A 向量（含次正规/无穷/NaN）" {
  // 0xf93c00 → 1.0
  assert_true(
    @infra_codec.cbor_decode([0xF9, 0x3C, 0x00]) ==
    Some(@infra_codec.CborFloat(1.0)),
  )
  // 0xf90001 → 5.960464477539063e-8（最小次正规）。
  assert_true(
    @infra_codec.cbor_decode([0xF9, 0x00, 0x01]) ==
    Some(@infra_codec.CborFloat(5.960464477539063e-8)),
  )
  // 0xf9c400 → -4.0
  assert_true(
    @infra_codec.cbor_decode([0xF9, 0xC4, 0x00]) ==
    Some(@infra_codec.CborFloat(-4.0)),
  )
  // 0xf97c00 → Infinity；0xf9fc00 → -Infinity。
  match @infra_codec.cbor_decode([0xF9, 0x7C, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d > 1.0e308)
    _ => assert_true(false)
  }
  match @infra_codec.cbor_decode([0xF9, 0xFC, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d < -1.0e308)
    _ => assert_true(false)
  }
  // 0xf97e00 → NaN。
  match @infra_codec.cbor_decode([0xF9, 0x7E, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d != d)
    _ => assert_true(false)
  }
  // 截断的 float16。
  assert_true(@infra_codec.cbor_decode([0xF9, 0x3C]) == None)
}

///|
test "cbor float32：附录 A 向量" {
  // 0xfa47c35000 → 100000.0
  assert_true(
    @infra_codec.cbor_decode([0xFA, 0x47, 0xC3, 0x50, 0x00]) ==
    Some(@infra_codec.CborFloat(100000.0)),
  )
  // 0xfa7f7fffff → 3.4028234663852886e38（float32 最大值）。
  assert_true(
    @infra_codec.cbor_decode([0xFA, 0x7F, 0x7F, 0xFF, 0xFF]) ==
    Some(@infra_codec.CborFloat(3.4028234663852886e38)),
  )
  // 次正规最小值 0xfa00000001 → 1.401298464324817e-45。
  assert_true(
    @infra_codec.cbor_decode([0xFA, 0x00, 0x00, 0x00, 0x01]) ==
    Some(@infra_codec.CborFloat(1.401298464324817e-45)),
  )
  // NaN 0xfa7fc00000。
  match @infra_codec.cbor_decode([0xFA, 0x7F, 0xC0, 0x00, 0x00]) {
    Some(@infra_codec.CborFloat(d)) => assert_true(d != d)
    _ => assert_true(false)
  }
  // 截断的 float32。
  assert_true(@infra_codec.cbor_decode([0xFA, 0x00]) == None)
}

///|
test "cbor 不定长字节串/文本：附录 A 向量与畸形拒绝" {
  // 0x5f42010243030405ff → h'0102030405'。
  assert_true(
    @infra_codec.cbor_decode([
      0x5F, 0x42, 0x01, 0x02, 0x43, 0x03, 0x04, 0x05, 0xFF,
    ]) ==
    Some(@infra_codec.CborBytes([1, 2, 3, 4, 5])),
  )
  // 0x7f657374726561646d696e67ff → "streaming"。
  assert_true(
    @infra_codec.cbor_decode([
      0x7F, 0x65, 0x73, 0x74, 0x72, 0x65, 0x61, 0x64, 0x6D, 0x69, 0x6E, 0x67, 0xFF,
    ]) ==
    Some(@infra_codec.CborText("streaming")),
  )
  // 空不定长文本 0x7fff → ""。
  assert_true(
    @infra_codec.cbor_decode([0x7F, 0xFF]) == Some(@infra_codec.CborText("")),
  )
  // 块类型不符（文本串中夹字节串块）拒绝。
  assert_true(@infra_codec.cbor_decode([0x7F, 0x41, 0x61, 0xFF]) == None)
  // 嵌套不定长块拒绝（RFC 8949 §3.2.3 明确禁止）。
  assert_true(@infra_codec.cbor_decode([0x5F, 0x5F, 0xFF, 0xFF]) == None)
  // 缺 break 截断拒绝。
  assert_true(@infra_codec.cbor_decode([0x5F, 0x41, 0x01]) == None)
  // 块长度越界拒绝。
  assert_true(@infra_codec.cbor_decode([0x5F, 0x42, 0x01, 0xFF]) == None)
}

///|
test "cbor 不定长数组/映射：附录 A 向量与畸形拒绝" {
  // 0x9fff → []。
  assert_true(
    @infra_codec.cbor_decode([0x9F, 0xFF]) == Some(@infra_codec.CborArray([])),
  )
  // 0x9f018202039f0405ffff → [1, [2, 3], [4, 5]]。
  assert_true(
    @infra_codec.cbor_decode([
      0x9F, 0x01, 0x82, 0x02, 0x03, 0x9F, 0x04, 0x05, 0xFF, 0xFF,
    ]) ==
    Some(
      @infra_codec.CborArray([
        @infra_codec.CborUInt(1UL),
        @infra_codec.CborArray([
          @infra_codec.CborUInt(2UL),
          @infra_codec.CborUInt(3UL),
        ]),
        @infra_codec.CborArray([
          @infra_codec.CborUInt(4UL),
          @infra_codec.CborUInt(5UL),
        ]),
      ]),
    ),
  )
  // 0xbf61610161629f0203ffff → {"a": 1, "b": [2, 3]}。
  assert_true(
    @infra_codec.cbor_decode([
      0xBF, 0x61, 0x61, 0x01, 0x61, 0x62, 0x9F, 0x02, 0x03, 0xFF, 0xFF,
    ]) ==
    Some(
      @infra_codec.CborMap([
        (@infra_codec.CborText("a"), @infra_codec.CborUInt(1UL)),
        (
          @infra_codec.CborText("b"),
          @infra_codec.CborArray([
            @infra_codec.CborUInt(2UL),
            @infra_codec.CborUInt(3UL),
          ]),
        ),
      ]),
    ),
  )
  // 不定长映射键后缺值拒绝。
  assert_true(@infra_codec.cbor_decode([0xBF, 0x61, 0x61, 0xFF]) == None)
  // 不定长数组缺 break 截断拒绝。
  assert_true(@infra_codec.cbor_decode([0x9F, 0x01]) == None)
  // 不定长数组同样受嵌套深度上限保护。
  let deep : Array[Int] = []
  for _ in 0..<600 {
    deep.push(0x9F)
  }
  for _ in 0..<600 {
    deep.push(0xFF)
  }
  assert_true(@infra_codec.cbor_decode(deep) == None)
}

///|
test "cbor 不定长解码与 canonical 再编码等价" {
  // 不定长形式解码后再编码得到定长 canonical 形式，语义一致。
  let bytes = [0x9F, 0x01, 0x02, 0xFF]
  match @infra_codec.cbor_decode(bytes) {
    Some(v) => {
      assert_eq(cff_hex(@infra_codec.cbor_encode(v)), "820102")
      assert_true(
        @infra_codec.cbor_decode(@infra_codec.cbor_encode(v)) == Some(v),
      )
    }
    None => assert_true(false)
  }
}
