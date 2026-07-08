// 白盒测试：infra_compress 解码器内部防御分支（Huffman 建表拒绝、
// 位流耗尽、zstd FSE/HUF 计数表损坏、bit reader 边界）。

///|
test "deflate huff_build：非法码长 / 空表 / 过订阅均拒绝" {
  assert_true(huff_build([16]) is None) // 码长越界
  assert_true(huff_build([0, 0, 0]) is None) // 没有任何符号
  assert_true(huff_build([1, 1, 1]) is None) // Kraft 过订阅
}

///|
test "deflate huff_decode：位流耗尽返回 -1" {
  guard huff_build([1, 1]) is Some(table)
  let br = BitReader::new([])
  assert_eq(huff_decode(br, table), -1)
}

///|
test "deflate inflate_dynamic_tables：位流截断与超界计数拒绝" {
  // 空位流：HLIT/HDIST/HCLEN 读取即失败。
  assert_true(inflate_dynamic_tables(BitReader::new([])) is None)
  // HLIT=31 → nlit=288 > 286：拒绝。
  assert_true(inflate_dynamic_tables(BitReader::new([0xFF, 0xFF])) is None)
}

///|
test "zstd_bit_reader：空长度与末字节为零拒绝" {
  assert_true(zstd_bit_reader([0x01], 0, 0) is None)
  assert_true(zstd_bit_reader([0x00], 0, 1) is None)
}

///|
test "zstd fse_build_table：计数总和与表长不符（摆表未归零）拒绝" {
  // accuracy_log=2 → 表长 4；-1 占 1 槽 + 4 个常规 → 总和 5 ≠ 4。
  assert_true(fse_build_table([-1, 4], 2) is None)
}

///|
test "zstd fse_read_ncount：空区间与截断位流拒绝" {
  assert_true(fse_read_ncount([], 0, 0, 10, 9) is None)
  // 只有 4 位精度头之后即耗尽。
  assert_true(fse_read_ncount([0x00], 0, 1, 10, 9) is None)
}

///|
test "zstd huf_build_table：权重越界与全零权重拒绝" {
  assert_true(huf_build_table([13]) is None)
  assert_true(huf_build_table([0, 0]) is None)
}
