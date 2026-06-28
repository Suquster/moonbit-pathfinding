// Edge-case tests for the fuzz harness itself: seed normalization and
// the differential checker's degenerate branches.

///|
test "fuzz lcg normalizes non-positive seeds" {
  let a = Lcg::new(-13)
  let b = Lcg::new(0)
  assert_true(a.next() >= 0)
  assert_true(b.next() >= 0)
}

///|
test "differential checker skips graphs with negative cycles" {
  // A 0 <-> 1 negative cycle makes Bellman-Ford bail out; the harness
  // treats that as a skip (0 mismatches) rather than a failure.
  let nodes = [0, 1]
  let edges = [(0, 1, -2), (1, 0, -2)]
  @test.assert_eq(differential_one(nodes, edges, 0), 0)
}

///|
test "differential checker counts mismatches on bad inputs" {
  // Negative (but acyclic) weights violate Dijkstra's precondition, so
  // the two algorithms legitimately disagree and the mismatch is counted.
  // Dijkstra settles node 1 at cost 2 before discovering the cheaper
  // route through node 2 (cost 1), while Bellman-Ford finds it.
  let nodes = [0, 1, 2]
  let edges = [(0, 1, 2), (0, 2, 3), (2, 1, -2)]
  assert_true(differential_one(nodes, edges, 0) > 0)
}
