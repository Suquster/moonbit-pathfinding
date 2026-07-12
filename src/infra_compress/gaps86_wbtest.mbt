// gaps86_wbtest.mbt —— zstd 块尾部字面量输出预算拒绝（第八十六批）。

///|
/// zstd_decode_compressed_block：序列耗尽后尾部剩余字面量超出
/// max_out 预算 → 拒绝；预算恰好足够 → 接受并输出该字面量。
test "zstd 块：尾部剩余字面量超预算拒绝" {
  // Raw 字面量 regen=1（b0=0x08），字面量 'A'，nb_seq=0。
  let blk = [0x08, 0x41, 0x00]
  let out : Array[Int] = []
  // max_out=0：尾部 1 字节字面量超预算 → 拒绝。
  assert_false(
    zstd_decode_compressed_block(
      blk,
      0,
      blk.length(),
      out,
      0,
      0,
      zstd_block_ctx(),
    ),
  )
  // max_out=1：恰好容纳 → 接受。
  let out2 : Array[Int] = []
  assert_true(
    zstd_decode_compressed_block(
      blk,
      0,
      blk.length(),
      out2,
      0,
      1,
      zstd_block_ctx(),
    ),
  )
  assert_true(out2 == [0x41])
}

///|
/// 含序列块：序列执行完毕后，尾部剩余字面量使输出超出 max_out
/// 预算 → 拒绝；完整预算 → 往返一致。
test "zstd 块：序列后尾部字面量超预算拒绝" {
  // 构造有重复段 + 尾部独立字面量的输入，编码出含序列的块。
  let src : Array[Int] = []
  for _r in 0..<6 {
    for b in [0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68] {
      src.push(b)
    }
  }
  src.push(0x5A) // 尾部字面量 'Z'
  guard zstd_encode_block(src, 0, src.length(), [1, 4, 8]) is Some(blk)
  // 完整预算：往返一致。
  let ok : Array[Int] = []
  assert_true(
    zstd_decode_compressed_block(
      blk,
      0,
      blk.length(),
      ok,
      0,
      src.length(),
      zstd_block_ctx(),
    ),
  )
  assert_true(ok == src)
  // 预算差 1 字节：序列全部执行成功，尾部字面量超预算 → 拒绝。
  let bad : Array[Int] = []
  assert_false(
    zstd_decode_compressed_block(
      blk,
      0,
      blk.length(),
      bad,
      0,
      src.length() - 1,
      zstd_block_ctx(),
    ),
  )
}
