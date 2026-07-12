// 白盒测试：覆盖率审计收口（INFRA 第六十八批）——
// 大字面量（size_format 11，regen ≥ 4096）编码往返与输出预算超限拒绝。

///|
fn zg3_prng_bytes(n : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut s = 0x12345678UL
  for _i in 0..<n {
    s = s * 6364136223846793005UL + 1442695040888963407UL
    out.push(((s >> 33) & 0xFFUL).to_int())
  }
  out
}

///|
test "zstd_compress_entropy：regen ≥ 4096 大字面量往返一致" {
  let data = zg3_prng_bytes(5000)
  let enc = zstd_compress_entropy(data, false)
  guard zstd_decompress(enc, 1 << 20) is Some(dec)
  assert_true(dec == data)
}

///|
test "zstd_decompress：输出超过 max_out 预算即拒绝" {
  let data = zg3_prng_bytes(600)
  let enc = zstd_compress(data, false)
  assert_true(zstd_decompress(enc, 100) is None)
  guard zstd_decompress(enc, 600) is Some(dec)
  assert_true(dec == data)
}
