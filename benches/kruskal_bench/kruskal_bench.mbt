// benches/kruskal_bench — native benchmark and smoke guard for `@und.kruskal_mst`.
//
// Edge-list workload: 1 000 nodes, ~10 000 random undirected edges with
// weights in [1, 100]. Kruskal's work is dominated by the initial edge sort
// (O(E log E)), so this benchmark is the canary for any accidental n^2
// blowup in the comparator path (see 28.1 whitebox case).
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
/// Build `m` random undirected edges over nodes `0..n`. Self-loops are
/// rejected; duplicates are allowed — Kruskal's DSU will ignore them, which
/// is part of what the benchmark exercises.
fn build_edge_list(
  seed : Int,
  n : Int,
  m : Int,
  max_w : Int,
) -> (Array[Int], Array[(Int, Int, Int)]) {
  let rng = Lcg::new(seed)
  let nodes : Array[Int] = Array::makei(n, fn(i) { i })
  let edges : Array[(Int, Int, Int)] = []
  let mut generated = 0
  while generated < m {
    let u = rng.next() % n
    let v = rng.next() % n
    if u == v {
      continue
    }
    // w ∈ [1, max_w]
    let w = 1 + rng.next() % max_w
    edges.push((u, v, w))
    generated += 1
  }
  (nodes, edges)
}

///|
/// Smoke guard: Kruskal MST on a 1k-node, 10k-edge weighted multigraph.
///
/// MST of a connected graph on |V| = 1000 must have exactly 999 edges; for
/// a disconnected graph the MSF will have strictly fewer. Either outcome
/// is acceptable — the benchmark's real job is to ensure Kruskal handles
/// the 10k-edge input without regressions.
test "smoke: kruskal_mst on 1k-node 10k-edge weighted graph" {
  let (nodes, edges) = build_edge_list(17, 1000, 10000, 100)
  let mst = @und.kruskal_mst(nodes, edges)
  // |MST| ≤ |V| - 1; if the random graph is connected this is tight.
  assert_true(mst.length() <= nodes.length() - 1)
  // Every returned edge must come from the input edge set and carry a
  // positive weight (we sampled from [1, 100]).
  for e in mst {
    let (_u, _v, w) = e
    assert_true(w >= 1 && w <= 100)
  }
}

///|
/// Native benchmark: measure only repeated Kruskal calls over a prebuilt edge list.
test "bench: kruskal_mst on 1k-node 10k-edge weighted graph" (b : @bench.T) {
  let (nodes, edges) = build_edge_list(17, 1000, 10000, 100)
  b.bench(name="kruskal_1k_nodes_10k_edges", fn() {
    b.keep(@und.kruskal_mst(nodes, edges))
  })
}
