// 黑盒测试：UTF-8 四字节编码、HMAC 超长密钥、流式哈希重置。

///|
test "hash：星芒层码点（4 字节 UTF-8）编码" {
  let bs = utf8_bytes("𝄞")
  assert_eq(bs.length(), 4)
  assert_eq(bs[0], 0xF0)
}

///|
test "hash：HMAC 超块长密钥先散列" {
  let key : Array[Int] = Array::make(100, 0x61) // 100 > 64 块长。
  let m1 = hmac_sha256(key, [1, 2, 3])
  let m2 = hmac_sha256(key, [1, 2, 3])
  assert_eq(m1, m2)
  assert_eq(m1.length(), 32)
}

///|
test "hash：流式哈希 reset 后重算一致" {
  let c = Crc32Hasher::new()
  c.update([1, 2, 3])
  c.reset()
  c.update([9])
  let x = XxHash64Hasher::new(0UL)
  x.update([1])
  x.reset()
  x.update([9])
  let c2 = Crc32Hasher::new()
  c2.update([9])
  assert_eq(c.finalize(), c2.finalize())
  let x2 = XxHash64Hasher::new(0UL)
  x2.update([9])
  assert_eq(x.finalize(), x2.finalize())
}
