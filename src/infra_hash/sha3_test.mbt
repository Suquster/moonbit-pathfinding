// SHA-3/BLAKE2b/CRC-32C/xxHash64 官方向量测试。

///|
/// SHA3-256 官方向量（FIPS 202 示例 / CPython hashlib）。
test "sha3_256 known vectors" {
  assert_true(
    sha3_256_hex("") ==
    "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a",
  )
  assert_true(
    sha3_256_hex("abc") ==
    "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
  )
  assert_true(
    sha3_256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
    "41c0dba2a9d6240849100376a8235e2c82e1b9998a999e21db32dd97496d3376",
  )
}

///|
/// SHA3-512 官方向量。
test "sha3_512 known vectors" {
  assert_true(
    sha3_512_hex("") ==
    "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26",
  )
  assert_true(
    sha3_512_hex("abc") ==
    "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0",
  )
}

///|
/// SHA3-224 / SHA3-384 空串官方向量。
test "sha3 224 and 384 empty vectors" {
  assert_true(
    digest_hex(sha3_224(utf8_bytes(""))) ==
    "6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7",
  )
  assert_true(
    digest_hex(sha3_384(utf8_bytes(""))) ==
    "0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004",
  )
}

///|
/// SHA-3 多块吸收（长输入跨越 rate 边界，与 CPython 对拍）。
test "sha3_256 multi block absorb" {
  // 200 × 'a'（> rate 136，两次吸收）。
  let sb = StringBuilder::new()
  for _ in 0..<200 {
    sb.write_char('a')
  }
  assert_true(
    sha3_256_hex(sb.to_string()) ==
    "cce34485baf2bf2aca99b94833892a4f52896d3d153f7b840cc4f9fe695f1387",
  )
}

///|
/// BLAKE2b-512 官方向量（RFC 7693 附录 A："abc"）。
test "blake2b known vectors" {
  assert_true(
    blake2b_hex("abc") ==
    "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923",
  )
  assert_true(
    blake2b_hex("") ==
    "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce",
  )
}

///|
/// BLAKE2b 变长输出与 keyed-MAC 模式（CPython hashlib.blake2b 对拍）。
test "blake2b digest size and keyed mode" {
  // blake2b(b"abc", digest_size=32)。
  assert_true(
    digest_hex(blake2b(utf8_bytes("abc"), out_len=32)) ==
    "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319",
  )
  // keyed：blake2b(b"abc", key=b"key", digest_size=64)。
  assert_true(
    digest_hex(blake2b(utf8_bytes("abc"), key=utf8_bytes("key"))) ==
    "5c6a9a4ae911c02fb7e71a991eb9aea371ae993d4842d206e6020d46f5e41358c6d5c277c110ef86c959ed63e6ecaaaceaaff38019a43264ae06acf73b9550b1",
  )
  // 非法参数 → 空数组。
  assert_true(blake2b([], out_len=0) == [])
  assert_true(blake2b([], out_len=65) == [])
}

///|
/// CRC-32C 官方检验值：check("123456789") = 0xE3069283。
test "crc32c check value" {
  assert_true(crc32c(utf8_bytes("123456789")) == 0xE3069283U)
  assert_true(crc32c([]) == 0U)
}

///|
/// xxHash64 参考实现向量（xxhash CLI / python-xxhash 对拍）。
test "xxhash64 reference vectors" {
  assert_true(xxhash64([], 0UL) == 0xEF46DB3751D8E999UL)
  assert_true(xxhash64(utf8_bytes("xxhash"), 0UL) == 0x32DD38952C4BC720UL)
  // 长输入（> 32 字节主循环）。
  let sb = StringBuilder::new()
  for _ in 0..<100 {
    sb.write_char('a')
  }
  assert_true(xxhash64(utf8_bytes(sb.to_string()), 0UL) == 0x375041E8B1DECFB3UL)
}
