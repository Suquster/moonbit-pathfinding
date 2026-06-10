// Edge-case tests for `gen_with_neg_cycle`: degenerate fallbacks
// documented in its contract.

///|
test "neg cycle generator falls back to empty graph" {
  let (nodes0, edges0) = gen_with_neg_cycle(5, 1, -3, 3)
  assert_eq(nodes0.length(), 1)
  assert_eq(edges0.length(), 0)
  // Non-negative min_w cannot seed a negative cycle.
  let (nodes1, edges1) = gen_with_neg_cycle(5, 4, 0, 3)
  assert_eq(nodes1.length(), 4)
  assert_eq(edges1.length(), 0)
}

///|
test "neg cycle generator emits a 2-cycle when n is 2" {
  let (nodes, edges) = gen_with_neg_cycle(5, 2, -3, 3)
  assert_eq(nodes.length(), 2)
  // The first two edges form the strictly-negative 2-cycle.
  let (u0, v0, w0) = edges[0]
  let (u1, v1, w1) = edges[1]
  assert_eq((u0, v0), (0, 1))
  assert_eq((u1, v1), (1, 0))
  assert_true(w0 < 0 && w1 < 0)
}
