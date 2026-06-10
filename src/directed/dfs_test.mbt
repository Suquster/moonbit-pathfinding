// Blackbox tests for DFS.

///|
test "dfs reaches goal in a simple chain" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  let found = match path {
    Some(p) => p.length() >= 2 && p[0] == 0 && p[p.length() - 1] == 3
    None => false
  }
  inspect(found, content="true")
}

///|
test "dfs start equals goal" {
  let adj : Array[Array[Int]] = [[1], [0]]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match path {
    Some(p) => assert_true(p.length() == 1 && p[0] == 0)
    None => assert_true(false)
  }
}

///|
test "dfs unreachable returns None" {
  let adj : Array[Array[Int]] = [[1], [], []]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 2 })
  assert_true(path is None)
}

///|
test "dfs handles graph with cycle and still reaches goal" {
  // Graph contains a cycle 0 -> 1 -> 2 -> 0, but goal is node 3 reachable
  // via 1 -> 3. DFS must terminate (thanks to `visited`) instead of looping.
  let adj : Array[Array[Int]] = [[1], [2, 3], [0], []]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  let found = match path {
    Some(p) => p[0] == 0 && p[p.length() - 1] == 3 && p.length() >= 2
    None => false
  }
  inspect(found, content="true")
}

///|
test "dfs self loop does not hang" {
  // Node 0 has a self-loop and an edge to 1. DFS must not loop on 0 -> 0.
  let adj : Array[Array[Int]] = [[0, 1], []]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 1 })
  match path {
    Some(p) => assert_true(p.length() == 2 && p[0] == 0 && p[1] == 1)
    None => assert_true(false)
  }
}

///|
test "dfs cycle with unreachable goal returns None" {
  // Graph: 0 -> 1 -> 2 -> 1 (cycle 1<->2), isolated node 3 is the goal.
  // DFS must fully exhaust reachable set and return None without hanging.
  let adj : Array[Array[Int]] = [[1], [2], [1], []]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  assert_true(path is None)
}

///|
/// whitebox: 单节点图 — 触发 `goal(start)` 快速返回分支,不进入主循环。
/// 覆盖 `dfs.mbt` 中 `if goal(start) { return Some([start]) }` 冷路径。
test "whitebox: dfs single-node graph start equals goal short circuits" {
  // 单节点、无出边、start == goal
  let adj : Array[Array[Int]] = [[]]
  let path = dfs(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match path {
    Some(p) => assert_true(p.length() == 1 && p[0] == 0)
    None => assert_true(false)
  }
}
