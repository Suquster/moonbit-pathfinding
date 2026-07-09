// zstd_gaps2_wbtest.mbt —— zstd 解码/编码深层防御分支收口
// （INFRA 第二十三批）：FSE 计数表逐分支畸形流、HUF 权重段
// FSE 位流异常、编码侧 Huffman/归一化退化输入。

///|
test "fse_read_ncount：repeat-zero 标志链截断拒绝" {
  // al=5，首符号 prob=0（low=1），随后三组 '11' 标志后位流耗尽。
  // 位流：0000(al) 10000(low=1) 111111 1 → 字节 0x10, 0x7E。
  assert_true(fse_read_ncount([0x10, 0x7E], 0, 2, 255, 9) is None)
}

///|
test "fse_read_ncount：零串越过 max_symbol 拒绝" {
  // max_symbol=2：首符号 prob=0 后标志 3（'11'）连推零越界。
  assert_true(fse_read_ncount([0x10, 0x06], 0, 2, 2, 9) is None)
}

///|
test "fse_read_ncount：零串收尾越界 break 后摆表未归零拒绝" {
  // max_symbol=2：标志 2（'01' 低位序 → 位 0,1）推 2 个零后
  // norm 长度 3 > 2 → break → remaining≠1 → None。
  assert_true(fse_read_ncount([0x10, 0x04], 0, 2, 2, 9) is None)
}

///|
test "fse_read_ncount：满位补读最高位截断拒绝" {
  // al=5；sym0 low=18（prob 17）、sym1 low=9（prob 8）收缩后
  // sym2 low=7 ≥ max=7 需补读最高位，此时位流恰好耗尽。
  assert_true(fse_read_ncount([0x20, 0xF3], 0, 2, 255, 9) is None)
}

///|
test "huf_read_weights：FSE 权重位流为空拒绝" {
  // ncount（[32] al=5）恰好消费全部 2 字节 → 位流长度 0。
  assert_true(huf_read_weights([2, 0xF0, 0x03], 0, 3) is None)
}

///|
test "huf_read_weights：FSE 初始状态位不足拒绝" {
  // 位流仅 1 字节（哨兵后 0 位可用）< 2×al=10 位。
  assert_true(huf_read_weights([3, 0xF0, 0x03, 0x01], 0, 4) is None)
}

///|
test "huf_read_weights：255 权重仍未耗尽拒绝" {
  // 单符号表（nb_bits=0）永不消费位 → 推满 255 个权重后判损坏。
  assert_true(huf_read_weights([5, 0xF0, 0x03, 0xFF, 0xFF, 0x01], 0, 6) is None)
}

///|
test "zstd_ll/ml 编码：全档位基数单调覆盖" {
  // 走满编码档位查表路径（16..35 / 32..52 全部命中 Some 分支）。
  let mut prev_ll = -1
  for ll in [16, 18, 20, 24, 32, 48, 64, 128, 1024, 65536] {
    let (code, bits, extra) = zstd_ll_encode(ll)
    assert_true(code >= 16 && code <= 35)
    assert_true(bits >= 0 && extra >= 0)
    assert_true(code >= prev_ll)
    prev_ll = code
  }
  let mut prev_ml = -1
  for ml in [35, 37, 43, 67, 131, 259, 515, 1027, 4099, 65539] {
    let (code, bits, extra) = zstd_ml_encode(ml)
    assert_true(code >= 32 && code <= 52)
    assert_true(bits >= 0 && extra >= 0)
    assert_true(code >= prev_ml)
    prev_ml = code
  }
}

///|
test "huf_lengths：符号不足 / 超出档位容量拒绝" {
  assert_true(huf_lengths([0, 7], 11) is None) // 仅 1 个活跃符号
  assert_true(huf_lengths([1, 1, 1, 1, 1], 2) is None) // 5 > 2^2
}

///|
test "huf_encode_literals：单一符号无法建 Huffman 拒绝" {
  let lits : Array[Int] = Array::make(32, 0x41)
  assert_true(huf_encode_literals(lits) is None)
}

///|
test "fse_normalize：单一符号 / 削峰失败拒绝" {
  assert_true(fse_normalize([5], 9) is None) // distinct < 2
  // ts=4：四个 -1（less-than-one）+ scaled 2 → used 6 > 4，
  // 削峰仅能扣 1 后无 >1 项 → None。
  assert_true(fse_normalize([1, 1, 1, 1, 4], 2) is None)
}

