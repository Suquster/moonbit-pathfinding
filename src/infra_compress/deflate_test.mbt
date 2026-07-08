// deflate_test.mbt —— DEFLATE/gzip 黑盒测试。
//
// 黄金向量来自 CPython zlib 1.3（生成命令：
// `zlib.compressobj(9, zlib.DEFLATED, -15)` / `gzip.compress(..., mtime=0)`），
// 覆盖 stored / fixed / dynamic 三种块类型的互通解码、gzip 头尾校验、
// 自 round-trip 与 PBT、畸形输入拒绝。

///|
/// 测试文本（90 字节，内含重复短语触发 LZ77 回拷）。
fn sample_text() -> Array[Int] {
  let s = "the quick brown fox jumps over the lazy dog. the quick brown fox jumps over the lazy dog!"
  let out : Array[Int] = []
  for c in s {
    out.push(c.to_int())
  }
  out
}

///|
test "inflate 解 zlib fixed Huffman 黄金向量（level 9）" {
  let compressed : Array[Int] = [
    43, 201, 72, 85, 40, 44, 205, 76, 206, 86, 72, 42, 202, 47, 207, 83, 72, 203,
    175, 80, 200, 42, 205, 45, 40, 86, 200, 47, 75, 45, 82, 40, 1, 74, 231, 36, 86,
    85, 42, 164, 228, 167, 235, 129, 121, 68, 42, 86, 4, 0,
  ]
  assert_true(@infra_compress.inflate(compressed) == Some(sample_text()))
}

///|
test "inflate 解 zlib stored 块黄金向量（level 0）" {
  let compressed : Array[Int] = [
    1, 89, 0, 166, 255, 116, 104, 101, 32, 113, 117, 105, 99, 107, 32, 98, 114, 111,
    119, 110, 32, 102, 111, 120, 32, 106, 117, 109, 112, 115, 32, 111, 118, 101,
    114, 32, 116, 104, 101, 32, 108, 97, 122, 121, 32, 100, 111, 103, 46, 32, 116,
    104, 101, 32, 113, 117, 105, 99, 107, 32, 98, 114, 111, 119, 110, 32, 102, 111,
    120, 32, 106, 117, 109, 112, 115, 32, 111, 118, 101, 114, 32, 116, 104, 101,
    32, 108, 97, 122, 121, 32, 100, 111, 103, 33,
  ]
  assert_true(@infra_compress.inflate(compressed) == Some(sample_text()))
}

///|
test "inflate 解 zlib dynamic Huffman 黄金向量" {
  // 源数据：82 字节英文句子 ×20 = 1620 字节。
  let sentence = "in computer science, a huffman code is a particular type of optimal prefix code. "
  let expected : Array[Int] = []
  for _ in 0..<20 {
    for c in sentence {
      expected.push(c.to_int())
    }
  }
  let compressed : Array[Int] = [
    237, 204, 237, 9, 128, 48, 12, 132, 225, 85, 110, 0, 113, 167, 16, 19, 12, 180,
    54, 164, 45, 232, 246, 126, 172, 97, 254, 222, 123, 60, 118, 128, 91, 245, 57,
    36, 208, 217, 228, 96, 89, 64, 216, 167, 106, 165, 183, 109, 2, 235, 207, 226,
    20, 195, 120, 22, 10, 140, 203, 5, 77, 209, 124, 88, 165, 2, 15, 81, 59, 191,
    239, 10, 75, 48, 193, 4, 19, 76, 240, 175, 224, 13,
  ]
  assert_true(@infra_compress.inflate(compressed) == Some(expected))
}

///|
test "gzip_decompress 解 CPython gzip 黄金向量并校验 CRC/ISIZE" {
  let gz : Array[Int] = [
    31, 139, 8, 0, 0, 0, 0, 0, 2, 3, 43, 201, 72, 85, 40, 44, 205, 76, 206, 86, 72,
    42, 202, 47, 207, 83, 72, 203, 175, 80, 200, 42, 205, 45, 40, 86, 200, 47, 75,
    45, 82, 40, 1, 74, 231, 36, 86, 85, 42, 164, 228, 167, 235, 129, 121, 68, 42,
    86, 4, 0, 122, 129, 144, 126, 89, 0, 0, 0,
  ]
  assert_true(@infra_compress.gzip_decompress(gz) == Some(sample_text()))
}

///|
test "deflate→inflate round-trip：文本 / 空输入 / 全同字节 / 全 256 值" {
  let text = sample_text()
  assert_true(
    @infra_compress.inflate(@infra_compress.deflate(text)) == Some(text),
  )
  let empty : Array[Int] = []
  assert_true(
    @infra_compress.inflate(@infra_compress.deflate(empty)) == Some(empty),
  )
  let runs : Array[Int] = Array::make(5000, 0x41)
  assert_true(
    @infra_compress.inflate(@infra_compress.deflate(runs)) == Some(runs),
  )
  let all : Array[Int] = []
  for i in 0..<256 {
    all.push(i)
  }
  assert_true(
    @infra_compress.inflate(@infra_compress.deflate(all)) == Some(all),
  )
}

