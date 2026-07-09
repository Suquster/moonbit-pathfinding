// zstd_block_gaps_wbtest.mbt —— zstd Compressed 块解码器防御分支白盒收口
// （INFRA 第十六批）。每个 return false / None 拒绝分支给出确定性畸形输入。

///|
test "zstd huf_build_table：表深超限 / 剩余量非 2 的幂 / 末权重补位" {
  // 两个权重 12 → total=4096 → tableLog=13 > 11 拒绝。
  assert_true(huf_build_table([12, 12]) is None)
  // total=5 → rest=3 非 2 的幂拒绝。
  assert_true(huf_build_table([2, 1, 1, 1]) is None)
  // 末权重 2 > 显式最大权重 1（last_w > max_w 分支）仍可建表。
  assert_true(huf_build_table([1, 1]) is Some(_))
}

///|
test "zstd huf_read_weights：空区间 / 直存截断 / FSE 头截断" {
  // start >= end。
  assert_true(huf_read_weights([], 0, 0) is None)
  // 直存：header=130 → 3 个权重需 2 字节，仅 1 字节可用。
  assert_true(huf_read_weights([0x82, 0x11], 0, 2) is None)
  // 直存合法：header=129 → 2 个权重 (1,1)。
  assert_true(huf_read_weights([0x81, 0x11], 0, 2) is Some(([1, 1], 2)))
  // FSE 压缩：comp_size=5 超出区间。
  assert_true(huf_read_weights([0x05, 0x00], 0, 2) is None)
  // FSE 压缩：计数表本身损坏（精度头后位流耗尽）。
  assert_true(huf_read_weights([0x01, 0x00], 0, 2) is None)
}

///|
test "zstd huf_decode_stream：位流非法即拒绝" {
  guard huf_build_table([1, 1]) is Some(table)
  let out : Array[Int] = []
  // 末字节为 0 → zstd_bit_reader 拒绝。
  assert_false(huf_decode_stream(table, [0x00], 0, 1, 1, out))
}

///|
test "zstd ll/ml 码表：越界码拒绝、边界码给出基线" {
  assert_true(zstd_ll_code(-1) is None)
  assert_true(zstd_ll_code(36) is None)
  assert_true(zstd_ll_code(35) is Some((65536, 16)))
  assert_true(zstd_ml_code(-1) is None)
  assert_true(zstd_ml_code(53) is None)
  assert_true(zstd_ml_code(52) is Some((65539, 16)))
}

///|
test "zstd_seq_table：四模式的拒绝与接受" {
  // Predefined：默认分布建表成功，位置不动。
  assert_true(
    zstd_seq_table([], 0, 0, 0, zstd_ll_default(), 6, 35, 9, None) is Some(_),
  )
  // RLE：区间耗尽 / 符号越界 / 合法。
  assert_true(
    zstd_seq_table([], 0, 0, 1, zstd_ll_default(), 6, 35, 9, None) is None,
  )
  assert_true(
    zstd_seq_table([40], 0, 1, 1, zstd_ll_default(), 6, 35, 9, None) is None,
  )
  assert_true(
    zstd_seq_table([7], 0, 1, 1, zstd_ll_default(), 6, 35, 9, None) is Some(_),
  )
  // FSE_Compressed：计数表截断。
  assert_true(
    zstd_seq_table([0x00], 0, 1, 2, zstd_ll_default(), 6, 35, 9, None) is None,
  )
  // Repeat：无历史表拒绝，有历史表沿用。
  assert_true(
    zstd_seq_table([], 0, 0, 3, zstd_ll_default(), 6, 35, 9, None) is None,
  )
  guard fse_build_table(zstd_ll_default(), 6) is Some(prev)
  assert_true(
    zstd_seq_table([], 0, 0, 3, zstd_ll_default(), 6, 35, 9, Some(prev))
    is Some(_),
  )
}

///|
/// 便捷断言：畸形 Compressed 块必须被拒绝（独立新建上下文）。
fn zb_must_reject(data : Array[Int]) -> Bool {
  let out : Array[Int] = []
  !zstd_decode_compressed_block(
    data,
    0,
    data.length(),
    out,
    0,
    1 << 20,
    zstd_block_ctx(),
  )
}