///|
test "fse_normalize：削峰成功恰好归零" {
  // ts=4：两个 -1 + 2 + 2 → used 6 → 削峰两次 → [-1,-1,1,1]。
  match fse_normalize([1, 1, 4, 4], 2) {
    Some(norm) => {
      assert_eq(norm[0], -1)
      assert_eq(norm[1], -1)
      assert_eq(norm[2], 1)
      assert_eq(norm[3], 1)
    }
    None => assert_true(false)
  }
}

///|
test "fse_write_ncount：末尾零串收尾 break" {
  // norm=[1,0,0]：零串写完后 s 越过末尾 → break，输出非空。
  let out = fse_write_ncount([1, 0, 0], 5)
  assert_true(out.length() > 0)
}

///|
test "huf_encode_literals：18+18 位段头（size_format 11）" {
  // regen=20000 > 16383 且 7 符号分布可压 → 走 5 字节段头。
  let lits : Array[Int] = []
  for i in 0..<20000 {
    lits.push(i % 7)
  }
  match huf_encode_literals(lits) {
    Some(out) => {
      let b0 = out[0]
      assert_eq(b0 & 3, 2) // Compressed 字面量
      assert_eq((b0 >> 2) & 3, 3) // size_format 11
    }
    None => assert_true(false)
  }
}

///|
/// 构造仅含 Huffman 四流字面量段 + nb_seq=0 的最小压缩块。
fn zstd_four_stream_block() -> Array[Int] {
  let lits : Array[Int] = []
  for i in 0..<64 {
    lits.push(i % 3)
  }
  match huf_encode_literals(lits) {
    Some(sec) => {
      let block = sec.copy()
      block.push(0x00) // nb_seq = 0
      block
    }
    None => []
  }
}

///|
test "zstd_decode_compressed_block：四流字面量各流损坏逐一拒绝" {
  let block = zstd_four_stream_block()
  assert_true(block.length() > 12)
  // 完整块可解出 64 个字面量。
  let out : Array[Int] = []
  assert_true(
    zstd_decode_compressed_block(
      block,
      0,
      block.length(),
      out,
      0,
      128,
      zstd_block_ctx(),
    ),
  )
  assert_eq(out.length(), 64)
  // 段头 3 字节 + 权重 2 字节 → 跳表在 5..11，流区自 11 起。
  let s1 = (block[5] & 0xFF) | ((block[6] & 0xFF) << 8)
  let s2 = (block[7] & 0xFF) | ((block[8] & 0xFF) << 8)
  let s3 = (block[9] & 0xFF) | ((block[10] & 0xFF) << 8)
  // 依次破坏流 2/3/4 的末字节（哨兵置零 → 位读取器拒绝）。
  for cut in [11 + s1 + s2 - 1, 11 + s1 + s2 + s3 - 1, block.length() - 2] {
    let bad = block.copy()
    bad[cut] = 0
    assert_false(
      zstd_decode_compressed_block(
        bad,
        0,
        bad.length(),
        [],
        0,
        128,
        zstd_block_ctx(),
      ),
    )
  }
}

///|
test "zstd_decode_compressed_block：regen 过小致第 4 流长度为负拒绝" {
  let block = zstd_four_stream_block()
  // 段头改写 regen=1（size_format 01 保持不变，comp 位段不动）。
  let comp = ((block[1] & 0xFF) >> 6) | ((block[2] & 0xFF) << 2) // 原 comp（位 14..24 中低 10 位）
  let v = 2 | (1 << 2) | (1 << 4) | (comp << 14)
  block[0] = v & 0xFF
  block[1] = (v >> 8) & 0xFF
  block[2] = (v >> 16) & 0xFF
  assert_false(
    zstd_decode_compressed_block(
      block,
      0,
      block.length(),
      [],
      0,
      128,
      zstd_block_ctx(),
    ),
  )
}

///|
test "zstd_decompress：输出上限逐级收紧拒绝" {
  // 重复段 + 唯一尾部字面量：max_out 低于实际长度时各级守卫拒绝。
  let data : Array[Int] = []
  for i in 0..<48 {
    data.push([0x61, 0x62, 0x63, 0x64][i % 4])
  }
  for i in 0..<10 {
    data.push(0x50 + i)
  }
  let comp = zstd_compress(data, false)
  assert_true(zstd_decompress(comp, data.length()) == Some(data))
  assert_true(zstd_decompress(comp, data.length() - 1) is None)
  assert_true(zstd_decompress(comp, 4) is None)
}

///|
test "huf_encode_literals：单流超 65535 字节拒绝" {
  // 320000 个 127 值均匀分布 → 每流 ≈ 70000 字节 > 65535。
  let lits : Array[Int] = []
  for i in 0..<320000 {
    lits.push(i % 127)
  }
  assert_true(huf_encode_literals(lits) is None)
}
