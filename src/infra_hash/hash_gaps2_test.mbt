// 黑盒测试：覆盖率审计收口（INFRA 第七十七批）——
// HMAC 超长密钥先哈希折叠；murmur3 尾部 2/3 字节混入。

///|
test "hmac_sha1：超过分组长度的密钥先经哈希折叠" {
  let key : Array[Int] = []
  for i in 0..<100 {
    key.push(i & 0xFF)
  }
  let msg = [1, 2, 3]
  let direct = @infra_hash.hmac_sha1(key, msg)
  let folded = @infra_hash.hmac_sha1(@infra_hash.sha1(key), msg)
  assert_eq(direct, folded)
}

///|
test "murmur3_32：尾部 2/3 字节参与混合" {
  let h2 = @infra_hash.murmur3_32([1, 2, 3, 4, 5, 6], 0U)
  let h3 = @infra_hash.murmur3_32([1, 2, 3, 4, 5, 6, 7], 0U)
  assert_true(h2 != h3)
  // 参考向量：murmur3_32("") = 0。
  assert_eq(@infra_hash.murmur3_32([], 0U), 0U)
}
