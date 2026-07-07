// LZ4 块格式测试：参考实现黄金向量 + roundtrip + overlap + PBT。

///|
/// python-lz4 `lz4.block.compress(store_size=False)` 黄金压缩流可解压。
test "lz4 decodes reference implementation output" {
  // lz4.block.compress(b"abcabc...×11", store_size=False)。
  let golden = [63, 97, 98, 99, 3, 0, 6, 80, 98, 99, 97, 98, 99]
  let expect : Array[Int] = []
  for _ in 0..<11 {
    for b in [0x61, 0x62, 0x63] {
      expect.push(b)
    }
  }
  assert_true(lz4_decompress(golden, 1024) == Some(expect))
  // 真实英文句子的参考压缩流。
  let golden2 = [
    209, 116, 111, 32, 98, 101, 32, 111, 114, 32, 110, 111, 116, 32, 13, 0, 242,
    8, 44, 32, 116, 104, 97, 116, 32, 105, 115, 32, 116, 104, 101, 32, 113, 117,
    101, 115, 116, 105, 111, 110, 46, 29, 0, 5, 42, 0, 80, 111, 32, 98, 101, 33,
  ]
  let sentence = "to be or not to be, that is the question. to be or not to be!"
  assert_true(lz4_decompress(golden2, 1024) == Some(utf8_bytes_c(sentence)))
}

///|
/// UTF-8 字节工具（测试内部用）。
fn utf8_bytes_c(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s {
    out.push(c.to_int() & 0x7F) // 测试串均为 ASCII
  }
  out
}

///|
/// roundtrip：高冗余文本显著压缩且无损。
test "lz4 roundtrip compresses redundant data" {
  let data : Array[Int] = []
  for _ in 0..<500 {
    for b in [0x61, 0x62, 0x63, 0x64] {
      data.push(b)
    }
  }
  let enc = lz4_compress(data)
  assert_true(enc.length() * 10 < data.length())
  assert_true(lz4_decompress(enc, data.length()) == Some(data))
}

///|
/// overlap copy：offset < match 长的 RLE 式自引用。
test "lz4 overlap copy semantics" {
  // 手工构造：literal "ab" + match(offset=1, len=8) → "a" + "b"×9？
  // offset=1 时逐字节复制最后一个字节 → "ab" + "b"×8。
  let stream = [
    0x24, 0x61, 0x62, 0x01, 0x00, 0x50, 0x78, 0x79, 0x7A, 0x77, 0x76,
  ]
  let got = lz4_decompress(stream, 100)
  assert_true(
    got ==
    Some([
      0x61, 0x62, 0x62, 0x62, 0x62, 0x62, 0x62, 0x62, 0x62, 0x62, 0x78, 0x79, 0x7A,
      0x77, 0x76,
    ]),
  )
}

///|
/// 畸形输入显式拒绝：零 offset、越界 offset、截断、输出超限。
test "lz4 rejects malformed streams" {
  assert_true(lz4_decompress([0x10, 0x61, 0x00, 0x00, 0x40], 100) is None) // offset=0
  assert_true(lz4_decompress([0x10, 0x61, 0x09, 0x00, 0x40], 100) is None) // offset 越界
  assert_true(lz4_decompress([0x40, 0x61], 100) is None) // literal 截断
  assert_true(lz4_decompress([0xF0, 0xFF], 100) is None) // 长度扩展后截断
  // 输出超限（max_out 防炸弹）。
  let big : Array[Int] = Array::make(300, 0x41)
  let enc = lz4_compress(big)
  assert_true(lz4_decompress(enc, 100) is None)
}

///|
/// 空输入与短输入（< 13 字节纯 literal 路径）。
test "lz4 empty and short inputs" {
  assert_true(lz4_compress([]) == [])
  assert_true(lz4_decompress([], 10) == Some([]))
  let short = [1, 2, 3, 4, 5]
  assert_true(lz4_decompress(lz4_compress(short), 10) == Some(short))
}

///|
/// PBT：任意字节串 roundtrip 恒等（250 迭代，混合冗余/随机）。
test "lz4 pbt roundtrip identity" {
  let mut seed = 77U
  let next = fn() -> UInt {
    seed = seed * 1664525U + 1013904223U
    seed
  }
  for it in 0..<250 {
    let n = (next() % 400U).reinterpret_as_int()
    let data : Array[Int] = []
    let alphabet = if it % 2 == 0 { 4U } else { 256U } // 偶数轮高冗余
    for i in 0..<n {
      data.push(((next() >> 8) % alphabet).reinterpret_as_int())
      ignore(i)
    }
    let enc = lz4_compress(data)
    assert_true(lz4_decompress(enc, n + 16) == Some(data))
  }
}
