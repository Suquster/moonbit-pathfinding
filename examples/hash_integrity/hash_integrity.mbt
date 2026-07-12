// examples/hash_integrity — runnable demonstration of the `src/infra_hash`
// direction as a realistic artifact-integrity workflow: digest a release
// artifact with the SHA-2 / SHA-3 / BLAKE2b families, authenticate it with
// HMAC, derive session keys via HKDF, stretch a password via PBKDF2,
// checksum streams incrementally, and pick fast non-crypto hashes for
// hash-table sharding.
//
// Run with:
//   moon run examples/hash_integrity

///|
fn main {
  let artifact = "moonbit-pathfinding-v0.1.0.tar"
  println("=== 1. release artifact digests (hex) ===")
  println("sha256  : \{@hash.sha256_hex(artifact)}")
  println("sha512  : \{@hash.sha512_hex(artifact)}")
  println("sha3-256: \{@hash.sha3_256_hex(artifact)}")
  println("blake2b : \{@hash.blake2b_hex(artifact)}")
  println("md5     : \{@hash.md5_hex(artifact)} (legacy, display only)")
  println("")
  println("=== 2. HMAC authentication of a manifest ===")
  let key = @hash.utf8_bytes("release-signing-key")
  let manifest = @hash.utf8_bytes("name=pathfinding;version=0.1.0")
  let tag = @hash.hmac_sha256(key, manifest)
  println("hmac-sha256: \{@hash.digest_hex(tag)}")
  let tampered = @hash.utf8_bytes("name=pathfinding;version=9.9.9")
  let tag2 = @hash.hmac_sha256(key, tampered)
  println("tamper detected (tags differ): \{tag != tag2}")
  println("")
  println("=== 3. HKDF session keys from a shared secret ===")
  let ikm = @hash.utf8_bytes("shared-ecdh-secret")
  let salt = @hash.utf8_bytes("handshake-salt")
  let info = @hash.utf8_bytes("session-encryption")
  match @hash.hkdf(ikm, salt, info, 32) {
    Some(okm) => println("hkdf-sha256 (32B): \{@hash.digest_hex(okm)}")
    None => println("hkdf failed")
  }
  println("")
  println("=== 4. PBKDF2 password stretching ===")
  let pw = @hash.utf8_bytes("correct horse battery staple")
  let pw_salt = @hash.utf8_bytes("per-user-salt")
  match @hash.pbkdf2_hmac_sha256(pw, pw_salt, 1000, 32) {
    Some(dk) => println("pbkdf2 (1000 iters, 32B): \{@hash.digest_hex(dk)}")
    None => println("pbkdf2 failed")
  }
  println("")
  println("=== 5. streaming checksum equals one-shot ===")
  let whole = @hash.utf8_bytes("chunk-a|chunk-b|chunk-c")
  let one_shot = @hash.crc32(whole)
  let h = @hash.Crc32Hasher::new()
  h.update(@hash.utf8_bytes("chunk-a|"))
  h.update(@hash.utf8_bytes("chunk-b|"))
  h.update(@hash.utf8_bytes("chunk-c"))
  let streamed = h.finalize()
  println("crc32 one-shot : \{one_shot}")
  println("crc32 streamed : \{streamed} (equal: \{one_shot == streamed})")
  let sh = @hash.Sha256Hasher::new()
  sh.update(@hash.utf8_bytes("chunk-a|chunk-b|"))
  sh.update(@hash.utf8_bytes("chunk-c"))
  let sha_stream = sh.finalize()
  println("sha256 streamed == one-shot: \{sha_stream == @hash.sha256(whole)}")
  println("")
  println("=== 6. fast non-crypto hashes for sharding ===")
  let keys = ["user-1", "user-2", "user-3", "user-4"]
  for k in keys {
    let b = @hash.utf8_bytes(k)
    let shard = (@hash.xxhash64(b, 42) % 3UL).to_int()
    println(
      "\{k}: xxh64 shard #\{shard}, fnv1a=\{@hash.fnv1a_32(b)}, murmur3=\{@hash.murmur3_32(b, 0)}",
    )
  }
}
