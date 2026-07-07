// kdf_test.mbt —— HKDF（RFC 5869）与 PBKDF2-HMAC-SHA256（RFC 7914 §11
// 官方向量）测试。

///|
fn hex_bytes(hex : String) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i + 1 < hex.length() {
    let hi = hex.get_char(i).unwrap()
    let lo = hex.get_char(i + 1).unwrap()
    let v = fn(c : Char) -> Int {
      if c >= '0' && c <= '9' {
        c.to_int() - 48
      } else {
        c.to_int() - 97 + 10
      }
    }
    out.push(v(hi) * 16 + v(lo))
    i = i + 2
  }
  out
}

///|
/// RFC 5869 附录 A.1：基础用例（SHA-256）。
test "hkdf rfc5869 test case 1" {
  let ikm = hex_bytes("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
  let salt = hex_bytes("000102030405060708090a0b0c")
  let info = hex_bytes("f0f1f2f3f4f5f6f7f8f9")
  let prk = hkdf_extract(salt, ikm)
  assert_true(
    digest_hex(prk) ==
    "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5",
  )
  match hkdf_expand(prk, info, 42) {
    Some(okm) =>
      assert_true(
        digest_hex(okm) ==
        "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
      )
    None => fail("expand should succeed")
  }
}

///|
/// RFC 5869 附录 A.2：长输入长输出（SHA-256）。
test "hkdf rfc5869 test case 2 long inputs" {
  let ikm = hex_bytes(
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f",
  )
  let salt = hex_bytes(
    "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeaf",
  )
  let info = hex_bytes(
    "b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
  )
  match hkdf(salt, ikm, info, 82) {
    Some(okm) =>
      assert_true(
        digest_hex(okm) ==
        "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87",
      )
    None => fail("hkdf should succeed")
  }
}

///|
/// RFC 5869 附录 A.3：零长 salt/info。
test "hkdf rfc5869 test case 3 zero salt info" {
  let ikm = hex_bytes("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
  match hkdf([], ikm, [], 42) {
    Some(okm) =>
      assert_true(
        digest_hex(okm) ==
        "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8",
      )
    None => fail("hkdf should succeed")
  }
  // 超规范长度拒绝。
  assert_true(hkdf([], ikm, [], 255 * 32 + 1) is None)
  assert_true(hkdf([], ikm, [], -1) is None)
}

///|
/// RFC 7914 §11 官方向量：PBKDF2-HMAC-SHA256。
test "pbkdf2 hmac sha256 rfc7914 vectors" {
  let p1 = utf8_bytes("passwd")
  let s1 = utf8_bytes("salt")
  match pbkdf2_hmac_sha256(p1, s1, 1, 64) {
    Some(dk) =>
      assert_true(
        digest_hex(dk) ==
        "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783",
      )
    None => fail("pbkdf2 should succeed")
  }
  let p2 = utf8_bytes("Password")
  let s2 = utf8_bytes("NaCl")
  match pbkdf2_hmac_sha256(p2, s2, 80000, 64) {
    Some(dk) =>
      assert_true(
        digest_hex(dk) ==
        "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d",
      )
    None => fail("pbkdf2 should succeed")
  }
  // 畸形参数拒绝。
  assert_true(pbkdf2_hmac_sha256(p1, s1, 0, 32) is None)
  assert_true(pbkdf2_hmac_sha256(p1, s1, 1, 0) is None)
}
