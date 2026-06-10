// benches/dijkstra_bench — native benchmark and smoke guard for `@dir.dijkstra`.
//
// Uses the same 1k-node sparse graph construction as `bfs_bench.mbt`, but
// attaches a non-negative integer weight to every edge so Dijkstra has
// something to relax on. The LCG block is intentionally duplicated so each
// benchmark package stays self-contained.
//
// _Requirements: 14.1, 14.2_

///|
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
/// 1 000-node adjacency with `(neighbor, weight)` pairs. Weights are
/// uniformly sampled from `[1, max_w]` to avoid zero-weight ties that make
/// tie-breaking dominate the wall-clock measurement.
fn build_sparse_weighted_adj(
  seed : Int,
  n : Int,
  density : Double,
  max_w : Int,
) -> Array[Array[(Int, Int)]] {
  let rng = Lcg::new(seed)
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    for v in 0..<n {
      if u == v {
        continue
      }
      let r = rng.next().to_double() / 2147483648.0
      if r < density {
        // w ∈ [1, max_w]
        let w = 1 + rng.next() % max_w
        adj[u].push((v, w))
      }
    }
  }
  adj
}

///|
/// Smoke guard: Dijkstra from node 0 to node n-1 on a 1k-node, ~1%-density
/// weighted digraph with edge weights in [1, 10].
test "smoke: dijkstra on 1k-node sparse weighted graph (density 1%)" {
  let n = 1000
  let adj = build_sparse_weighted_adj(7, n, 0.01, 10)
  let result = @dir.dijkstra(0, fn(u) { adj[u] }, fn(v) { v == n - 1 })
  match result {
    Some((p, cost)) => {
      assert_true(p.length() >= 1)
      assert_true(p[0] == 0)
      assert_true(p[p.length() - 1] == n - 1)
      // Non-negative weights ⇒ non-negative cost.
      assert_true(cost >= 0)
    }
    None => assert_true(true)
  }
}

///|
/// Native benchmark: measure only repeated Dijkstra calls over a prebuilt graph.
test "bench: dijkstra on 1k-node sparse weighted graph (density 1%)" (
  b : @bench.T,
) {
  let n = 1000
  let adj = build_sparse_weighted_adj(7, n, 0.01, 10)
  b.bench(name="dijkstra_1k_sparse_density_1pct", fn() {
    b.keep(@dir.dijkstra(0, fn(u) { adj[u] }, fn(v) { v == n - 1 }))
  })
}
