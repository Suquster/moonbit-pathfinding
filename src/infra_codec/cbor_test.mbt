// cbor_test.mbt —— CBOR（RFC 8949）编解码测试。
//
// 已知向量来自 RFC 8949 附录 A（Examples of Encoded CBOR Data Items）。

///|
fn hex_of(v : @infra_codec.CborValue) -> String {
  @infra_codec.hex_encode(@infra_codec.cbor_encode(v))
}

///|
test "cbor rfc8949 appendix-a unsigned integers" {
  assert_eq(hex_of(@infra_codec.CborUInt(0UL)), "00")
  assert_eq(hex_of(@infra_codec.CborUInt(1UL)), "01")
  assert_eq(hex_of(@infra_codec.CborUInt(10UL)), "0a")
  assert_eq(hex_of(@infra_codec.CborUInt(23UL)), "17")
  assert_eq(hex_of(@infra_codec.CborUInt(24UL)), "1818")
  assert_eq(hex_of(@infra_codec.CborUInt(25UL)), "1819")
  assert_eq(hex_of(@infra_codec.CborUInt(100UL)), "1864")
  assert_eq(hex_of(@infra_codec.CborUInt(1000UL)), "1903e8")
  assert_eq(hex_of(@infra_codec.CborUInt(1000000UL)), "1a000f4240")
  assert_eq(
    hex_of(@infra_codec.CborUInt(1000000000000UL)),
    "1b000000e8d4a51000",
  )
  assert_eq(
    hex_of(@infra_codec.CborUInt(18446744073709551615UL)),
    "1bffffffffffffffff",
  )
}

///|
test "cbor rfc8949 appendix-a negative integers" {
  // -1 编码为 major 1 / n=0；-10 → n=9；-100 → n=99；-1000 → n=999。
  assert_eq(hex_of(@infra_codec.CborNInt(0UL)), "20")
  assert_eq(hex_of(@infra_codec.CborNInt(9UL)), "29")
  assert_eq(hex_of(@infra_codec.CborNInt(99UL)), "3863")
  assert_eq(hex_of(@infra_codec.CborNInt(999UL)), "3903e7")
}

///|
test "cbor rfc8949 appendix-a simple and float" {
  assert_eq(hex_of(@infra_codec.CborBool(false)), "f4")
  assert_eq(hex_of(@infra_codec.CborBool(true)), "f5")
  assert_eq(hex_of(@infra_codec.CborNull), "f6")
  // 1.1 → float64: fb3ff199999999999a（附录 A）。
  assert_eq(hex_of(@infra_codec.CborFloat(1.1)), "fb3ff199999999999a")
  // -4.1 → fbc010666666666666。
  assert_eq(hex_of(@infra_codec.CborFloat(-4.1)), "fbc010666666666666")
}

