// Reusable random-graph generators for property-based tests (PBT).
//
// Covers the three shapes used throughout `tests/pbt/`:
//   * `gen_nonneg_graph` — generic weighted digraph with non-negative edge
//     weights (Dijkstra / A* / BFS-on-weights territory).
//   * `gen_dag`          — directed acyclic graph (topo-sort / DAG SCC test
//     fixture, only edges `u < v` are emitted to guarantee acyclicity).
//   * `gen_with_neg_cycle` — digraph guaranteed to contain at least one
//     negative cycle (Bellman-Ford stress fixture).
//
// All generators are **deterministic** given a `seed`, so counterexamples
// surfaced by PBT can be replayed verbatim.  They use the same minimal LCG
// specified in `tasks.md` (§27.1) to avoid pulling extra dependencies and to
// keep the implementation auditable for the formal-verification narrative.
//
// Validates: Requirements 7.1 (PBT fixtures), 7.4 (minimal reproducer).

///|
/// Minimal 32-bit linear congruential generator with ANSI C constants.
///
/// The recurrence `next = (seed * 1103515245 + 12345) & 0x7fffffff` comes
/// straight from `tasks.md` task 27.1 and matches the canonical `rand(3)`
/// family.  It is *not* cryptographically strong, but it is perfectly
/// adequate — and intentionally simple — for producing reproducible graph
/// fixtures in tests.
///
/// The `state` field is `mut` so that the generator can be threaded through a
/// loop without rebuilding the struct on every draw.
priv struct Lcg {
  mut state : Int
}

///|
/// Build a new `Lcg` seeded with `seed`.  Non-positive seeds are mapped into
/// the positive half of the 31-bit range to avoid degenerate zero cycles.
fn Lcg::new(seed : Int) -> Lcg {
  let s = if seed <= 0 { (-seed).lor(1) } else { seed }
  { state: s.land(0x7fffffff) }
}

///|
/// Advance the generator and return the new state, guaranteed non-negative.
fn Lcg::next(self : Lcg) -> Int {
  // Multiplication can overflow Int (which is 32-bit wrap-around in MoonBit);
  // masking with 0x7fffffff discards the sign bit and keeps the value in a
  // well-defined non-negative range — exactly the behaviour PBT callers expect.
  let v = (self.state * 1103515245 + 12345).land(0x7fffffff)
  self.state = v
  v
}

///|
/// Draw a uniformly distributed integer in `[0, bound)` with `bound > 0`.
///
/// Uses plain modulo; the modest bias is irrelevant for graph fixtures of the
/// sizes considered in PBT (`n` up to a few hundred nodes).
fn Lcg::int_below(self : Lcg, bound : Int) -> Int {
  if bound <= 1 {
    0
  } else {
    self.next() % bound
  }
}

///|
/// Draw a uniformly distributed integer in `[lo, hi]` (inclusive both ends).
/// Returns `lo` when `hi <= lo`.
fn Lcg::int_range(self : Lcg, lo : Int, hi : Int) -> Int {
  if hi <= lo {
    lo
  } else {
    lo + self.int_below(hi - lo + 1)
  }
}

///|
/// Draw a double in `[0.0, 1.0)` by dividing the next 31-bit sample by 2^31.
fn Lcg::uniform(self : Lcg) -> Double {
  self.next().to_double() / 2147483648.0
}

///|
/// Generate a random directed graph with **non-negative integer weights**.
///
/// Contract:
///   * `nodes` is the contiguous range `[0, n)` as an `Array[Int]`.
///   * `edges` is an `Array[(u, v, w)]` where `0 <= u, v < n`, `u != v`,
///     `0 <= w <= max_w`, and each ordered pair `(u, v)` appears at most
///     once.  Self-loops are suppressed.
///   * `density` ∈ `[0.0, 1.0]` is the probability that any particular
///     ordered non-self pair `(u, v)` is included.  Out-of-range values are
///     clamped silently.
///   * Given identical `(seed, n, density, max_w)` inputs, the output is
///     bit-for-bit identical — this is what lets PBT shrink counterexamples.
///
/// Complexity: `O(n^2)` time / `O(E)` space.
pub fn gen_nonneg_graph(
  seed : Int,
  n : Int,
  density : Double,
  max_w : Int,
) -> (Array[Int], Array[(Int, Int, Int)]) {
  let nodes : Array[Int] = Array::makei(if n < 0 { 0 } else { n }, fn(i) { i })
  let edges : Array[(Int, Int, Int)] = []
  if n <= 1 {
    return (nodes, edges)
  }
  let rng = Lcg::new(seed)
  let d = if density < 0.0 {
    0.0
  } else if density > 1.0 {
    1.0
  } else {
    density
  }
  let w_cap = if max_w < 0 { 0 } else { max_w }
  for u in 0..<n {
    for v in 0..<n {
      if u == v {
        continue
      }
      if rng.uniform() < d {
        let w = rng.int_range(0, w_cap)
        edges.push((u, v, w))
      }
    }
  }
  (nodes, edges)
}

