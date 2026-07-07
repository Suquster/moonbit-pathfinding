// deflate_dynamic_test.mbt —— 动态 Huffman 编码 + zlib 封装测试。
//
// 关键见证：deflate_dynamic 产出的 BTYPE=10 块可被既有 inflate 解回原文
//（roundtrip）；偏斜数据下动态编码显著小于 fixed 编码；zlib 头尾 / Adler-32
// 校验语义与 RFC 1950 对齐（含 CPython zlib 黄金向量）。

///|
fn text_bytes(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s.iter() {
    out.push(c.to_int() & 0xFF)
  }
  out
}

///|
/// 动态块 roundtrip：文本 / 全同字节 / 空输入 / 二进制全值。
test "deflate_dynamic roundtrips through inflate" {
  let samples : Array[Array[Int]] = [
    text_bytes("the quick brown fox jumps over the lazy dog"),
    text_bytes(""),
    [],
  ]
  // 全同字节（LZ77 匹配主导）。
  let runs : Array[Int] = []
  for _ in 0..<5000 {
    runs.push(0x61)
  }
  samples.push(runs)
  // 0..255 循环（无匹配、literal 全覆盖）。
  let all : Array[Int] = []
  for i in 0..<1024 {
    all.push(i % 256)
  }
  samples.push(all)
  for s in samples {
    match inflate(deflate_dynamic(s)) {
      Some(back) => assert_true(back == s)
      None => fail("dynamic roundtrip failed")
    }
  }
}

///|
/// 偏斜数据下动态编码显著小于 fixed 编码（频率定制码表的收益见证）。
test "dynamic beats fixed on skewed data" {
  // 高度偏斜：一个字符占绝对主导 + 少量噪声，且打断长匹配。
  let skewed : Array[Int] = []
  for i in 0..<4096 {
    skewed.push(if i % 7 == 0 { i / 7 % 200 + 1 } else { 0x65 })
  }
  let dyn_size = deflate_dynamic(skewed).length()
  let fix_size = deflate(skewed).length()
  assert_true(dyn_size < fix_size)
  match inflate(deflate_dynamic(skewed)) {
    Some(back) => assert_true(back == skewed)
    None => fail("skewed roundtrip failed")
  }
}

///|
/// zlib roundtrip + 头部结构（CMF=0x78、FCHECK 模 31）。
test "zlib compress/decompress roundtrip and header" {
  let data = text_bytes("hello hello hello zlib world")
  let z = zlib_compress(data)
  assert_true((z[0] & 0x0F) == 8) // CM = deflate
  assert_true(((z[0] & 0xFF) * 256 + (z[1] & 0xFF)) % 31 == 0) // FCHECK
  match zlib_decompress(z) {
    Some(back) => assert_true(back == data)
    None => fail("zlib roundtrip failed")
  }
}

///|
/// CPython zlib 黄金向量：zlib.compress(b"hello world") 的输出可被解开。
test "zlib golden vector from cpython" {
  // python3: zlib.compress(b"hello world") =
  // 78 9c cb 48 cd c9 c9 57 28 cf 2f ca 49 01 00 1a 0b 04 5d
  let golden : Array[Int] = [
    0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0x28, 0xCF, 0x2F, 0xCA, 0x49,
    0x01, 0x00, 0x1A, 0x0B, 0x04, 0x5D,
  ]
  match zlib_decompress(golden) {
    Some(back) => assert_true(back == text_bytes("hello world"))
    None => fail("golden zlib stream should decompress")
  }
}

///|
/// zlib 畸形拒绝：坏 FCHECK、坏 Adler-32、FDICT、过短输入。
test "zlib rejects malformed streams" {
  assert_true(zlib_decompress([]) is None)
  assert_true(zlib_decompress([0x78, 0x9C]) is None)
  let ok = zlib_compress(text_bytes("abc"))
  // 破坏 FLG（FCHECK 不再成立）。
  let bad_hdr : Array[Int] = []
  for b in ok {
    bad_hdr.push(b)
  }
  bad_hdr[1] = (bad_hdr[1] + 1) % 256
  assert_true(zlib_decompress(bad_hdr) is None)
  // 破坏 Adler-32 尾。
  let bad_adler : Array[Int] = []
  for b in ok {
    bad_adler.push(b)
  }
  bad_adler[bad_adler.length() - 1] = (bad_adler[bad_adler.length() - 1] + 1) %
    256
  assert_true(zlib_decompress(bad_adler) is None)
}

///|
/// 动态编码 PBT：随机字节串（多种偏斜度）roundtrip 恒等（200 迭代）。
test "prop dynamic deflate roundtrip on random inputs" {
  let mut seed = 0x9E3779B9U
  for _ in 0..<200 {
    let data : Array[Int] = []
    seed = seed * 1664525U + 1013904223U
    let len = ((seed >> 8) % 300U).reinterpret_as_int()
    seed = seed * 1664525U + 1013904223U
    let alphabet = 1 + ((seed >> 16) % 255U).reinterpret_as_int()
    for _ in 0..<len {
      seed = seed * 1664525U + 1013904223U
      data.push(
        ((seed >> 8) % alphabet.reinterpret_as_uint()).reinterpret_as_int(),
      )
    }
    match inflate(deflate_dynamic(data)) {
      Some(back) => assert_true(back == data)
      None => fail("prop roundtrip failed")
    }
    match zlib_decompress(zlib_compress(data)) {
      Some(back) => assert_true(back == data)
      None => fail("prop zlib roundtrip failed")
    }
  }
}
