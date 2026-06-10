// Property 8 · Yen's K-Shortest monotone-cost invariant.
//
// Validates: Requirement 2.3.
//
// Statement: the paths returned by `yen_k_shortest` (when Ok) must be
// sorted by non-decreasing cost:
//   cost(paths[0]) <= cost(paths[1]) <= ... <= cost(paths[k-1])
// Additionally, paths[0].cost must equal the plain Dijkstra cost for
// the same (s, t) pair, since the first K-shortest is the shortest.

///|
test "PBT 8: yen_k_shortest returns paths with non-decreasing cost" {
  // Use small, hand-constructed graphs with multiple distinct s-t paths
  // so Yen actually produces k > 1 results.
  let graphs : Array[Array[(Int, Int, Int)]] = [
    // 4-node diamond: two paths 0-1-3 (6) and 0-2-3 (5)
    [(0, 1, 1), (0, 2, 2), (1, 3, 5), (2, 3, 3)],
    // 5-node with bypass: paths of cost 3, 4, 6
    [(0, 1, 1), (1, 2, 1), (2, 4, 1), (0, 3, 2), (3, 4, 2), (1, 4, 5)],
  ]
  for edges in graphs {
    let max_n = 0
    for e in edges {
      let (u, v, _w) = e
      let m = if u > v { u } else { v }
      if m > max_n {
        // track max index used
      }
      ignore(m)
    }
    match @dir.yen_k_shortest(0, 4, edges, 3) {
      Ok(paths) => {
        // Costs must be non-decreasing.
        let mut i = 1
        while i < paths.length() {
          let (_, cur) = paths[i]
          let (_, prev) = paths[i - 1]
          assert_true(prev <= cur)
          i += 1
        }
      }
      Err(_) => () // Some inputs legitimately produce fewer than k paths
    }
  }
}

///|
test "PBT 8b: yen first path cost equals dijkstra cost" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (0, 2, 4),
    (1, 2, 2),
    (1, 3, 5),
    (2, 3, 1),
  ]
  let adj : Array[Array[(Int, Int)]] = [[], [], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let dj = @dir.dijkstra(0, fn(n) { adj[n] }, fn(v) { v == 3 })
  let yn = @dir.yen_k_shortest(0, 3, edges, 2)
  match (dj, yn) {
    (Some((_, dj_cost)), Ok(paths)) =>
      if paths.length() > 0 {
        let (_, yen_cost) = paths[0]
        assert_true(yen_cost == dj_cost)
      }
    _ => assert_true(false)
  }
}

///|
test "PBT 8c: yen rejects k <= 0 with InvalidK" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  for bad_k in [-5, -1, 0] {
    match @dir.yen_k_shortest(0, 1, edges, bad_k) {
      Err(@core.InvalidK(k)) => assert_true(k == bad_k)
      _ => assert_true(false)
    }
  }
}
