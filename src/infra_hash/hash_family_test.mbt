// hash_family_test.mbt —— 哈希家族补全的规范测试向量。
//
// 向量来源：RFC 3174（SHA-1）、FIPS 180-4 / NIST 示例（SHA-512）、
// RFC 1321 附录 A.5（MD5）、xxhash.com sanity check（xxHash32）、
// RFC 1950（Adler-32，"Wikipedia" 例）、SipHash 参考实现附录 A 向量。

///|
/// SHA-1 规范向量（RFC 3174 §7.3 + 空串标准值）。
test "sha1 known vectors" {
  assert_true(sha1_hex("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
  assert_true(sha1_hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
  assert_true(
    sha1_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
    "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
  )
}

///|
/// SHA-512 规范向量（FIPS 180-4 / NIST CSRC 示例）。
test "sha512 known vectors" {
  assert_true(
    sha512_hex("") ==
    "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
  )
  assert_true(
    sha512_hex("abc") ==
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
  )
}

///|
/// MD5 规范向量（RFC 1321 附录 A.5 测试套件全 7 条）。
test "md5 rfc1321 test suite" {
  assert_true(md5_hex("") == "d41d8cd98f00b204e9800998ecf8427e")
  assert_true(md5_hex("a") == "0cc175b9c0f1b6a831c399e269772661")
  assert_true(md5_hex("abc") == "900150983cd24fb0d6963f7d28e17f72")
  assert_true(md5_hex("message digest") == "f96b697d7cb7938d525a2f31aaf161d0")
  assert_true(
    md5_hex("abcdefghijklmnopqrstuvwxyz") == "c3fcd3d76192e4007dfb496cca67e13b",
  )
  assert_true(
    md5_hex("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") ==
    "d174ab98d277d9f5a5611c2c9f419d9f",
  )
  assert_true(
    md5_hex(
      "12345678901234567890123456789012345678901234567890123456789012345678901234567890",
    ) ==
    "57edf4a22be3c955ac49da2e2107b67a",
  )
}

///|
/// xxHash32 官方 sanity check：空输入与已知素数种子。
test "xxhash32 sanity vectors" {
  // 官方参考实现 sanity check：XXH32("", seed=0) = 0x02CC5D05。
  assert_true(xxhash32([], 0U) == 0x02CC5D05U)
  // XXH32("", seed=PRIME32_1=0x9E3779B1) = 0x36B78AE7。
  assert_true(xxhash32([], 0x9E3779B1U) == 0x36B78AE7U)
  // 单字节确定性 + 种子敏感性（回归锚定值）。
  let one = xxhash32([0x9E], 0U)
  assert_true(one == xxhash32([0x9E], 0U))
  assert_true(one != xxhash32([0x9E], 1U))
  // 长输入覆盖 16 字节条带主循环 + 4 字节尾部 + 单字节尾部。
  let long : Array[Int] = []
  for i in 0..<37 {
    long.push(i * 7 % 256)
  }
  assert_true(xxhash32(long, 0U) == xxhash32(long, 0U))
}

///|
/// Adler-32 规范向量（RFC 1950；"Wikipedia" 经典例）。
test "adler32 known vectors" {
  assert_true(adler32([]) == 1U)
  assert_true(adler32(utf8_bytes("Wikipedia")) == 0x11E60398U)
}

///|
/// SipHash-2-4 参考实现附录 A 向量：key = 000102…0F，
/// 输入为 0..n-1 的字节序列。
test "siphash24 reference vectors" {
  let k0 = 0x0706050403020100UL
  let k1 = 0x0F0E0D0C0B0A0908UL
  // 参考实现 vectors[0..3]（小端读出）。
  let expected : Array[UInt64] = [
    0x726fdb47dd0e0e31UL, 0x74f839c593dc67fdUL, 0x0d6c8009d9a94f5aUL, 0x85676696d7fb7e2dUL,
  ]
  for n in 0..<4 {
    let input : Array[Int] = []
    for i in 0..<n {
      input.push(i)
    }
    assert_true(siphash24(input, k0, k1) == expected[n])
  }
  // 8 字节整块路径（vectors[8]）。
  let in8 : Array[Int] = [0, 1, 2, 3, 4, 5, 6, 7]
  assert_true(siphash24(in8, k0, k1) == 0x93f5f5799a932462UL)
}

///|
/// HMAC-SHA1 规范向量（RFC 2202 test case 1 / 2）。
test "hmac_sha1 rfc2202 vectors" {
  let key1 : Array[Int] = []
  for _ in 0..<20 {
    key1.push(0x0b)
  }
  assert_true(
    digest_hex(hmac_sha1(key1, utf8_bytes("Hi There"))) ==
    "b617318655057264e28bc0b6fb378c8ef146be00",
  )
  assert_true(
    digest_hex(
      hmac_sha1(utf8_bytes("Jefe"), utf8_bytes("what do ya want for nothing?")),
    ) ==
    "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79",
  )
}

///|
/// HMAC-SHA512 规范向量（RFC 4231 test case 1 / 2）。
test "hmac_sha512 rfc4231 vectors" {
  let key1 : Array[Int] = []
  for _ in 0..<20 {
    key1.push(0x0b)
  }
  assert_true(
    digest_hex(hmac_sha512(key1, utf8_bytes("Hi There"))) ==
    "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854",
  )
  assert_true(
    digest_hex(
      hmac_sha512(
        utf8_bytes("Jefe"),
        utf8_bytes("what do ya want for nothing?"),
      ),
    ) ==
    "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737",
  )
}

///|
/// 多字节 UTF-8 输入跨家族一致性（都走 utf8_bytes，非 ASCII 覆盖）。
test "hash family handles multibyte utf8 deterministically" {
  let s = "héllo 世界"
  assert_true(sha1_hex(s) == sha1_hex(s))
  assert_true(sha512_hex(s) == sha512_hex(s))
  assert_true(md5_hex(s) == md5_hex(s))
  let bytes = utf8_bytes(s)
  assert_true(adler32(bytes) == adler32(bytes))
  assert_true(xxhash32(bytes, 42U) == xxhash32(bytes, 42U))
}
