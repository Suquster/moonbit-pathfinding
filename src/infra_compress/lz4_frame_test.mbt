// lz4_frame_test.mbt —— LZ4 帧格式黑盒测试：roundtrip PBT +
// python-lz4 双向黄金对拍 + 畸形输入拒绝。

///|
test "lz4 frame roundtrip：文本 / 空 / 全同 / 跨块" {
  let cases : Array[Array[Int]] = []
  cases.push([])
  let text : Array[Int] = []
  for i in 0..<50 {
    let s = "record \{i % 9}: the quick brown fox jumps over the lazy dog\n"
    for j in 0..<s.length() {
      text.push(s[j].to_int() & 0xFF)
    }
  }
  cases.push(text)
  cases.push(Array::make(70000, 0x41)) // 跨 64KB 块边界。
  for data in cases {
    let frame = lz4_frame_compress(data)
    match lz4_frame_decompress(frame, 1 << 20) {
      None => abort("lz4 frame 解压失败")
      Some(dec) => {
        assert_eq(dec.length(), data.length())
        for k in 0..<data.length() {
          assert_eq(dec[k], data[k])
        }
      }
    }
  }
}

///|
test "lz4 frame roundtrip PBT：150 组结构化随机" {
  let rng = @infra_pbt.rng_new(0x14A4F4A3EUL)
  for _ in 0..<150 {
    let n = rng.next_below(3000)
    let data : Array[Int] = []
    let mut k = 0
    while k < n {
      if rng.next_below(3) == 0 && data.length() >= 8 {
        // 回引一段（制造匹配）。
        let back = 1 + rng.next_below(data.length())
        let run = 4 + rng.next_below(40)
        for _ in 0..<run {
          if data.length() >= n {
            break
          }
          data.push(data[data.length() - back])
          k = k + 1
        }
      } else {
        data.push(rng.next_below(24) + 97)
        k = k + 1
      }
    }
    let frame = lz4_frame_compress(data)
    match lz4_frame_decompress(frame, 1 << 20) {
      None => abort("lz4 frame PBT 解压失败")
      Some(dec) => {
        assert_eq(dec.length(), data.length())
        for j in 0..<data.length() {
          assert_eq(dec[j], data[j])
        }
      }
    }
  }
}

///|
/// python-lz4 生成帧（lz4.frame.compress(b"..."), block_size 默认，
/// content_checksum=True）：本实现须可解。
test "lz4 frame 黄金向量：python-lz4 压缩 → 本实现解压" {
  // lz4.frame.compress(b"hello hello hello hello hello!",
  //                    content_checksum=True, store_size=True)
  let frame : Array[Int] = [
    0x04, 0x22, 0x4D, 0x18, 0x6C, 0x40, 0x1E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x72, 0x10, 0x00, 0x00, 0x00, 0x6F, 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x20,
    0x06, 0x00, 0x00, 0x50, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0x00, 0x00, 0x00, 0x00,
    0x6D, 0x22, 0x3A, 0x74,
  ]
  match lz4_frame_decompress(frame, 1024) {
    None => abort("黄金帧解压失败")
    Some(dec) => {
      let want = "hello hello hello hello hello!"
      assert_eq(dec.length(), want.length())
      for k in 0..<want.length() {
        assert_eq(dec[k], want[k].to_int() & 0xFF)
      }
    }
  }
}

///|
test "lz4 frame 畸形输入拒绝：坏魔数 / 坏 HC / 坏校验 / 截断" {
  let data : Array[Int] = []
  let s = "lz4 frame negative test payload, lz4 frame negative test payload"
  for j in 0..<s.length() {
    data.push(s[j].to_int() & 0xFF)
  }
  let good = lz4_frame_compress(data)
  assert_true(lz4_frame_decompress(good, 1 << 20) is Some(_))
  // 坏魔数。
  let bad1 = good.copy()
  bad1[0] = 0x05
  assert_true(lz4_frame_decompress(bad1, 1 << 20) is None)
  // 坏 HC（描述符校验字节）。
  let bad2 = good.copy()
  bad2[14] = bad2[14] ^ 0xFF
  assert_true(lz4_frame_decompress(bad2, 1 << 20) is None)
  // 坏内容校验（末 4 字节）。
  let bad3 = good.copy()
  bad3[bad3.length() - 1] = bad3[bad3.length() - 1] ^ 0x01
  assert_true(lz4_frame_decompress(bad3, 1 << 20) is None)
  // 截断。
  let bad4 : Array[Int] = []
  for k in 0..<(good.length() - 6) {
    bad4.push(good[k])
  }
  assert_true(lz4_frame_decompress(bad4, 1 << 20) is None)
  // 输出上限。
  assert_true(lz4_frame_decompress(good, 4) is None)
}

///|
/// python-lz4 block-linked 多块帧（block_size=64KB, block_linked=True）：
/// 第二块的 match 回引第一块历史，覆盖 lz4_decompress_into 链接路径。
test "lz4 frame 黄金向量：python-lz4 block-linked 跨块回引" {
  let hexstr = "04224d184c40c6e60100000000001a4b01000060726f7720303b060011310600113206001133060011340600113506001136060011370600113806001139060013313d00023e0012313f000314000121000212000f5100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff81507720303b72f10000000ff9ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff95506f7720353b00000000579bfcbe"
  let data : Array[Int] = []
  fn nib(v : Int) -> Int {
    if v >= 97 {
      v - 87
    } else {
      v - 48
    }
  }

  let mut i = 0
  while i + 1 < hexstr.length() {
    data.push((nib(hexstr[i].to_int()) << 4) | nib(hexstr[i + 1].to_int()))
    i = i + 2
  }
  match lz4_frame_decompress(data, 1 << 21) {
    None => abort("block-linked 黄金帧解压失败")
    Some(dec) => {
      let mut idx = 0
      for r in 0..<20000 {
        let s = "row \{r % 13};"
        for j in 0..<s.length() {
          assert_eq(dec[idx], s[j].to_int() & 0xFF)
          idx = idx + 1
        }
      }
      assert_eq(idx, dec.length())
    }
  }
}
