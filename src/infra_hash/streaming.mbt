// streaming.mbt —— 流式增量哈希 API（Go `hash.Hash` / zlib 可续算语义）。

///|
/// SHA-256 流式哈希器：多次 update，finalize 与一次性 `sha256` 一致。
pub struct Sha256Hasher {
  data : Array[Int]
}

///|
pub fn Sha256Hasher::new() -> Sha256Hasher {
  { data: [] }
}

///|
pub fn Sha256Hasher::update(self : Sha256Hasher, chunk : Array[Int]) -> Unit {
  for b in chunk {
    self.data.push(b & 0xFF)
  }
}

///|
pub fn Sha256Hasher::finalize(self : Sha256Hasher) -> Array[Int] {
  sha256(self.data)
}

///|
pub fn Sha256Hasher::reset(self : Sha256Hasher) -> Unit {
  self.data.clear()
}

///|
/// CRC-32 流式校验器（zlib `crc32(crc, buf, len)` 语义）。
pub struct Crc32Hasher {
  data : Array[Int]
}

///|
pub fn Crc32Hasher::new() -> Crc32Hasher {
  { data: [] }
}

///|
pub fn Crc32Hasher::update(self : Crc32Hasher, chunk : Array[Int]) -> Unit {
  for b in chunk {
    self.data.push(b & 0xFF)
  }
}

///|
pub fn Crc32Hasher::finalize(self : Crc32Hasher) -> UInt {
  crc32(self.data)
}

///|
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
pub fn XxHash64Hasher::new(seed : UInt64) -> XxHash64Hasher {
  { seed, data: [] }
}

///|
pub fn XxHash64Hasher::update(
  self : XxHash64Hasher,
  chunk : Array[Int],
) -> Unit {
  for b in chunk {
    self.data.push(b & 0xFF)
  }
}

///|
pub fn XxHash64Hasher::finalize(self : XxHash64Hasher) -> UInt64 {
  xxhash64(self.data, self.seed)
}

///|
pub fn XxHash64Hasher::reset(self : XxHash64Hasher) -> Unit {
  self.data.clear()
}
