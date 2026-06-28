// pbt_test.mbt —— infra_pbt 基础设施的单元测试。
//
// 这些测试在小型确定性夹具上校验随机源、生成器与断言模板的行为，
// 验证 task 1.1 的实现自洽（Rng 确定性、模板默认迭代、往返与不变量语义）。
// 三后端逐位一致性的属性测试由后续 task 1.2 单独承载。

///|
/// Rng 同种子产生确定性序列：两个相同种子的实例逐步产生相同的值。
test "rng same seed yields identical sequence" {
  let a = rng_new(42)
  let b = rng_new(42)
  let mut i = 0
  while i < 16 {
    @test.assert_eq(a.next(), b.next())
    i += 1
  }
}

///|
/// Rng 非零种子的前若干输出非全零（基本健全性，避免退化为零不动点）。
test "rng zero seed does not collapse to zero" {
  let r = rng_new(0)
  let mut any_nonzero = false
  let mut i = 0
  while i < 8 {
    if r.next() != 0 {
      any_nonzero = true
    }
    i += 1
  }
  assert_true(any_nonzero)
}

///|
/// next_range 产生的值始终落在闭区间内。
test "next_range stays within bounds" {
  let r = rng_new(7)
  let mut i = 0
  while i < 200 {
    let v = r.next_range(3, 9)
    assert_true(v >= 3 && v <= 9)
    i += 1
  }
}

///|
/// 生成器 generate 等价于直接调用其采样函数。
test "gen generate uses sample function" {
  let g = gen_int_range(10, 10)
  let r = rng_new(1)
  @test.assert_eq(g.generate(r), 10)
}

///|
/// holds_for_all：对恒真谓词返回 true，对恒假谓词返回 false。
test "holds_for_all reflects predicate truth" {
  let g = gen_int_range(0, 100)
  assert_true(holds_for_all(g, fn(x) { x >= 0 && x <= 100 }))
  assert_false(holds_for_all(g, fn(x) { x > 100 }))
}

///|
/// round_trip：恒等编解码（单字节）应往返成功；篡改解码应往返失败。
test "round_trip detects identity and broken codecs" {
  let g = gen_int_range(0, 255)
  let encode = fn(x : Int) -> Bytes { Bytes::from_array([x.to_byte()]) }
  let decode_ok = fn(b : Bytes) -> Int? { Some(b[0].to_int()) }
  assert_true(round_trip(g, encode, decode_ok))
  // 始终解码为常数，违反往返恒等。
  let decode_bad = fn(_b : Bytes) -> Int? { Some(0) }
  assert_false(round_trip(g, encode, decode_bad))
}