///|
test "deflate 对重复文本产生实际压缩（LZ77 生效）" {
  let data : Array[Int] = []
  for _ in 0..<50 {
    for c in "abcdefgh-abcdefgh-" {
      data.push(c.to_int())
    }
  }
  let compressed = @infra_compress.deflate(data)
  assert_true(compressed.length() * 4 < data.length())
  assert_true(@infra_compress.inflate(compressed) == Some(data))
}

///|
test "gzip round-trip 与互检（自产 gzip 可被自解且 CRC 一致）" {
  let text = sample_text()
  let gz = @infra_compress.gzip_compress(text)
  assert_true(@infra_compress.gzip_decompress(gz) == Some(text))
  // 篡改任一负载字节 → CRC 校验失败 → None。
  let bad = gz.copy()
  bad[12] = bad[12] ^ 0xFF
  assert_true(@infra_compress.gzip_decompress(bad) == None)
}

///|
test "畸形输入拒绝：截断流 / 保留块类型 / stored LEN 不匹配 / 坏魔数" {
  // 截断的 fixed 块（丢结尾）。
  let truncated : Array[Int] = [43, 201, 72]
  assert_true(@infra_compress.inflate(truncated) == None)
  // BTYPE=11 保留。
  assert_true(@infra_compress.inflate([0x07]) == None)
  // stored 块 LEN 与 ~LEN 不互补。
  assert_true(
    @infra_compress.inflate([0x01, 0x02, 0x00, 0x00, 0x00, 0x61, 0x61]) == None,
  )
  // gzip 魔数错误。
  let gz = @infra_compress.gzip_compress(sample_text())
  let bad = gz.copy()
  bad[0] = 0x1E
  assert_true(@infra_compress.gzip_decompress(bad) == None)
  // 空输入。
  assert_true(@infra_compress.inflate([]) == None)
  assert_true(@infra_compress.gzip_decompress([]) == None)
}

///|
test "PBT：随机字节数组 deflate/inflate 与 gzip round-trip（200 迭代）" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<200 {
    let n = rng.next_below(300)
    let data : Array[Int] = []
    for _ in 0..<n {
      // 混合：一半窄字母表（触发匹配）、一半全字节。
      if rng.next_bool() {
        data.push(97 + rng.next_below(4))
      } else {
        data.push(rng.next_below(256))
      }
    }
    assert_true(
      @infra_compress.inflate(@infra_compress.deflate(data)) == Some(data),
    )
    assert_true(
      @infra_compress.gzip_decompress(@infra_compress.gzip_compress(data)) ==
      Some(data),
    )
  }
}

///|
/// 十六进制字符串转字节数组（测试辅助）。
fn dfh_hex(hexstr : String) -> Array[Int] {
  fn hv(c : Char) -> Int {
    let x = c.to_int()
    if x >= 48 && x <= 57 {
      x - 48
    } else {
      x - 87
    }
  }

  let out : Array[Int] = []
  let mut k = 0
  while k + 1 < hexstr.length() {
    out.push(
      hv(hexstr[k].to_char().unwrap()) * 16 +
      hv(hexstr[k + 1].to_char().unwrap()),
    )
    k = k + 2
  }
  out
}

///|
/// RFC 1952 §2.2 多成员 gzip：自产两成员拼接往返、python gzip 黄金
/// 向量（`gzip.compress(a)+gzip.compress(b)`）、尾随垃圾拒绝。
test "gzip 多成员流解压与尾随垃圾拒绝" {
  // 自产两成员。
  let a : Array[Int] = []
  for i in 0..<400 {
    a.push(65 + i % 7)
  }
  let b : Array[Int] = [0, 255, 1, 254, 2, 253]
  let joined = @infra_compress.gzip_compress(a)
  for x in @infra_compress.gzip_compress(b) {
    joined.push(x)
  }
  let expect = a.copy()
  for x in b {
    expect.push(x)
  }
  assert_true(@infra_compress.gzip_decompress(joined) == Some(expect))
  // 尾随垃圾（既非新成员头也非空）拒绝。
  joined.push(0)
  assert_true(@infra_compress.gzip_decompress(joined) == None)
  // python gzip 黄金向量：`gzip.compress(a,9)+gzip.compress(b,9)`，
  // a = b"hello multi-member "*20，b = "第二个成员 second member\n" UTF-8 ×10。
  let golden = dfh_hex(
    "1f8b0800a67e4e6a02ffcb48cdc9c957c82dcd29c9d4cd4dcd4d4a2d52c81815a28f10003e99ccc47c0100001f8b0800a67e4e6a02ff7bbe66cd935d3d4f76ac7ad631e1e9c4190ac5a9c9f979290ab9a9b949a9455ccf476591640102c4f4812c010000",
  )
  match @infra_compress.gzip_decompress(golden) {
    None => abort("python 多成员黄金向量解压失败")
    Some(dec) => {
      assert_eq(dec.length(), 680)
      // 第一成员前 19 字节 = "hello multi-member "。
      let head = "hello multi-member "
      for k in 0..<head.length() {
        assert_eq(dec[k], head[k].to_int() & 0xFF)
      }
      // 第二成员起点（380）为 UTF-8 “第” 的首字节 0xE7。
      assert_eq(dec[380], 0xE7)
    }
  }
}
