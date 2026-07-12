// infra_pbt_bench.mbt —— PBT/fuzz 方向基准：属性检查、失败缩小与
// 种子化图生成在确定性生成器上的吞吐对比。

///|
test "smoke: properties hold, shrinking reaches boundary, graphs are seeded" {
  assert_true(
    @pbt.holds_for_all(@pbt.gen_int_range(0, 1000), fn(n) { n + n == 2 * n }),
  )
  let r = @pbt.check_with_shrink(
    @pbt.gen_int_range(0, 1000),
    fn(n) { n < 500 },
    @pbt.shrink_int,
  )
  assert_true(r.passed == false)
  assert_true(r.counterexample is Some(500))
  let g = @fuzz.fuzz_graph_gen(5, 42)
  let rng1 = @pbt.rng_new(7UL)
  let rng2 = @pbt.rng_new(7UL)
  let g1 = g.generate(rng1)
  let g2 = g.generate(rng2)
  assert_eq(g1.edges.length(), g2.edges.length())
}

///|
test "bench: property check / shrink / graph fuzz throughput" (b : @bench.T) {
  let gen = @pbt.gen_int_range(0, 1_000_000)
  b.bench(name="holds_for_all_200_iters", fn() {
    b.keep(@pbt.holds_for_all(gen, fn(n) { n + n == 2 * n }, iters=200))
  })
  b.bench(name="check_with_shrink_falsified", fn() {
    b.keep(
      @pbt.check_with_shrink(gen, fn(n) { n < 500_000 }, @pbt.shrink_int).passed,
    )
  })
  let weighted = @pbt.frequency([
    (1, @pbt.gen_int_range(0, 10)),
    (3, @pbt.gen_int_range(1000, 2000)),
  ])
  b.bench(name="frequency_gen_1024", fn() {
    let rng = @pbt.rng_new(20260712UL)
    let mut acc = 0
    for _ in 0..<1024 {
      acc = acc + weighted.generate(rng)
    }
    b.keep(acc)
  })
  let graph_gen = @fuzz.fuzz_graph_gen(16, 42)
  b.bench(name="fuzz_graph_gen_64", fn() {
    let rng = @pbt.rng_new(42UL)
    let mut edges = 0
    for _ in 0..<64 {
      edges = edges + graph_gen.generate(rng).edges.length()
    }
    b.keep(edges)
  })
}