///|
test "cbor rfc8949 appendix-a strings arrays maps" {
  assert_eq(hex_of(@infra_codec.CborText("")), "60")
  assert_eq(hex_of(@infra_codec.CborText("a")), "6161")
  assert_eq(hex_of(@infra_codec.CborText("IETF")), "6449455446")
  // "\u00fc" → 62c3bc（UTF-8 两字节）。
  assert_eq(hex_of(@infra_codec.CborText("ü")), "62c3bc")
  // "\u6c34" → 63e6b0b4（UTF-8 三字节）。
  assert_eq(hex_of(@infra_codec.CborText("水")), "63e6b0b4")
  assert_eq(hex_of(@infra_codec.CborBytes([])), "40")
  assert_eq(
    hex_of(@infra_codec.CborBytes([0x01, 0x02, 0x03, 0x04])),
    "4401020304",
  )
  assert_eq(hex_of(@infra_codec.CborArray([])), "80")
  assert_eq(
    hex_of(
      @infra_codec.CborArray([
        @infra_codec.CborUInt(1UL),
        @infra_codec.CborUInt(2UL),
        @infra_codec.CborUInt(3UL),
      ]),
    ),
    "83010203",
  )
  assert_eq(hex_of(@infra_codec.CborMap([])), "a0")
  // {"a": 1, "b": [2, 3]} → a26161016162820203。
  assert_eq(
    hex_of(
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
    "a26161016162820203",
  )
}

///|
test "cbor decode roundtrip of nested value" {
  let v = @infra_codec.CborMap([
    (
      @infra_codec.CborText("路径"),
      @infra_codec.CborArray([
        @infra_codec.CborUInt(42UL),
        @infra_codec.CborNInt(7UL),
        @infra_codec.CborFloat(3.5),
        @infra_codec.CborBool(true),
        @infra_codec.CborNull,
      ]),
    ),
    (
      @infra_codec.CborBytes([0, 127, 255]),
      @infra_codec.CborText("δοκιμή"),
    ),
  ])
  let bytes = @infra_codec.cbor_encode(v)
  assert_true(@infra_codec.cbor_decode(bytes) == Some(v))
}

///|
test "cbor decode rejects malformed input" {
  // 空输入。
  assert_true(@infra_codec.cbor_decode([]) == None)
  // 截断的扩展长度（0x18 需要 1 个后续字节）。
  assert_true(@infra_codec.cbor_decode([0x18]) == None)
  // 截断的文本串（声明 4 字节只给 2 字节）。
  assert_true(@infra_codec.cbor_decode([0x64, 0x49, 0x45]) == None)
  // 尾随字节。
  assert_true(@infra_codec.cbor_decode([0x01, 0x02]) == None)
  // 孤立 break（0xFF）不构成数据项。
  assert_true(@infra_codec.cbor_decode([0xFF]) == None)
  // 截断的 tag（major 6 缺内层项）。
  assert_true(@infra_codec.cbor_decode([0xC0]) == None)
  // 非法 UTF-8 文本（孤立续字节）。
  assert_true(@infra_codec.cbor_decode([0x61, 0x80]) == None)
  // 保留 additional info 28。
  assert_true(@infra_codec.cbor_decode([0x1C]) == None)
}

///|
test "cbor decode depth limit guards deep nesting" {
  // 构造 600 层嵌套数组 [[[...]]]，超过 cbor_max_depth=512 应拒绝。
  let bytes : Array[Int] = []
  for _ in 0..<600 {
    bytes.push(0x81) // array(1)
  }
  bytes.push(0x00) // 0
  assert_true(@infra_codec.cbor_decode(bytes) == None)
  // 100 层则应成功。
  let ok : Array[Int] = []
  for _ in 0..<100 {
    ok.push(0x81)
  }
  ok.push(0x00)
  assert_true(@infra_codec.cbor_decode(ok) is Some(_))
}

///|
/// PBT：随机生成 CBOR 值做编解码 roundtrip。
fn gen_cbor(rng : @infra_pbt.Rng, depth : Int) -> @infra_codec.CborValue {
  let kind = if depth <= 0 { rng.next_below(6) } else { rng.next_below(8) }
  match kind {
    0 => @infra_codec.CborUInt(rng.next_below(1000000).to_uint64())
    1 => @infra_codec.CborNInt(rng.next_below(1000000).to_uint64())
    2 => {
      let bs : Array[Int] = []
      for _ in 0..<rng.next_below(8) {
        bs.push(rng.next_below(256))
      }
      @infra_codec.CborBytes(bs)
    }
    3 => {
      let sb = StringBuilder::new()
      for _ in 0..<rng.next_below(6) {
        // 覆盖 ASCII / 两字节 / 三字节 / 四字节码点。
        let c = match rng.next_below(4) {
          0 => 'x'
          1 => 'é'
          2 => '水'
          _ => '\u{1F600}'
        }
        sb.write_char(c)
      }
      @infra_codec.CborText(sb.to_string())
    }
    4 => @infra_codec.CborBool(rng.next_below(2) == 0)
    5 => @infra_codec.CborNull
    6 => {
      let items : Array[@infra_codec.CborValue] = []
      for _ in 0..<rng.next_below(4) {
        items.push(gen_cbor(rng, depth - 1))
      }
      @infra_codec.CborArray(items)
    }
    _ => {
      let pairs : Array[(@infra_codec.CborValue, @infra_codec.CborValue)] = []
      for _ in 0..<rng.next_below(3) {
        pairs.push((gen_cbor(rng, depth - 1), gen_cbor(rng, depth - 1)))
      }
      @infra_codec.CborMap(pairs)
    }
  }
}

///|
test "cbor pbt roundtrip 200 random values" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<200 {
    let v = gen_cbor(rng, 3)
    let bytes = @infra_codec.cbor_encode(v)
    assert_true(@infra_codec.cbor_decode(bytes) == Some(v))
  }
}
