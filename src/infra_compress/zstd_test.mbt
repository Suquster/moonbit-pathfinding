// zstd_test.mbt —— Zstandard 帧格式黑盒测试。
//
// 黄金向量来自 python-zstandard 0.25（level 1，write_content_size=True），
// 互通性另经镜像实现由参考解码器 ZstdDecompressor 全用例还原验证。
// 覆盖：黄金帧解码、RLE/Raw roundtrip、多帧级联、跳过帧、
// XXH64 校验、防解压炸弹、畸形输入拒绝、PBT。

///|
/// python-zstandard 黄金帧 1 的原始内容（random.seed(42) 64 字节）。
fn zstd_golden_content() -> Array[Int] {
  [
    57, 12, 140, 125, 114, 71, 52, 44, 216, 16, 15, 47, 111, 119, 13, 101, 214, 112,
    229, 142, 3, 81, 216, 174, 142, 79, 110, 172, 52, 47, 194, 49, 183, 176, 135,
    22, 235, 63, 193, 40, 150, 185, 98, 35, 23, 116, 148, 40, 119, 51, 194, 142,
    232, 186, 83, 189, 181, 107, 136, 36, 87, 125, 83, 236,
  ]
}

///|
test "zstd_decompress 解 python-zstandard 黄金帧（带 XXH64 校验）" {
  let frame : Array[Int] = [
    40, 181, 47, 253, 36, 64, 1, 2, 0, 57, 12, 140, 125, 114, 71, 52, 44, 216, 16,
    15, 47, 111, 119, 13, 101, 214, 112, 229, 142, 3, 81, 216, 174, 142, 79, 110,
    172, 52, 47, 194, 49, 183, 176, 135, 22, 235, 63, 193, 40, 150, 185, 98, 35,
    23, 116, 148, 40, 119, 51, 194, 142, 232, 186, 83, 189, 181, 107, 136, 36, 87,
    125, 83, 236, 100, 82, 37, 47,
  ]
  assert_true(
    @infra_compress.zstd_decompress(frame, 1 << 20) ==
    Some(zstd_golden_content()),
  )
}

///|
test "zstd_decompress 解 python-zstandard 黄金帧（无校验，32 字节）" {
  let frame : Array[Int] = [
    40, 181, 47, 253, 32, 32, 1, 1, 0, 57, 12, 140, 125, 114, 71, 52, 44, 216, 16,
    15, 47, 111, 119, 13, 101, 214, 112, 229, 142, 3, 81, 216, 174, 142, 79, 110,
    172, 52, 47, 194, 49,
  ]
  let expect : Array[Int] = []
  for k in 0..<32 {
    expect.push(zstd_golden_content()[k])
  }
  assert_true(@infra_compress.zstd_decompress(frame, 1 << 20) == Some(expect))
}

///|
test "zstd_compress RLE 块输出与镜像实现黄金字节一致" {
  let data : Array[Int] = []
  for _k in 0..<30 {
    data.push('z'.to_int())
  }
  let expect : Array[Int] = [
    40, 181, 47, 253, 36, 30, 243, 0, 0, 122, 227, 48, 43, 142,
  ]
  assert_true(@infra_compress.zstd_compress(data, true) == expect)
}

///|
test "zstd roundtrip：空 / RLE / 混合 / 跨块（>64KiB）" {
  let cases : Array[Array[Int]] = [[], [], [], []]
  for _k in 0..<20 {
    cases[1].push(7)
  }
  for k in 0..<300 {
    cases[2].push(k * 37 % 256)
  }
  for k in 0..<70000 {
    cases[3].push(if k < 65600 { 5 } else { k % 251 })
  }
  for data in cases {
    for with_checksum in [false, true] {
      let frame = @infra_compress.zstd_compress(data, with_checksum)
      assert_true(@infra_compress.zstd_decompress(frame, 1 << 20) == Some(data))
    }
  }
}

