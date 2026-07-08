// zstd_encode_test.mbt —— 熵压缩侧 roundtrip 与外部互通对拍。

///|
/// 简易 LCG（测试内确定性伪随机）。
fn lcg_next(state : UInt64) -> UInt64 {
  state * 6364136223846793005UL + 1442695040888963407UL
}

///|
test "zstd entropy roundtrip: 重复文本经 Compressed 块无损还原且真压缩" {
  let data : Array[Int] = []
  for i in 0..<40 {
    for
      b in ascii_bytes(
        "packet \{i % 7}: the quick brown fox jumps over the lazy dog\n",
      ) {
      data.push(b)
    }
  }
  let frame = @infra_compress.zstd_compress_entropy(data, true)
  assert_true(frame.length() < data.length() / 2)
  let got = @infra_compress.zstd_decompress(frame, 1 << 20)
  assert_true(got == Some(data))
}

///|
test "zstd entropy roundtrip PBT: 200 组结构化随机输入" {
  let mut seed = 0x9E3779B97F4A7C15UL
  for _iter in 0..<200 {
    seed = lcg_next(seed)
    let n = ((seed >> 33) % 900UL).to_int() + 1
    let data : Array[Int] = []
    let mut s = seed
    for _k in 0..<n {
      s = lcg_next(s)
      // 混合模式：低熵字节 + 周期回指，制造可匹配区。
      let b = if (s >> 40) % 3UL == 0UL {
        ((s >> 33) % 8UL).to_int() + 97
      } else if data.length() > 16 {
        data[data.length() - 13]
      } else {
        ((s >> 33) % 256UL).to_int()
      }
      data.push(b)
    }
    let frame = @infra_compress.zstd_compress_entropy(data, false)
    let got = @infra_compress.zstd_decompress(frame, 1 << 22)
    assert_true(got == Some(data))
  }
}

///|
test "zstd entropy: 高熵输入回退 Raw 块仍无损" {
  let data : Array[Int] = []
  let mut s = 12345UL
  for _k in 0..<600 {
    s = lcg_next(s)
    data.push(((s >> 33) % 256UL).to_int())
  }
  let frame = @infra_compress.zstd_compress_entropy(data, true)
  let got = @infra_compress.zstd_decompress(frame, 1 << 20)
  assert_true(got == Some(data))
}

///|
test "zstd entropy: 空输入 / 全同字节（RLE 路径）" {
  let empty = @infra_compress.zstd_decompress(
    @infra_compress.zstd_compress_entropy([], false),
    16,
  )
  assert_true(empty == Some([]))
  let same : Array[Int] = Array::make(5000, 0x41)
  let frame = @infra_compress.zstd_compress_entropy(same, true)
  assert_true(frame.length() < 32)
  assert_true(@infra_compress.zstd_decompress(frame, 1 << 20) == Some(same))
}

///|
test "zstd entropy: 跨 64KB 分块边界（多块帧）无损" {
  let data : Array[Int] = []
  for i in 0..<12000 {
    for b in ascii_bytes("row \{i % 41};") {
      data.push(b)
    }
  }
  assert_true(data.length() > 65536)
  let frame = @infra_compress.zstd_compress_entropy(data, true)
  assert_true(frame.length() < data.length() / 4)
  let got = @infra_compress.zstd_decompress(frame, 1 << 20)
  assert_true(got == Some(data))
}
