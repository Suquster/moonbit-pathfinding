// Property 2 · BFS path integrity.
//
// Validates: Requirements 8.1, 13.2.
//
// Statement: whenever BFS returns Some(path), the path must satisfy
//   1. path[0] == start
//   2. goal(path[-1])
//   3. every consecutive pair (path[i], path[i+1]) is an edge in the graph
// These are exactly the conditions encoded by `is_valid_path` from
// `src/proofs/predicates.mbt`; this PBT exercises the runtime BFS output
// on random digraphs.

///|
/// Build an unweighted adjacency from a weighted (u, v, w) triple list,
/// discarding the weight. This lets us reuse `gen_nonneg_graph`.
fn build_unweighted_adj(
  nodes : Array[Int],
  edges : Array[(Int, Int, Int)],
) -> Array[Array[Int]] {
  let n = nodes.length()
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for e in edges {
    let (u, v, _w) = e
    adj[u].push(v)
  }
  adj
}

///|
test "PBT 2: bfs-returned paths are structurally valid" {
  let seeds = [2, 9, 17, 43, 98, 129, 257, 992]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 10, 0.3, 1)
    let adj = build_unweighted_adj(nodes, edges)
    let succ = fn(n : Int) { adj[n] }
    // For each (start, goal) ordered pair, if BFS returns Some, the path
    // must be structurally valid.
    for start in nodes {
      for goal in nodes {
        let path_opt = @uw.bfs(start, succ, fn(v) { v == goal })
        match path_opt {
          None => ()
          Some(path) => {
            // Check (1), (2), (3) via the shared `is_valid_path` predicate.
            let ok = @proofs.is_valid_path(path, start, succ)
            assert_true(ok)
            // Explicit last-node check: `is_valid_path` verifies edges
            // but not the goal predicate; add it separately.
            assert_true(path.length() > 0)
            assert_true(path[path.length() - 1] == goal)
            assert_true(path[0] == start)
          }
        }
      }
    }
  }
}
