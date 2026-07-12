// infra_compress_bench.mbt —— 压缩方向基准：DEFLATE / zstd(entropy) /
// LZ4 在重复性日志负载上的压缩 + 解压 round-trip 吞吐对比，
// smoke 校验三者均无损。

///|
fn cb_log_payload(lines : Int) -> Array[Int] {
  let sb = StringBuilder::new()
  for i in 0..<lines {
    sb.write_string(
      "2026-07-12T18:0\{i % 10}:0\{i % 6}Z INFO handled path=/api/v\{i % 3}/route status=200 rt=\{i % 40}ms\n",
    )
  }
  @codec.utf8_bytes_of_string(sb.to_string())
}

///|
test "smoke: all codecs round-trip losslessly" {
  let data = cb_log_payload(64)
  let n = data.length()
  assert_true(@compress.inflate(@compress.deflate(data)) == Some(data))
  assert_true(
    @compress.zstd_decompress(@compress.zstd_compress_entropy(data, true), n) ==
    Some(data),
  )
  assert_true(
    @compress.lz4_decompress(@compress.lz4_compress(data), n) == Some(data),
  )
}

///|
test "bench: compress + decompress round-trip throughput" (b : @bench.T) {
  for lines in [64, 512] {
    let data = cb_log_payload(lines)
    let n = data.length()
    b.bench(name="deflate_roundtrip_\{n}B", fn() {
      let c = @compress.deflate(data)
      b.keep(@compress.inflate(c))
    })
    b.bench(name="zstd_roundtrip_\{n}B", fn() {
      let c = @compress.zstd_compress_entropy(data, false)
      b.keep(@compress.zstd_decompress(c, n))
    })
    b.bench(name="lz4_roundtrip_\{n}B", fn() {
      let c = @compress.lz4_compress(data)
      b.keep(@compress.lz4_decompress(c, n))
    })
  }
}