///|
test "zstd 块：字面量段截断与越界拒绝" {
  // 块本身过短。
  assert_true(zb_must_reject([0x00]))
  // Raw 字面量 size_format=3：3 字节头截断。
  assert_true(zb_must_reject([0x0C, 0x00]))
  // Raw 字面量：声称 5 字节但区间不足。
  assert_true(zb_must_reject([40, 0x00]))
  // RLE 字面量 size_format=1：重复字节缺失。
  assert_true(zb_must_reject([0x05, 0x00]))
  // Compressed 字面量：3/4/5 字节头逐级截断。
  assert_true(zb_must_reject([0x02, 0x00]))
  assert_true(zb_must_reject([0x0A, 0x00]))
  assert_true(zb_must_reject([0x0E, 0x00]))
  // 5 字节头读出 comp=0 → 权重区间空拒绝。
  assert_true(zb_must_reject([0x0E, 0x00, 0x00, 0x00, 0x00, 0x00]))
  // comp 超出块尾。
  assert_true(zb_must_reject([0x02, 0x00, 0xFF, 0x00]))
  // Treeless 无历史 Huffman 表。
  assert_true(zb_must_reject([0x03, 0x00, 0x00]))
}

///|
test "zstd 块：Huffman 字面量流结构拒绝" {
  // 四流（size_format=1）：权重后不足 6 字节流长表。
  // v = 6 | (0<<4) | (2<<14)；权重直存 [1,1]。
  assert_true(zb_must_reject([0x06, 0x80, 0x00, 0x81, 0x11]))
  // 四流：s1=s2=s3=0 → s4<=0 拒绝（comp=8）。
  assert_true(zb_must_reject([0x06, 0x00, 0x02, 0x81, 0x11, 0, 0, 0, 0, 0, 0]))
  // 四流：regen=1 → c4<0 拒绝（comp=9，s4=1）。
  assert_true(
    zb_must_reject([0x06, 0x40, 0x02, 0x81, 0x11, 0, 0, 0, 0, 0, 0, 0x01]),
  )
  // 四流：首流末字节为 0 → 位流拒绝（regen=4, comp=10, s1=1）。
  assert_true(
    zb_must_reject([0x06, 0x80, 0x02, 0x81, 0x11, 1, 0, 0, 0, 0, 0, 0x00, 0x00]),
  )
  // 单流（size_format=0）：流末字节为 0 → 位流拒绝（regen=1, comp=3）。
  assert_true(zb_must_reject([0x02, 0xC0, 0x00, 0x81, 0x11, 0x00]))
}

///|
test "zstd 块：序列段结构拒绝与纯字面量块" {
  // 序列头缺失（字面量后即块尾）。
  assert_true(zb_must_reject([0x04, 0x00]))
  // 双字节序列数截断。
  assert_true(zb_must_reject([0x00, 0x80]))
  // 三字节序列数截断。
  assert_true(zb_must_reject([0x00, 0xFF, 0x00]))
  // nb_seq=0 但块尾有多余字节。
  assert_true(zb_must_reject([0x00, 0x00, 0x09]))
  // nb_seq=0 纯字面量块成功。
  let out : Array[Int] = []
  assert_true(
    zstd_decode_compressed_block(
      [0x00, 0x00],
      0,
      2,
      out,
      0,
      16,
      zstd_block_ctx(),
    ),
  )
  assert_true(out.length() == 0)
  // 模式字节缺失。
  assert_true(zb_must_reject([0x00, 0x01]))
  // 模式字节保留位非 0。
  assert_true(zb_must_reject([0x00, 0x01, 0x01]))
  // LL / OF / ML 的 Repeat 模式均无历史表。
  assert_true(zb_must_reject([0x00, 0x01, 0xC0]))
  assert_true(zb_must_reject([0x00, 0x01, 0x30]))
  assert_true(zb_must_reject([0x00, 0x01, 0x0C]))
  // 三表就绪但交织位流缺失。
  assert_true(zb_must_reject([0x00, 0x01, 0x00]))
  // 位流存在但不足以初始化三个状态（LL6+OF5+ML6=17 位 > 7 位）。
  assert_true(zb_must_reject([0x00, 0x01, 0x00, 0x80]))
  // 纯字面量块（带内容）成功。
  let out : Array[Int] = []
  assert_true(
    zstd_decode_compressed_block(
      [0x08, 0x41, 0x00],
      0,
      3,
      out,
      0,
      16,
      zstd_block_ctx(),
    ),
  )
  assert_true(out == [0x41])
}

///|
test "zstd 块：权重合法但建表失败与重复偏移下溢拒绝" {
  // 直存权重 [13] 越界 → huf_build_table 拒绝（Compressed 字面量路径）。
  assert_true(zb_must_reject([0x02, 0x80, 0x00, 0x80, 0xD0]))
  // 三表全 RLE：首序列 ll=0 且 of_value=3 → offset=rep0-1=0 下溢拒绝。
  assert_true(zb_must_reject([0x00, 0x01, 0x54, 0x00, 0x01, 0x00, 0x03]))
}
