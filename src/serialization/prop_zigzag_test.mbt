// prop_zigzag_test.mbt —— Property 3：zigzag 双射（旗舰深化，任务 1.3）。
//
// Feature: serialization, Property 3: zigzag 双射（zigzag bijection）
//
// 对任意 32 / 64 位有符号整数 `n`，zigzag 编码再解码为恒等：
//   `zigzag_decode_32(zigzag_encode_32(n)) == n`
//   `zigzag_decode_64(zigzag_encode_64(n)) == n`
// 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`（≥100 迭代）。
//
// **Validates: Requirements 1.2**

///|
/// 32 位有符号整数生成器：覆盖全 32 位范围（含 `Int::min_value`/`max_value`）。
fn zz_gen_int() -> @infra_pbt.Gen[Int] {
  @infra_pbt.Gen::new(fn(rng) {
    // rng.next() 提供 64 位随机字，取低 32 位重解释为有符号 Int，覆盖全域。
    rng.next().to_int()
  })
}

///|
/// 64 位有符号整数生成器：覆盖全 64 位范围。
fn zz_gen_int64() -> @infra_pbt.Gen[Int64] {
  @infra_pbt.Gen::new(fn(rng) { rng.next().reinterpret_as_int64() })
}

///|
/// Feature: serialization, Property 3: zigzag 双射（32 位）
///
/// **Validates: Requirements 1.2**
test "Feature: serialization, Property 3: zigzag bijection (32-bit)" {
  let ok = @infra_pbt.holds_for_all(zz_gen_int(), fn(n) {
    zigzag_decode_32(zigzag_encode_32(n)) == n
  })
  assert_true(ok)
}

///|
/// Feature: serialization, Property 3: zigzag 双射（64 位）
///
/// **Validates: Requirements 1.2**
test "Feature: serialization, Property 3: zigzag bijection (64-bit)" {
  let ok = @infra_pbt.holds_for_all(zz_gen_int64(), fn(n) {
    zigzag_decode_64(zigzag_encode_64(n)) == n
  })
  assert_true(ok)
}

///|
/// 具体见证：边界与代表性取值的双射（小幅负值映射为短无符号编码）。
test "zigzag encodes small magnitudes compactly and round-trips boundaries" {
  // 经典映射：0→0、-1→1、1→2、-2→3、2→4。
  @test.assert_eq(zigzag_encode_32(0), 0U)
  @test.assert_eq(zigzag_encode_32(-1), 1U)
  @test.assert_eq(zigzag_encode_32(1), 2U)
  @test.assert_eq(zigzag_encode_32(-2), 3U)
  @test.assert_eq(zigzag_encode_32(2), 4U)
  // 32 位边界往返。
  @test.assert_eq(zigzag_decode_32(zigzag_encode_32(2147483647)), 2147483647)
  @test.assert_eq(zigzag_decode_32(zigzag_encode_32(-2147483648)), -2147483648)
  // 64 位边界往返。
  @test.assert_eq(zigzag_encode_64(-1L), 1UL)
  @test.assert_eq(zigzag_encode_64(1L), 2UL)
  @test.assert_eq(
    zigzag_decode_64(zigzag_encode_64(9223372036854775807L)),
    9223372036854775807L,
  )
  @test.assert_eq(
    zigzag_decode_64(zigzag_encode_64(-9223372036854775808L)),
    -9223372036854775808L,
  )
}
