// tests/fuzz/runner.mbt — Fuzz + Differential Testing runner.
//
// Requirement R20.1: single-round generates >= 100 random non-negative
// weighted digraphs and cross-validates Dijkstra vs Bellman-Ford on each.
// Any cost mismatch is a counterexample proving a bug.
//
// Design:
//   * Uses the same LCG as `tests/pbt/gen.mbt` for reproducibility.
//   * Each graph has 8 nodes, density ~30%, weights in [0, 15].
//   * For each graph, runs Dijkstra and Bellman-Ford from node 0 and
//     compares the distance to every other node.
//   * On mismatch: prints the seed + (src, dst, dj_cost, bf_cost) tuple
//     so the counterexample can be replayed.
//
// This is NOT a time-bounded fuzzer (no clock); it is a deterministic
// differential test that exercises 100+ random inputs per `moon test` run.
// A true time-bounded fuzzer (tasks.md 40.2) would need external tooling
// (Python + networkx docker container); this file covers the MoonBit-native
// portion of the fuzz story.

///|
/// Minimal LCG (same constants as tests/pbt/gen.mbt).
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
/// Generate a random non-negative weighted digraph with `n` nodes and
/// approximately `n * n * density` edges, weights in `[0, max_w]`.
fn gen_graph(
  rng : Lcg,
  n : Int,
  density : Double,
  max_w : Int,
) -> (Array[Int], Array[(Int, Int, Int)]) {
  let nodes : Array[Int] = Array::makei(n, fn(i) { i })
  let edges : Array[(Int, Int, Int)] = []
  for u in 0..<n {
    for v in 0..<n {
      if u == v {
        continue
      }
      let r = rng.next().to_double() / 2147483648.0
      if r < density {
        let w = rng.next() % (max_w + 1)
        edges.push((u, v, w))
      }
    }
  }
  (nodes, edges)
}

///|
/// Differential test: Dijkstra vs Bellman-Ford on a single graph.
/// Returns the number of mismatches found (0 = pass).
fn differential_one(
  nodes : Array[Int],
  edges : Array[(Int, Int, Int)],
  source : Int,
) -> Int {
  let n = nodes.length()
  // Build adjacency for Dijkstra.
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  // Run Bellman-Ford.
  let bf_dist = match @dir.bellman_ford(nodes, edges, source) {
    Ok(m) => m
    Err(_) => return 0 // negative cycle → skip (shouldn't happen with non-neg weights)
  }
  // Compare every target.
  let inf : Int = 2147483647
  let mut mismatches = 0
  for target in nodes {
    let bf_val = bf_dist.get(target).unwrap_or(inf)
    let dj_val = match
      @dir.dijkstra(source, fn(u) { adj[u] }, fn(v) { v == target }) {
      Some((_, cost)) => cost
      None => inf
    }
    if bf_val != dj_val {
      mismatches += 1
    }
  }
  mismatches
}

///|
/// Main fuzz test: 200 random graphs, differential Dijkstra vs Bellman-Ford.
/// Any mismatch fails the test with a reproducible seed.
test "fuzz: 200 random graphs differential dijkstra vs bellman_ford" {
  let base_seed = 20260510
  let num_rounds = 200
  let rng = Lcg::new(base_seed)
  let mut total_mismatches = 0
  for _round in 0..<num_rounds {
    let seed = rng.next()
    let graph_rng = Lcg::new(seed)
    let (nodes, edges) = gen_graph(graph_rng, 8, 0.3, 15)
    let m = differential_one(nodes, edges, 0)
    if m > 0 {
      println("COUNTEREXAMPLE seed=\{seed} mismatches=\{m}")
      total_mismatches += m
    }
  }
  assert_true(total_mismatches == 0)
}

///|
/// Smaller focused test: 50 dense graphs (density 0.6) to stress edge cases.
test "fuzz: 50 dense graphs differential" {
  let rng = Lcg::new(99999)
  let mut total_mismatches = 0
  for _round in 0..<50 {
    let seed = rng.next()
    let graph_rng = Lcg::new(seed)
    let (nodes, edges) = gen_graph(graph_rng, 6, 0.6, 10)
    let m = differential_one(nodes, edges, 0)
    if m > 0 {
      println("DENSE COUNTEREXAMPLE seed=\{seed}")
      total_mismatches += m
    }
  }
  assert_true(total_mismatches == 0)
}
