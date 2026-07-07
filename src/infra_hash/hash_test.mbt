// hash_test.mbt —— 哈希与校验测试（官方已知向量 + PBT）。

///|
test "sha256 nist fips 180-4 vectors" {
  // NIST FIPS 180-4 附录 B.1：空串。
  assert_eq(
    @infra_hash.sha256_hex(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  // "abc"。
  assert_eq(
    @infra_hash.sha256_hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  // B.2：两分组消息。
  assert_eq(
    @infra_hash.sha256_hex(
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
    ),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  // 恰好一个分组（64 字节）需要第二个填充分组。
  let sixty_four = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  assert_eq(
    @infra_hash.sha256_hex(sixty_four),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
  // UTF-8 多字节输入。
  assert_eq(
    @infra_hash.sha256_hex("路径"),
    @infra_hash.digest_hex(@infra_hash.sha256(@infra_hash.utf8_bytes("路径"))),
  )
}

///|
test "hmac sha256 rfc 4231 vectors" {
  // RFC 4231 Test Case 1：key = 0x0b × 20，data = "Hi There"。
  let key1 : Array[Int] = []
  for _ in 0..<20 {
    key1.push(0x0B)
  }
  assert_eq(
    @infra_hash.digest_hex(
      @infra_hash.hmac_sha256(key1, @infra_hash.utf8_bytes("Hi There")),
    ),
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  )
  // Test Case 2：key = "Jefe"，data = "what do ya want for nothing?"。
  assert_eq(
    @infra_hash.digest_hex(
      @infra_hash.hmac_sha256(
        @infra_hash.utf8_bytes("Jefe"),
        @infra_hash.utf8_bytes("what do ya want for nothing?"),
      ),
    ),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
  // Test Case 6：超长密钥（131 字节 0xaa）触发密钥预哈希。
  let key6 : Array[Int] = []
  for _ in 0..<131 {
    key6.push(0xAA)
  }
  assert_eq(
    @infra_hash.digest_hex(
      @infra_hash.hmac_sha256(
        key6,
        @infra_hash.utf8_bytes(
          "Test Using Larger Than Block-Size Key - Hash Key First",
        ),
      ),
    ),
    "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
  )
}

///|
test "crc32 zlib vectors" {
  // 空输入 → 0。
  assert_eq(@infra_hash.crc32([]), 0x00000000U)
  // 经典向量 "123456789" → 0xCBF43926。
  assert_eq(@infra_hash.crc32(@infra_hash.utf8_bytes("123456789")), 0xCBF43926U)
  // "abc" → 0x352441C2。
  assert_eq(@infra_hash.crc32(@infra_hash.utf8_bytes("abc")), 0x352441C2U)
}

///|
test "fnv1a vectors" {
  // 官方参考向量（http://www.isthe.com/chongo/tech/comp/fnv/）。
  assert_eq(@infra_hash.fnv1a_32([]), 0x811C9DC5U)
  assert_eq(@infra_hash.fnv1a_32(@infra_hash.utf8_bytes("a")), 0xE40C292CU)
  assert_eq(@infra_hash.fnv1a_32(@infra_hash.utf8_bytes("foobar")), 0xBF9CF968U)
  assert_eq(@infra_hash.fnv1a_64([]), 0xCBF29CE484222325UL)
  assert_eq(
    @infra_hash.fnv1a_64(@infra_hash.utf8_bytes("a")),
    0xAF63DC4C8601EC8CUL,
  )
  assert_eq(
    @infra_hash.fnv1a_64(@infra_hash.utf8_bytes("foobar")),
    0x85944171F73967E8UL,
  )
}

///|
test "hash determinism and sensitivity (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<100 {
    let bs : Array[Int] = []
    for _ in 0..<(1 + rng.next_below(100)) {
      bs.push(rng.next_below(256))
    }
    // 确定性：同输入同摘要。
    assert_eq(
      @infra_hash.digest_hex(@infra_hash.sha256(bs)),
      @infra_hash.digest_hex(@infra_hash.sha256(bs)),
    )
    assert_eq(@infra_hash.crc32(bs), @infra_hash.crc32(bs))
    // 敏感性：翻转任一位改变摘要。
    let idx = rng.next_below(bs.length())
    let mutated = bs.copy()
    mutated[idx] = mutated[idx] ^ 0x01
    assert_true(
      @infra_hash.digest_hex(@infra_hash.sha256(bs)) !=
      @infra_hash.digest_hex(@infra_hash.sha256(mutated)),
    )
    assert_true(@infra_hash.crc32(bs) != @infra_hash.crc32(mutated))
    assert_true(@infra_hash.fnv1a_64(bs) != @infra_hash.fnv1a_64(mutated))
  }
}

///|
test "sha256 length boundary sweep" {
  // 覆盖填充边界 55/56/57 与 63/64/65 字节。
  for len in [0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 128] {
    let bs : Array[Int] = []
    for i in 0..<len {
      bs.push(i % 251)
    }
    let d = @infra_hash.sha256(bs)
    assert_eq(d.length(), 32)
    for b in d {
      assert_true(b >= 0 && b <= 255)
    }
  }
}
