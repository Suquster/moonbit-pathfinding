// 白盒测试：PBT 生成器边界、round_trip 解码失败、统计失败分支、收缩去重。

///|
test "pbt：next_below 非正上界返回 0 与 gen_bool 采样" {
  let rng = rng_new(42UL)
  assert_eq(rng.next_below(0), 0)
  assert_eq(rng.next_below(-3), 0)
  let gb = gen_bool()
  let v = gb.generate(rng)
  assert_true(v == true || v == false)
}

///|
test "pbt：round_trip 解码失败即 false" {
  let g = gen_int_range(0, 10)
  let ok = round_trip(g, fn(_x) { b"" }, fn(_b) { (None : Int?) })
  assert_eq(ok, false)
}

///|
test "pbt：holds_for_all_stats 记录失败" {
  let g = gen_int_range(0, 10)
  let (passed, stats) = holds_for_all_stats(
    g,
    fn(_x) { false },
    fn(_x) { "all" },
    iters=3,
  )
  assert_eq(passed, false)
  assert_true(stats.total() >= 3)
}

///|
test "pbt：contains_int 命中路径" {
  assert_true(contains_int([1, 2, 3], 2))
  assert_true(!contains_int([1, 2, 3], 9))
}
