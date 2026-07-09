// zstd_encode_gaps_test.mbt —— zstd 熵编码器分支覆盖收口（INFRA 第十七批）：
// 字面量段各 size_format、单符号退化、大 regen 多流、FSE 归一化边界的
// 无损往返见证。

///|
fn zg_roundtrip(data : Array[Int]) -> Bool {
  let comp = zstd_compress_entropy(data, false)
  zstd_decompress(comp, data.length() + 16) == Some(data)
}

///|
/// 结构化伪随机字节（线性同余），带重复片段以保证可压缩。
fn zg_pattern(n : Int, seed : Int, alphabet : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut s = seed
  while out.length() < n {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    let b = s % alphabet
    // 小片段重复制造 LZ 匹配。
    let rep = 1 + s % 7
    for _ in 0..<rep {
      if out.length() < n {
        out.push(b)
      }
    }
  }
  out
}

///|
test "zstd 熵编码：字面量段 size_format 各档往返" {
  // 小段（1 流、10 位 regen）。
  assert_true(zg_roundtrip(zg_pattern(300, 1, 8)))
  // 中段（4 流、14 位 regen）。
  assert_true(zg_roundtrip(zg_pattern(5000, 2, 8)))
  // 大段（4 流、18 位 regen，逼近 64KB 块上限）。
  assert_true(zg_roundtrip(zg_pattern(60000, 3, 8)))
  // 跨块（>64KB，两块 + 帧级重复偏移延续）。
  assert_true(zg_roundtrip(zg_pattern(70000, 4, 8)))
}

///|
test "zstd 熵编码：单符号退化与高熵回退" {
  // 长同字节 + 异质尾部：字面量段仅 1-2 个符号 → huf_lengths 拒绝回退。
  let mono : Array[Int] = []
  for i in 0..<800 {
    mono.push(if i % 400 == 399 { i % 251 } else { 65 })
  }
  assert_true(zg_roundtrip(mono))
  // 高熵（全 256 字母表、无重复）→ 整块回退 Raw。
  let noisy : Array[Int] = []
  let mut s = 99
  for _ in 0..<2000 {
    s = s * 48271 % 2147483647
    noisy.push(s & 0xFF)
  }
  assert_true(zg_roundtrip(noisy))
  // 二值分布（权重极偏）触发 FSE 归一化削减分支。
  let skew : Array[Int] = []
  for i in 0..<3000 {
    skew.push(if i % 100 == 0 { 66 } else { 65 })
  }
  assert_true(zg_roundtrip(skew))
}

///|
test "zstd 熵编码：长匹配与远距离偏移码档" {
  // 长匹配（ml ≥ 35 高码档）与远距离（of 高码档）。
  let base = zg_pattern(400, 7, 16)
  let data : Array[Int] = []
  for b in base {
    data.push(b)
  }
  for _ in 0..<6 {
    for b in base {
      data.push(b) // 整段重复 → 长匹配 + 大偏移
    }
  }
  for i in 0..<50 {
    data.push(i % 5) // 尾部小字母表
  }
  assert_true(zg_roundtrip(data))
  // 校验和路径。
  let comp = zstd_compress_entropy(data, true)
  assert_true(zstd_decompress(comp, data.length() + 16) == Some(data))
  // 空输入 + 校验和。
  let empty = zstd_compress_entropy([], true)
  assert_true(zstd_decompress(empty, 16) == Some([]))
}
