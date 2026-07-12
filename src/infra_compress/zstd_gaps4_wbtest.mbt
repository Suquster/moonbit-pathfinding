// 白盒测试：覆盖率审计收口（INFRA 第七十四批）——
// 多帧串联解码：全量往返与跨帧累计预算超限拒绝。

///|
fn zg4_bytes(n : Int, seed : UInt64) -> Array[Int] {
  let out : Array[Int] = []
  let mut s = seed
  for _i in 0..<n {
    s = s * 6364136223846793005UL + 1442695040888963407UL
    out.push(((s >> 33) & 0xFFUL).to_int())
  }
  out
}

///|
test "zstd_decompress：两帧串联全量往返一致" {
  let a = zg4_bytes(500, 1UL)
  let b = zg4_bytes(400, 2UL)
  let enc : Array[Int] = []
  for x in zstd_compress(a, false) {
    enc.push(x)
  }
  for x in zstd_compress(b, false) {
    enc.push(x)
  }
  guard zstd_decompress(enc, 1 << 20) is Some(dec)
  let expect : Array[Int] = []
  for x in a {
    expect.push(x)
  }
  for x in b {
    expect.push(x)
  }
  assert_true(dec == expect)
}

///|
test "zstd_decompress：跨帧累计输出超预算拒绝" {
  let a = zg4_bytes(500, 3UL)
  let b = zg4_bytes(400, 4UL)
  let enc : Array[Int] = []
  for x in zstd_compress(a, false) {
    enc.push(x)
  }
  for x in zstd_compress(b, false) {
    enc.push(x)
  }
  assert_true(zstd_decompress(enc, 600) is None)
}
