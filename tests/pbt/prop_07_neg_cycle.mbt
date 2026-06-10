// Property 7 · Bellman-Ford negative-cycle detection.
//
// Validates: Requirement 2.2.
//
// Statement:
//   * `gen_with_neg_cycle` guarantees at least one reachable negative
//     cycle from node 0, so Bellman-Ford MUST return
//     `Err(@core.NegativeCycle)`.
//   * `gen_nonneg_graph` (weights ≥ 0) guarantees NO negative cycle, so
//     Bellman-Ford MUST return `Ok(dist)`.

///|
test "PBT 7: bellman_ford detects negative cycles" {
  let seeds = [6, 35, 79, 147, 311]
  for s in seeds {
    let (nodes, edges) = gen_with_neg_cycle(s, 6, -5, 5)
    match @dir.bellman_ford(nodes, edges, 0) {
      Err(@core.NegativeCycle) => assert_true(true)
      Err(e) => {
        ignore(e)
        assert_true(false)
      }
      Ok(_) => assert_true(false)
    }
  }
}

///|
test "PBT 7b: bellman_ford reports Ok on non-negative-weight graphs" {
  let seeds = [13, 67, 113, 229, 479]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 8, 0.3, 12)
    match @dir.bellman_ford(nodes, edges, 0) {
      Ok(dist) =>
        // Source is always at distance 0.
        assert_true(dist.get(0) == Some(0))
      Err(_) => assert_true(false)
    }
  }
}
