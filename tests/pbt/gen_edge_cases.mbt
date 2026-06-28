// Edge-case tests for the PBT generator helpers: non-positive seeds,
// degenerate bounds and density clamping.

///|
test "lcg normalizes non-positive seeds" {
  let a = Lcg::new(-42)
  let b = Lcg::new(0)
  // Both must still produce values in range without diverging.
  assert_true(a.int_below(10) >= 0 && a.int_below(10) < 10)
  assert_true(b.int_below(10) >= 0 && b.int_below(10) < 10)
}

///|
test "lcg degenerate bounds collapse deterministically" {
  let rng = Lcg::new(7)
  @test.assert_eq(rng.int_below(1), 0)
  @test.assert_eq(rng.int_below(0), 0)
  @test.assert_eq(rng.int_range(5, 5), 5)
  @test.assert_eq(rng.int_range(9, 3), 9)
}

///|
test "nonneg graph generator clamps size and density" {
  let (nodes0, edges0) = gen_nonneg_graph(11, 1, 0.5, 9)
  @test.assert_eq(nodes0.length(), 1)
  @test.assert_eq(edges0.length(), 0)
  let (nodes1, edges1) = gen_nonneg_graph(11, 5, -1.0, 9)
  @test.assert_eq(nodes1.length(), 5)
  @test.assert_eq(edges1.length(), 0)
  let (nodes2, edges2) = gen_nonneg_graph(11, 4, 2.0, 9)
  @test.assert_eq(nodes2.length(), 4)
  // Density clamped to 1.0: every ordered pair becomes an edge.
  @test.assert_eq(edges2.length(), 12)
}

///|
test "dag generator clamps size and density" {
  let (nodes0, edges0) = gen_dag(3, 0, 0.5)
  @test.assert_eq(nodes0.length(), 0)
  @test.assert_eq(edges0.length(), 0)
  let (nodes1, edges1) = gen_dag(3, 4, -0.5)
  @test.assert_eq(nodes1.length(), 4)
  @test.assert_eq(edges1.length(), 0)
  let (nodes2, edges2) = gen_dag(3, 3, 1.5)
  @test.assert_eq(nodes2.length(), 3)
  // Density clamped to 1.0: every forward pair (u < v) becomes an edge.
  @test.assert_eq(edges2.length(), 3)
}
