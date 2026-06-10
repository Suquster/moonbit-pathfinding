// Property 9 · Graceful handling of unreachable goals.
//
// Validates: Requirements 1.4, 3.5.
//
// Statement: for every search algorithm in the library
// (bfs / dfs / dijkstra / astar / ida_star / bidirectional_bfs), calling
// it with a goal that is PROVABLY unreachable must return `None` in
// finite time — no panic, no hang.

///|
test "PBT 9: search algos return None on isolated-node inputs" {
  // Build a graph where node n-1 is isolated (no incoming edges), so any
  // search from 0 for `n == n-1` must yield None.
  let n = 5
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  // Connected segment [0..n-2] but node n-1 is unreachable.
  let mut i = 0
  while i < n - 2 {
    adj[i].push(i + 1)
    i += 1
  }
  let unreachable_node = n - 1
  let succ_uw = fn(u : Int) { adj[u] }
  let succ_w = fn(u : Int) -> Array[(Int, Int)] {
    let out : Array[(Int, Int)] = []
    for v in adj[u] {
      out.push((v, 1))
    }
    out
  }
  let goal_pred = fn(v : Int) { v == unreachable_node }
  // BFS
  match @uw.bfs(0, succ_uw, goal_pred) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
  // DFS
  match @dir.dfs(0, succ_uw, goal_pred) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
  // Dijkstra
  match @dir.dijkstra(0, succ_w, goal_pred) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
  // A*
  match @dir.astar(0, succ_w, fn(_v) { 0 }, goal_pred) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
  // IDA*
  match @dir.ida_star(0, succ_w, fn(_v) { 0 }, goal_pred) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
  // Bidirectional BFS — needs a reverse successor too.
  let rev : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    for v in adj[u] {
      rev[v].push(u)
    }
  }
  match @dir.bidirectional_bfs(0, unreachable_node, succ_uw, fn(u) { rev[u] }) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}
