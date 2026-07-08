// streaming_test.mbt —— 流式哈希 API 对拍一次性函数。

///|
fn bytes_of(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s {
    out.push(c.to_int() & 0xFF)
  }
  out
}

///|
test "sha256 streaming matches one-shot" {
  let h = @infra_hash.Sha256Hasher::new()
  h.update(bytes_of("abc"))
  assert_eq(h.finalize(), @infra_hash.sha256(bytes_of("abc")))
}

///|
test "sha256 streaming supports reset" {
  let h = @infra_hash.Sha256Hasher::new()
  h.update(bytes_of("hello"))
  assert_eq(h.finalize(), @infra_hash.sha256(bytes_of("hello")))
  h.reset()
  h.update(bytes_of("world"))
  assert_eq(h.finalize(), @infra_hash.sha256(bytes_of("world")))
}

///|
test "crc32 streaming matches one-shot" {
  let c = @infra_hash.Crc32Hasher::new()
  c.update(bytes_of("123"))
  c.update(bytes_of("456789"))
  assert_eq(c.finalize(), @infra_hash.crc32(bytes_of("123456789")))
}

///|
test "xxhash64 streaming matches one-shot" {
  let h = @infra_hash.XxHash64Hasher::new(0UL)
  h.update(bytes_of("xxhash streaming"))
  assert_eq(
    h.finalize(),
    @infra_hash.xxhash64(bytes_of("xxhash streaming"), 0UL),
  )
}
