// zlib_dict_test.mbt —— zlib 预置字典（RFC 1950 §2.2 FDICT）收口
// （INFRA 第四十九批）：压缩/解压 roundtrip、跨起点回引增益、畸形拒绝。

///|
fn zd_bytes(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s.iter() {
    out.push(c.to_int() & 0xFF)
  }
  out
}

///|
test "zlib FDICT：预置字典 roundtrip 与压缩增益" {
  let dict = zd_bytes("the quick brown fox jumps over the lazy dog")
  let data = zd_bytes("the quick brown fox says hello to the lazy dog")
  let framed = @infra_compress.zlib_compress_with_dict(data, dict)
  // FDICT 位与 FCHECK 均成立。
  assert_eq(framed[1] & 0x20, 0x20)
  assert_eq(((framed[0] & 0xFF) * 256 + (framed[1] & 0xFF)) % 31, 0)
  assert_true(
    @infra_compress.zlib_decompress_with_dict(framed, dict) == Some(data),
  )
  // 字典命中应带来压缩体量优势（数据与字典高度重叠）。
  let plain = @infra_compress.zlib_compress(data)
  // FDICT 帧多 4 字节 DICTID，仍应更短。
  assert_true(framed.length() < plain.length())
}

///|
test "zlib FDICT：空数据与长字典（>32K 截尾）roundtrip" {
  let dict = zd_bytes("abc")
  let framed = @infra_compress.zlib_compress_with_dict([], dict)
  assert_true(
    @infra_compress.zlib_decompress_with_dict(framed, dict) == Some([]),
  )
  // 超过 32K 的字典只保留尾部入窗，编解两侧一致。
  let big_dict : Array[Int] = []
  for i in 0..<40000 {
    big_dict.push(i % 251)
  }
  let data : Array[Int] = []
  for i in 0..<300 {
    data.push((39700 + i) % 251) // 与字典尾部重叠
  }
  let framed2 = @infra_compress.zlib_compress_with_dict(data, big_dict)
  assert_true(
    @infra_compress.zlib_decompress_with_dict(framed2, big_dict) == Some(data),
  )
}

///|
test "zlib FDICT：畸形与错配拒绝" {
  let dict = zd_bytes("dictionary")
  let data = zd_bytes("payload payload payload")
  let framed = @infra_compress.zlib_compress_with_dict(data, dict)
  // 无字典入口拒绝 FDICT 帧。
  assert_true(@infra_compress.zlib_decompress(framed) == None)
  // 错误字典（DICTID 不符）。
  assert_true(
    @infra_compress.zlib_decompress_with_dict(framed, zd_bytes("wrong")) == None,
  )
  // 非 FDICT 帧交给带字典入口。
  let plain = @infra_compress.zlib_compress(data)
  assert_true(@infra_compress.zlib_decompress_with_dict(plain, dict) == None)
  // 过短输入。
  assert_true(
    @infra_compress.zlib_decompress_with_dict([0x78, 0x20], dict) == None,
  )
  // 坏 CM / 坏 FCHECK。
  let bad_cm = framed.copy()
  bad_cm[0] = 0x77
  assert_true(@infra_compress.zlib_decompress_with_dict(bad_cm, dict) == None)
  let bad_fcheck = framed.copy()
  bad_fcheck[1] = bad_fcheck[1] ^ 0x01
  assert_true(
    @infra_compress.zlib_decompress_with_dict(bad_fcheck, dict) == None,
  )
  // 坏 Adler-32。
  let bad_adler = framed.copy()
  bad_adler[bad_adler.length() - 1] = bad_adler[bad_adler.length() - 1] ^ 0xFF
  assert_true(
    @infra_compress.zlib_decompress_with_dict(bad_adler, dict) == None,
  )
}

///|
test "inflate_preset：跨起点回引与无字典等价" {
  // 无字典时与 inflate 等价。
  let data = zd_bytes("hello hello hello")
  let raw = @infra_compress.deflate_dynamic(data)
  assert_true(@infra_compress.inflate_preset(raw, []) == Some(data))
}
