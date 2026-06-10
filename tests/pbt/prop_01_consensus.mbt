// Property 1 · Cross-algorithm shortest-path consensus.
//
// Validates: Requirements 7.3, 13.1, 13.8.
//
// Statement: on any random non-negative-weighted digraph, Dijkstra,
// Bellman-Ford (without negative cycles), and A*(h=0) must report
// identical shortest distances from a common source to every reachable
// node. "Three agree" is the strongest single-run check of correctness
// against each other's bugs.

///|
/// Build an adjacency map from (u, v, w) triples so Dijkstra / A* can
/// query successors in O(1); Bellman-Ford uses the edges directly.
fn build_adj_from_triples(
  nodes : Array[Int],
  edges : Array[(Int, Int, Int)],
) -> Array[Array[(Int, Int)]] {
  let n = nodes.length()
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  adj
}

///|
test "PBT 1: dijkstra, bellman_ford, astar(h=0) agree on random graphs" {
  // Drive 8 independent random graphs; with n=12 nodes & density 0.25 we
  // get roughly 30 edges each — enough diversity to catch consensus bugs
  // without blowing up test time on Windows runners.
  let seeds = [1, 7, 13, 42, 97, 128, 256, 991]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 12, 0.25, 10)
    let adj = build_adj_from_triples(nodes, edges)
    let succ = fn(n : Int) { adj[n] }
    // Run Bellman-Ford once to get all source-to-v distances.
    let bf = match @dir.bellman_ford(nodes, edges, 0) {
      Ok(m) => m
      Err(_) => {
        // Non-negative weights + no negative cycle ⇒ must be Ok; fail fast.
        assert_true(false)
        return
      }
    }
    // For every reachable target, check Dijkstra and A*(h=0) agree with BF.
    for target in nodes {
      match bf.get(target) {
        None => () // truly unreachable in BF
        Some(bf_cost) => {
          let dj = @dir.dijkstra(0, succ, fn(v) { v == target })
          let as_ = @dir.astar(0, succ, fn(_v) { 0 }, fn(v) { v == target })
          match (dj, as_) {
            (Some((_, dj_cost)), Some((_, as_cost))) => {
              assert_true(dj_cost == bf_cost)
              assert_true(as_cost == bf_cost)
            }
            (None, None) =>
              // All three algorithms agree this target is unreachable.
              // bf.get(target) returned Some, which means target IS
              // reachable (BF records only reachable nodes) — mismatch.
              // Fail to flag the inconsistency.
              assert_true(false)
            _ => assert_true(false)
          }
        }
      }
    }
  }
}