///|
/// Generate a random **directed acyclic graph** (DAG).
///
/// Only edges `(u, v)` with `u < v` are emitted, which is the canonical
/// invariant that guarantees acyclicity for integer node IDs.  Edges are
/// unweighted — callers that need weights can attach their own later (DAG
/// fixtures mostly feed topo-sort / Kahn tests).
///
/// Contract:
///   * `nodes = [0, n)`; all returned `(u, v)` satisfy `0 <= u < v < n`;
///   * Each qualifying pair appears at most once;
///   * `density ∈ [0.0, 1.0]` is clamped silently and controls inclusion
///     probability for every forward pair;
///   * Deterministic in `seed`.
pub fn gen_dag(
  seed : Int,
  n : Int,
  density : Double,
) -> (Array[Int], Array[(Int, Int)]) {
  let nodes : Array[Int] = Array::makei(if n < 0 { 0 } else { n }, fn(i) { i })
  let edges : Array[(Int, Int)] = []
  if n <= 1 {
    return (nodes, edges)
  }
  let rng = Lcg::new(seed)
  let d = if density < 0.0 {
    0.0
  } else if density > 1.0 {
    1.0
  } else {
    density
  }
  for u in 0..<n {
    for v in (u + 1)..<n {
      if rng.uniform() < d {
        edges.push((u, v))
      }
    }
  }
  (nodes, edges)
}

///|
/// Generate a random directed graph **guaranteed to contain at least one
/// negative cycle**.
///
/// Construction strategy:
///   1. Lay down a small *negative triangle* on nodes `{0, 1, 2}` whose edge
///      weights are all drawn from `[min_w, -1]` (so the sum is guaranteed
///      negative);
///   2. Scatter additional random edges across the remaining `n*(n-1)`
///      ordered pairs with probability ≈ 0.3 and weights in
///      `[min_w, max_w]`.  This gives Bellman-Ford realistic work to do
///      beyond the pathological triangle.
///
/// Requires `n >= 3` and `min_w <= -1`; degenerate inputs fall back to the
/// smallest valid graph with a single 2-node negative cycle if possible, or
/// an empty graph otherwise (caller contract documented below).
///
/// Contract:
///   * `nodes = [0, n)`;
///   * If `n >= 3` and `min_w <= -1`, the returned `edges` contain a
///     negative cycle reachable from node 0;
///   * All edges `(u, v, w)` satisfy `u != v`, `min_w <= w <= max_w`;
///   * Deterministic in `seed`.
pub fn gen_with_neg_cycle(
  seed : Int,
  n : Int,
  min_w : Int,
  max_w : Int,
) -> (Array[Int], Array[(Int, Int, Int)]) {
  let safe_n = if n < 0 { 0 } else { n }
  let nodes : Array[Int] = Array::makei(safe_n, fn(i) { i })
  let edges : Array[(Int, Int, Int)] = []
  if safe_n < 2 || min_w >= 0 {
    return (nodes, edges)
  }
  let rng = Lcg::new(seed)
  // Clamp weight range to something Bellman-Ford can chew on.
  let lo = min_w
  let hi = if max_w < min_w { min_w } else { max_w }
  let neg_hi = -1 // guarantee strictly-negative weights on the seed triangle
  // --- Seed a guaranteed negative cycle.
  if safe_n >= 3 {
    // Triangle 0 -> 1 -> 2 -> 0 with strictly-negative edges.
    edges.push((0, 1, rng.int_range(lo, neg_hi)))
    edges.push((1, 2, rng.int_range(lo, neg_hi)))
    edges.push((2, 0, rng.int_range(lo, neg_hi)))
  } else {
    // n == 2: fall back to a 2-cycle (both edges strictly negative).
    edges.push((0, 1, rng.int_range(lo, neg_hi)))
    edges.push((1, 0, rng.int_range(lo, neg_hi)))
  }
  // --- Sprinkle random edges elsewhere (skip ones already emitted above).
  for u in 0..<safe_n {
    for v in 0..<safe_n {
      if u == v {
        continue
      }
      // Skip the triangle/2-cycle edges we already placed.
      if safe_n >= 3 {
        if (u == 0 && v == 1) || (u == 1 && v == 2) || (u == 2 && v == 0) {
          continue
        }
      } else if (u == 0 && v == 1) || (u == 1 && v == 0) {
        continue
      }
      if rng.uniform() < 0.3 {
        edges.push((u, v, rng.int_range(lo, hi)))
      }
    }
  }
  (nodes, edges)
}

