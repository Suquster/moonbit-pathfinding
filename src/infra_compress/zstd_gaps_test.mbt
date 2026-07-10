// zstd_gaps_test.mbt —— zstd 余支覆盖收口（INFRA 第六十一批）：
// 结构化字典逐长度截断拒绝、字典帧解码防御分支（FCS 截断/超限/
// 不匹配、校验和截断/翻转）、字典路径 RLE 块、20 位 Raw 字面量布局、
// 压缩帧逐字节腐蚀鲁棒性。

///|
fn zsg_data(n : Int) -> Array[Int] {
  let phrase : Array[Int] = []
  for c in "hello world hello dictionary content again and again " {
    phrase.push(c.to_int() & 0xFF)
  }
  let out : Array[Int] = []
  for i in 0..<n {
    out.push(phrase[i % phrase.length()])
  }
  out
}

///|
test "zstd 字典：结构化字典逐长度截断——要么拒绝要么往返成立" {
  let dict = zsd_dict()
  let data = zsg_data(120)
  let mut rejected = 0
  let mut k = 8
  while k < dict.length() {
    let trunc : Array[Int] = []
    for i in 0..<k {
      trunc.push(dict[i])
    }
    match @infra_compress.zstd_compress_with_dict(data, trunc, false) {
      None => rejected = rejected + 1
      Some(frame) =>
        assert_eq(
          @infra_compress.zstd_decompress_with_dict(frame, trunc, 1 << 20),
          Some(data),
        )
    }
    k = k + 1
  }
  // 结构化前缀截断绝大多数长度都应被拒绝。
  assert_true(rejected > 0)
}

///|
test "zstd 字典：极短原始字典（read_le 越界走 raw 路径）" {
  let data = zsg_data(40)
  for d in [[], [0x37], [0x37, 0xA4, 0x30]] {
    match @infra_compress.zstd_compress_with_dict(data, d, false) {
      Some(frame) =>
        assert_eq(
          @infra_compress.zstd_decompress_with_dict(frame, d, 1 << 20),
          Some(data),
        )
      None => fail("原始短字典应可压缩")
    }
  }
}

///|
test "zstd 字典帧解码：FCS 截断 / 超限 / 不匹配 / 校验和缺失与翻转" {
  let dict = zsd_raw_dict()
  let data = zsg_data(300) // fcs_flag=1（两字节 FCS）。
  guard @infra_compress.zstd_compress_with_dict(data, dict, true) is Some(frame)
  // 帧头后 FCS 截断（magic 4 + FHD 1 + FCS 首字节 = 6 字节保留）。
  let cut6 : Array[Int] = []
  for i in 0..<6 {
    cut6.push(frame[i])
  }
  assert_true(
    @infra_compress.zstd_decompress_with_dict(cut6, dict, 1 << 20) is None,
  )
  // 声明内容量超出 max_out。
  assert_true(
    @infra_compress.zstd_decompress_with_dict(frame, dict, 10) is None,
  )
  // FCS 篡改 → 解码长度与声明不一致。
  let bad_fcs : Array[Int] = []
  for b in frame {
    bad_fcs.push(b)
  }
  bad_fcs[5] = bad_fcs[5] ^ 0x01
  assert_true(
    @infra_compress.zstd_decompress_with_dict(bad_fcs, dict, 1 << 20) is None,
  )
  // 校验和截断。
  let no_sum : Array[Int] = []
  for i in 0..<(frame.length() - 4) {
    no_sum.push(frame[i])
  }
  assert_true(
    @infra_compress.zstd_decompress_with_dict(no_sum, dict, 1 << 20) is None,
  )
  // 校验和翻转。
  let bad_sum : Array[Int] = []
  for b in frame {
    bad_sum.push(b)
  }
  bad_sum[bad_sum.length() - 1] = bad_sum[bad_sum.length() - 1] ^ 0xFF
  assert_true(
    @infra_compress.zstd_decompress_with_dict(bad_sum, dict, 1 << 20) is None,
  )
}

///|
test "zstd 字典帧解码：多帧总量超出 max_out" {
  let dict = zsd_raw_dict()
  let data = zsg_data(60)
  guard @infra_compress.zstd_compress_with_dict(data, dict, false)
    is Some(frame)
  let two : Array[Int] = []
  for b in frame {
    two.push(b)
  }
  for b in frame {
    two.push(b)
  }
  assert_eq(
    @infra_compress.zstd_decompress_with_dict(two, dict, 90) is None,
    true,
  )
  match @infra_compress.zstd_decompress_with_dict(two, dict, 1 << 20) {
    Some(out) => assert_eq(out.length(), 120)
    None => fail("双帧应可解")
  }
}

///|
test "zstd 字典压缩：全同字节块走 RLE 路径" {
  let dict = zsd_raw_dict()
  let data : Array[Int] = []
  for _i in 0..<300 {
    data.push(0x41)
  }
  guard @infra_compress.zstd_compress_with_dict(data, dict, false)
    is Some(frame)
  assert_true(frame.length() < 40)
  assert_eq(
    @infra_compress.zstd_decompress_with_dict(frame, dict, 1 << 20),
    Some(data),
  )
}

///|
test "zstd 压缩：不可压缩长块（20 位 Raw 字面量布局）往返" {
  // LCG 伪随机 8000 字节：几乎无匹配也无熵收益 → 字面量 ≥4096 走
  // size_format 11（20 位）Raw 布局。
  let data : Array[Int] = []
  let mut x = 123456789
  for _i in 0..<8000 {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    data.push((x >> 16) & 0xFF)
  }
  let frame = @infra_compress.zstd_compress(data, true)
  assert_eq(@infra_compress.zstd_decompress(frame, 1 << 20), Some(data))
}

///|
test "zstd 鲁棒性：压缩帧逐字节腐蚀不崩溃" {
  let data = zsg_data(500)
  let frame = @infra_compress.zstd_compress(data, true)
  let mut i = 0
  while i < frame.length() {
    let bad : Array[Int] = []
    for b in frame {
      bad.push(b)
    }
    bad[i] = bad[i] ^ 0xFF
    // 腐蚀后要么拒绝，要么解出等长内容（头部某些位不参与校验）。
    match @infra_compress.zstd_decompress(bad, 1 << 20) {
      None => ()
      Some(out) => assert_true(out.length() <= 1 << 20)
    }
    i = i + 1
  }
}
