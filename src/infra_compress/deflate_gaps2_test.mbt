// 黑盒测试：覆盖率审计收口（INFRA 第七十八批）——
// 预置字典解压对畸形输入的拒绝与 zlib 头 CM 校验。

///|
test "inflate_preset：畸形 deflate 流返回 None" {
  assert_true(
    @infra_compress.inflate_preset([0xFF, 0xFF, 0xFF], [1, 2]) is None,
  )
}

///|
test "zlib_decompress：CM 非 deflate 拒绝" {
  assert_true(@infra_compress.zlib_decompress([0x77, 0x9C, 0, 0, 0, 1]) is None)
}
