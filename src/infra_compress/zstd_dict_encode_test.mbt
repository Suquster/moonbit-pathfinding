// zstd_dict_encode_test.mbt —— zstd 字典压缩侧（RFC 8878 §5，INFRA
// 第五十九批）：原始/结构化字典往返、Dictionary_ID 帧头、校验和、
// 字典收益与畸形字典拒绝。

///|
fn zsd_text(n : Int) -> Array[Int] {
  // 与 zsd_raw_dict 高度重叠的报文：字典回引应显著缩短产物。
  let phrase : Array[Int] = []
  for c in "hello world hello dictionary content says hello world ".iter() {
    phrase.push(c.to_int() & 0xFF)
  }
  let out : Array[Int] = []
  let mut i = 0
  while out.length() < n {
    out.push(phrase[i % phrase.length()])
    i = i + 1
  }
  out
}

///|
test "zstd 字典压缩：原始内容字典往返" {
  let dict = zsd_raw_dict()
  for size in [0, 1, 5, 100, 500, 3000] {
    let data = zsd_text(size)
    match @infra_compress.zstd_compress_with_dict(data, dict, false) {
      Some(frame) =>
        assert_eq(
          @infra_compress.zstd_decompress_with_dict(frame, dict, 1 << 20),
          Some(data),
        )
      None => fail("原始字典压缩失败 size=\{size}")
    }
  }
}

///|
test "zstd 字典压缩：结构化字典往返（Dictionary_ID + 初始 rep）" {
  let dict = zsd_dict()
  let data : Array[Int] = []
  for _r in 0..<8 {
    for c in "the quick brown fox jumps over the lazy dog 26 extra".iter() {
      data.push(c.to_int() & 0xFF)
    }
  }
  match @infra_compress.zstd_compress_with_dict(data, dict, true) {
    Some(frame) => {
      assert_eq(
        @infra_compress.zstd_decompress_with_dict(frame, dict, 1 << 20),
        Some(data),
      )
      // 帧头声明了 Dictionary_ID：换一个 id 不同的字典应拒绝。
      assert_true(
        @infra_compress.zstd_decompress_with_dict(
          frame,
          zsd_raw_dict(),
          1 << 20,
        )
        is None,
      )
    }
    None => fail("结构化字典压缩失败")
  }
}

///|
test "zstd 字典压缩：字典回引带来净收益" {
  let dict = zsd_raw_dict()
  let data = zsd_text(400)
  match @infra_compress.zstd_compress_with_dict(data, dict, false) {
    Some(with_dict) => {
      let without = @infra_compress.zstd_compress_entropy(data, false)
      assert_true(with_dict.length() <= without.length())
      assert_true(with_dict.length() < data.length())
    }
    None => fail("字典压缩失败")
  }
}

///|
test "zstd 字典压缩：带校验和往返与畸形字典拒绝" {
  let dict = zsd_raw_dict()
  let data = zsd_text(257) // fcs_flag=1 分支。
  match @infra_compress.zstd_compress_with_dict(data, dict, true) {
    Some(frame) =>
      assert_eq(
        @infra_compress.zstd_decompress_with_dict(frame, dict, 1 << 20),
        Some(data),
      )
    None => fail("带校验和字典压缩失败")
  }
  // 结构化 magic 但头部截断的畸形字典 → None。
  let bad : Array[Int] = [0x37, 0xA4, 0x30, 0xEC, 0x01]
  assert_true(@infra_compress.zstd_compress_with_dict(data, bad, false) is None)
}

///|
test "zstd 字典压缩：大输入跨块历史累积往返" {
  let dict = zsd_raw_dict()
  let data = zsd_text(70000) // 跨 64KB 块边界。
  match @infra_compress.zstd_compress_with_dict(data, dict, true) {
    Some(frame) =>
      assert_eq(
        @infra_compress.zstd_decompress_with_dict(frame, dict, 1 << 20),
        Some(data),
      )
    None => fail("跨块字典压缩失败")
  }
}