///|
test "zstd 多帧级联与跳过帧" {
  let a : Array[Int] = [1, 2, 3, 4, 5]
  let b : Array[Int] = [9, 9, 9, 9, 9, 9]
  let stream : Array[Int] = []
  for x in @infra_compress.zstd_compress(a, true) {
    stream.push(x)
  }
  // 跳过帧：魔数 0x184D2A50 + 3 字节负载。
  for x in ([0x50, 0x2A, 0x4D, 0x18, 3, 0, 0, 0, 111, 222, 33] : Array[Int]) {
    stream.push(x)
  }
  for x in @infra_compress.zstd_compress(b, false) {
    stream.push(x)
  }
  let expect : Array[Int] = [1, 2, 3, 4, 5, 9, 9, 9, 9, 9, 9]
  assert_true(@infra_compress.zstd_decompress(stream, 1 << 20) == Some(expect))
}

///|
test "zstd 防解压炸弹：max_out 上限强制生效" {
  let data : Array[Int] = []
  for _k in 0..<1000 {
    data.push(8)
  }
  let frame = @infra_compress.zstd_compress(data, false)
  assert_true(@infra_compress.zstd_decompress(frame, 999) is None)
  assert_true(@infra_compress.zstd_decompress(frame, 1000) == Some(data))
}

///|
test "zstd 畸形输入拒绝：坏魔数/截断/校验错/保留块/字典帧" {
  // 坏魔数。
  assert_true(@infra_compress.zstd_decompress([1, 2, 3, 4, 0], 100) is None)
  let good = @infra_compress.zstd_compress([10, 20, 30, 40, 50], true)
  // 截断（去尾字节）。
  let truncated : Array[Int] = []
  for k in 0..<(good.length() - 1) {
    truncated.push(good[k])
  }
  assert_true(@infra_compress.zstd_decompress(truncated, 100) is None)
  // 校验篡改。
  let tampered : Array[Int] = []
  for x in good {
    tampered.push(x)
  }
  tampered[tampered.length() - 1] = tampered[tampered.length() - 1] ^ 0xFF
  assert_true(@infra_compress.zstd_decompress(tampered, 100) is None)
  // Reserved 块类型（type=3）。
  let reserved : Array[Int] = [
    40,
    181,
    47,
    253,
    32,
    1, // FHD 单段，FCS=1
    7 | (1 << 3),
    0,
    0, // last=1, type=3, size=1
    0,
  ]
  assert_true(@infra_compress.zstd_decompress(reserved, 100) is None)
  // 字典帧（Dictionary_ID_flag != 0）显式拒绝。
  let dict_frame : Array[Int] = [40, 181, 47, 253, 0x21, 1, 5, 1, 0, 0]
  assert_true(@infra_compress.zstd_decompress(dict_frame, 100) is None)
  // FCS 与再生长度不符。
  let bad_fcs : Array[Int] = [
    40,
    181,
    47,
    253,
    32,
    9, // 声称 9 字节
    1 | (2 << 3) | 0,
    0,
    0,
    1,
    2, // raw 块只有 2 字节
  ]
  assert_true(@infra_compress.zstd_decompress(bad_fcs, 100) is None)
}

///|
test "zstd roundtrip PBT（200 迭代，含全同/半同/随机负载）" {
  let rng = @infra_pbt.rng_new(20260708UL)
  for _iter in 0..<200 {
    let n = rng.next_below(400)
    let mode = rng.next_below(3)
    let data : Array[Int] = []
    let fill = rng.next_below(256)
    for k in 0..<n {
      if mode == 0 {
        data.push(fill)
      } else if mode == 1 {
        data.push(if k < n / 2 { fill } else { rng.next_below(256) })
      } else {
        data.push(rng.next_below(256))
      }
    }
    let with_checksum = rng.next_bool()
    let frame = @infra_compress.zstd_compress(data, with_checksum)
    assert_true(@infra_compress.zstd_decompress(frame, 1 << 20) == Some(data))
  }
}