// -----------------------------------------------------------------------------
// Smoke tests — sanity-check that the generators themselves produce well-formed
// fixtures before the real properties (27.2+) start relying on them.
// -----------------------------------------------------------------------------

///|
test "gen_nonneg_graph produces well-formed fixture" {
  let (nodes, edges) = gen_nonneg_graph(42, 8, 0.4, 10)
  // Nodes are exactly [0..n).
  inspect(nodes.length(), content="8")
  for i in 0..<nodes.length() {
    inspect(nodes[i], content=i.to_string())
  }
  // Every edge is well-formed: u != v, weights in [0, max_w], endpoints valid.
  for e in edges {
    let (u, v, w) = e
    assert_true(u != v)
    assert_true(u >= 0 && u < 8)
    assert_true(v >= 0 && v < 8)
    assert_true(w >= 0 && w <= 10)
  }
  // Determinism: same seed → identical output.
  let (_, edges2) = gen_nonneg_graph(42, 8, 0.4, 10)
  inspect(edges.length() == edges2.length(), content="true")
  for i in 0..<edges.length() {
    inspect(edges[i] == edges2[i], content="true")
  }
}

///|
test "gen_dag only emits forward edges" {
  let (nodes, edges) = gen_dag(7, 10, 0.5)
  inspect(nodes.length(), content="10")
  // Acyclicity witness: every edge goes from a lower id to a higher one.
  for e in edges {
    let (u, v) = e
    assert_true(u < v)
    assert_true(u >= 0 && v < 10)
  }
}

///|
test "gen_with_neg_cycle contains a detectable negative cycle" {
  let (nodes, edges) = gen_with_neg_cycle(13, 6, -5, 5)
  inspect(nodes.length(), content="6")
  // Sanity: edge count is at least the seeded triangle.
  assert_true(edges.length() >= 3)
  // Hand the fixture to Bellman-Ford from node 0 — it MUST detect the cycle.
  // This also smoke-tests that the generator's output type matches what the
  // real algorithms (used by prop_07_neg_cycle) expect.
  let result = @dir.bellman_ford(nodes, edges, 0)
  match result {
    Err(@core.NegativeCycle) => inspect(true, content="true")
    Err(_) => inspect(false, content="true")
    Ok(_) => inspect(false, content="true")
  }
}

///|
test "generators keep the main library usable (cross-package smoke)" {
  // Build a small non-negative digraph and run BFS on its adjacency view.
  // This proves the generator output can feed `@uw.bfs` without adapters —
  // the shape PBT 27.2+ will rely on.
  let (nodes, edges) = gen_nonneg_graph(3, 6, 0.6, 5)
  // Build adjacency from edge list.
  let adj : Array[Array[Int]] = Array::makei(nodes.length(), fn(_) { [] })
  for e in edges {
    let (u, v, _w) = e
    adj[u].push(v)
  }
  // BFS from 0: either reaches node 5 or returns None; both are fine,
  // we just assert the call does not crash and returns a typed answer.
  let path = @uw.bfs(0, fn(n) { adj[n] }, fn(n) { n == 5 })
  match path {
    Some(p) => assert_true(p.length() >= 1)
    None => inspect(true, content="true")
  }
  // Also exercise Undirected Kruskal on a non-empty weighted fixture so we
  // know `@und` import is wired correctly (non-negative weights only).
  let _mst = @und.kruskal_mst(nodes, edges)
  inspect(true, content="true")
}
