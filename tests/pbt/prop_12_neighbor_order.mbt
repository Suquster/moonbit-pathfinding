// Property 12 · Neighbour-order insensitivity.
//
// Validates: Requirement 6.4.
//
// Statement: shuffling the order in which `successors` returns neighbours
// must NOT change the optimal cost reported by Dijkstra / A* (weighted
// algorithms) or the path length reported by BFS (unweighted). The
// specific path chosen may differ (tie-breaking), but total cost /
// length is invariant.

///|
/// Reverse each adjacency list in place (simulates a shuffle that is
/// deterministic and easy to audit).
fn[W] reverse_each(adj : Array[Array[(Int, W)]]) -> Array[Array[(Int, W)]] {
  let out : Array[Array[(Int, W)]] = Array::makei(adj.length(), fn(_) { [] })
  for i in 0..<adj.length() {
    let src = adj[i]
    let dst : Array[(Int, W)] = []
    let mut j = src.length() - 1
    while j >= 0 {
      dst.push(src[j])
      j -= 1
    }
    out[i] = dst
  }
  out
}

///|
test "PBT 12: dijkstra cost is invariant under adjacency reversal" {
  let seeds = [10, 20, 30, 40, 50]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 10, 0.3, 8)
    let adj : Array[Array[(Int, Int)]] = Array::makei(nodes.length(), fn(_) {
      []
    })
    for e in edges {
      let (u, v, w) = e
      adj[u].push((v, w))
    }
    let adj_rev = reverse_each(adj)
    for target in nodes {
      let r1 = @dir.dijkstra(0, fn(n) { adj[n] }, fn(v) { v == target })
      let r2 = @dir.dijkstra(0, fn(n) { adj_rev[n] }, fn(v) { v == target })
      match (r1, r2) {
        (Some((_, c1)), Some((_, c2))) => assert_true(c1 == c2)
        (None, None) => ()
        _ => assert_true(false)
      }
    }
  }
}

///|
test "PBT 12b: bfs path length is invariant under adjacency reversal" {
  let seeds = [11, 21, 31, 41]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 10, 0.3, 1)
    let adj : Array[Array[Int]] = Array::makei(nodes.length(), fn(_) { [] })
    for e in edges {
      let (u, v, _w) = e
      adj[u].push(v)
    }
    let adj_rev : Array[Array[Int]] = Array::makei(nodes.length(), fn(_) { [] })
    for i in 0..<adj.length() {
      let mut j = adj[i].length() - 1
      while j >= 0 {
        adj_rev[i].push(adj[i][j])
        j -= 1
      }
    }
    for target in nodes {
      let r1 = @uw.bfs(0, fn(n) { adj[n] }, fn(v) { v == target })
      let r2 = @uw.bfs(0, fn(n) { adj_rev[n] }, fn(v) { v == target })
      match (r1, r2) {
        (Some(p1), Some(p2)) => assert_true(p1.length() == p2.length())
        (None, None) => ()
        _ => assert_true(false)
      }
    }
  }
}
