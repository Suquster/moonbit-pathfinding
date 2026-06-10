// benches/bfs_bench — native benchmark and smoke guard for `@uw.bfs`.
//
// `test "smoke: ..."` keeps the workload in the normal acceptance path,
// while `test "... native benchmark" (b : @bench.T)` lets `moon bench`
// measure algorithm-level timing without counting MoonBit package startup.
//
// Graph fixture:
//   * 1 000 nodes, ~1% edge density → ~10 000 directed edges
//   * Integer nodes 0..999, adjacency array `Array[Array[Int]]`
//   * Reproducible via a minimal linear congruential generator seeded below
//
// _Requirements: 14.1, 14.2_

///|
/// Minimal LCG used here (and in other `benches/*_bench` files) so each
/// benchmark stays self-contained without pulling in the `tests/pbt` helper.
/// Constants are the classic ANSI C `rand(3)` pair, which is more than
/// enough for reproducible fixture generation.
priv struct Lcg {
  mut state : Int
}

///|
fn Lcg::new(seed : Int) -> Lcg {
  let s = if seed <= 0 { (-seed).lor(1) } else { seed }
  { state: s.land(0x7fffffff) }
}

///|
fn Lcg::next(self : Lcg) -> Int {
  let v = (self.state * 1103515245 + 12345).land(0x7fffffff)
  self.state = v
  v
}

///|
/// Build a 1 000-node adjacency array where each ordered pair (u, v) with
/// `u != v` is included with probability `density`. Deterministic given
/// `seed`.
fn build_sparse_adj(seed : Int, n : Int, density : Double) -> Array[Array[Int]] {
  let rng = Lcg::new(seed)
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    for v in 0..<n {
      if u == v {
        continue
      }
      // Use next()/2^31 in [0,1) as the Bernoulli trial.
      let r = rng.next().to_double() / 2147483648.0
      if r < density {
        adj[u].push(v)
      }
    }
  }
  adj
}

///|
/// Smoke guard: BFS from node 0 to node n-1 on a 1k-node, ~1%-density digraph.
///
/// We don't assert a specific path; the only invariants are that BFS
/// terminates in reasonable time and returns either `Some(path)` whose
/// endpoints match the query, or `None`. This is a smoke benchmark: its
/// real purpose is to prevent accidental O(V^2) regressions on realistic
/// input sizes.
test "smoke: bfs on 1k-node sparse graph (density 1%)" {
  let n = 1000
  let adj = build_sparse_adj(42, n, 0.01)
  let result = @uw.bfs(0, fn(u) { adj[u] }, fn(v) { v == n - 1 })
  match result {
    Some(p) => {
      assert_true(p.length() >= 1)
      assert_true(p[0] == 0)
      assert_true(p[p.length() - 1] == n - 1)
    }
    // Random sparse graphs sometimes have no 0 -> n-1 path; that is a
    // valid outcome and should not fail the benchmark.
    None => assert_true(true)
  }
}

///|
/// Native benchmark: measure only repeated BFS calls over a prebuilt graph.
test "bench: bfs on 1k-node sparse graph (density 1%)" (b : @bench.T) {
  let n = 1000
  let adj = build_sparse_adj(42, n, 0.01)
  b.bench(name="bfs_1k_sparse_density_1pct", fn() {
    b.keep(@uw.bfs(0, fn(u) { adj[u] }, fn(v) { v == n - 1 }))
  })
}
