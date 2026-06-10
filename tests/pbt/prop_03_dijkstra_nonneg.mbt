// Property 3 · Dijkstra non-negative distance invariant.
//
// Validates: Requirements 8.2(a), 13.3.
//
// Statement: given a graph with **non-negative** edge weights, the cost
// of every Dijkstra result is `>= Weight::zero()`. This is the lemma
// `src/proofs/dijkstra_proof.mbt :: check_non_negativity` proves
// pointwise; here we drive it over random graphs.

///|
test "PBT 3: dijkstra reports non-negative cost on non-neg graphs" {
  let seeds = [3, 11, 19, 47, 101, 131, 277, 1009]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 15, 0.2, 20)
    // Build adjacency for Dijkstra's successor function.
    let n = nodes.length()
    let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
    for e in edges {
      let (u, v, w) = e
      adj[u].push((v, w))
    }
    let succ = fn(i : Int) { adj[i] }
    // Every source -> target pair should yield a non-negative cost (or None).
    for src in nodes {
      for dst in nodes {
        let r = @dir.dijkstra(src, succ, fn(v) { v == dst })
        match r {
          None => ()
          Some((_, cost)) => {
            assert_true(@proofs.is_non_negative(cost))
            assert_true(cost >= 0)
          }
        }
      }
    }
  }
}
