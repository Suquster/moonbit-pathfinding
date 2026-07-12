// infra_hash_bench.mbt —— 哈希方向基准：SHA-256 加密摘要 vs
// xxHash64 / FNV-1a / CRC32 快速哈希在同一确定性负载上的吞吐对比，
// 以及流式分块与一次性摘要的等价校验。

///|
fn hb_payload(n : Int, seed : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut s = seed
  for _ in 0..<n {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    out.push(s % 256)
  }
  out
}

///|
test "smoke: digests agree between streaming and one-shot" {
  let data = hb_payload(4096, 20260712)
  let one = @hash.sha256(data)
  let head : Array[Int] = []
  let tail : Array[Int] = []
  for i in 0..<4096 {
    if i < 2048 {
      head.push(data[i])
    } else {
      tail.push(data[i])
    }
  }
  let h = @hash.Sha256Hasher::new()
  h.update(head)
  h.update(tail)
  assert_eq(@hash.digest_hex(h.finalize()), @hash.digest_hex(one))
  let c = @hash.Crc32Hasher::new()
  c.update(data)
  assert_eq(c.finalize(), @hash.crc32(data))
}

///|
test "bench: crypto digest vs fast non-crypto hashes" (b : @bench.T) {
  for n in [1024, 16384] {
    let data = hb_payload(n, 20260712)
    b.bench(name="sha256_\{n}", fn() { b.keep(@hash.sha256(data)) })
    b.bench(name="sha3_256_\{n}", fn() { b.keep(@hash.sha3_256(data)) })
    b.bench(name="blake2b_\{n}", fn() { b.keep(@hash.blake2b(data)) })
    b.bench(name="xxhash64_\{n}", fn() { b.keep(@hash.xxhash64(data, 42)) })
    b.bench(name="fnv1a_64_\{n}", fn() { b.keep(@hash.fnv1a_64(data)) })
    b.bench(name="crc32_\{n}", fn() { b.keep(@hash.crc32(data)) })
  }
}
