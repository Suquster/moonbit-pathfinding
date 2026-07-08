// streaming.mbt —— 流式增量哈希 API（Go `hash.Hash` / zlib 可续算语义）。

///|
/// SHA-256 流式哈希器：多次 update，finalize 与一次性 `sha256` 一致。
pub struct Sha256Hasher {
  data : Array[Int]
}

///|
/// Create an empty SHA-256 stream.
pub fn Sha256Hasher::new() -> Sha256Hasher {
  { data: [] }
}

///|
/// Append one chunk to the SHA-256 stream.
pub fn Sha256Hasher::update(self : Sha256Hasher, chunk : Array[Int]) -> Unit {
  for b in chunk {
    self.data.push(b & 0xFF)
  }
}

///|
/// Finalize the SHA-256 stream and return the digest bytes.
pub fn Sha256Hasher::finalize(self : Sha256Hasher) -> Array[Int] {
  sha256(self.data)
}

///|
/// Clear the buffered SHA-256 state for reuse.
pub fn Sha256Hasher::reset(self : Sha256Hasher) -> Unit {
  self.data.clear()
}

///|
/// CRC-32 流式校验器（zlib `crc32(crc, buf, len)` 语义）。
pub struct Crc32Hasher {
  data : Array[Int]
}

///|
/// Create an empty CRC-32 stream.
pub fn Crc32Hasher::new() -> Crc32Hasher {
  { data: [] }
}

///|
/// Append one chunk to the CRC-32 stream.
pub fn Crc32Hasher::update(self : Crc32Hasher, chunk : Array[Int]) -> Unit {
  for b in chunk {
    self.data.push(b & 0xFF)
  }
}

///|
/// Finalize the CRC-32 stream and return the checksum.
pub fn Crc32Hasher::finalize(self : Crc32Hasher) -> UInt {
  crc32(self.data)
}

///|
/// Clear the buffered CRC-32 state for reuse.
pub fn Crc32Hasher::reset(self : Crc32Hasher) -> Unit {
  self.data.clear()
}

///|
/// xxHash64 流式哈希器：保持 seed，不断追加分片后在 finalize 时统一计算。
pub struct XxHash64Hasher {
  seed : UInt64
  data : Array[Int]
}

///|
/// Create an empty xxHash64 stream with the given seed.
pub fn XxHash64Hasher::new(seed : UInt64) -> XxHash64Hasher {
  { seed, data: [] }
}

///|
/// Append one chunk to the xxHash64 stream.
pub fn XxHash64Hasher::update(
  self : XxHash64Hasher,
  chunk : Array[Int],
) -> Unit {
  for b in chunk {
    self.data.push(b & 0xFF)
  }
}

///|
/// Finalize the xxHash64 stream and return the digest.
pub fn XxHash64Hasher::finalize(self : XxHash64Hasher) -> UInt64 {
  xxhash64(self.data, self.seed)
}

///|
/// Clear the buffered xxHash64 state for reuse.
pub fn XxHash64Hasher::reset(self : XxHash64Hasher) -> Unit {
  self.data.clear()
}
