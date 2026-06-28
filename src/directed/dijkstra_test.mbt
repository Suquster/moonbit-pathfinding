// Blackbox tests for Dijkstra on non-negative weighted graphs.
//
// These tests cover the four baseline cases required by tasks.md 6.3:
//   1. 4-node chain 0 -> 1 -> 2 -> 3 with unit weights, distance 3
//   2. Unreachable target -> None
//   3. start == goal -> Some(([s], zero()))
//   4. Double edge weights (validates Requirement R1-AC3)
// plus a handful of complementary tie-breaking / shortcut scenarios.

///|
test "dijkstra finds shortest path in 4-node chain" {
  // 0 --(1)--> 1 --(1)--> 2 --(1)--> 3
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(2, 1)], [(3, 1)], []]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match result {
    Some((path, cost)) => {
      inspect(cost, content="3")
      @debug.debug_inspect(path, content="[0, 1, 2, 3]")
    }
    None => inspect(false, content="true")
  }
}

///|
test "dijkstra picks cheaper of two paths" {
  // 0 -(10)-> 1 -(10)-> 3  (cost 20)
  // 0 -(1)--> 2 -(1)--> 3  (cost 2)
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 10), (2, 1)],
    [(3, 10)],
    [(3, 1)],
    [],
  ]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match result {
    Some((path, cost)) => {
      inspect(cost, content="2")
      @debug.debug_inspect(path, content="[0, 2, 3]")
    }
    None => inspect(false, content="true")
  }
}

///|
test "dijkstra unreachable target returns None" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [], []]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 2 })
  inspect(result is None, content="true")
}

///|
test "dijkstra start equals goal returns singleton path with zero cost" {
  // Even if start has outgoing edges, goal(start) triggers before any
  // relaxation, so the path must be [start] and cost must be zero().
  let adj : Array[Array[(Int, Int)]] = [[(1, 5)]]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0]")
      inspect(cost, content="0")
    }
    None => inspect(false, content="true")
  }
}

///|
test "dijkstra works with Double edge weights" {
  // Validates Requirement R1-AC3: Weight trait supports both Int and Double.
  // Graph: 0 --(1.5)--> 1 --(2.5)--> 2, direct 0 --(5.0)--> 2.
  // Shortest 0 -> 2 via 1 is 1.5 + 2.5 = 4.0 (< 5.0).
  let adj : Array[Array[(Int, Double)]] = [[(1, 1.5), (2, 5.0)], [(2, 2.5)], []]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 2 })
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0, 1, 2]")
      inspect(cost, content="4")
    }
    None => inspect(false, content="true")
  }
}

///|
test "dijkstra start equals goal with Double weight" {
  // start == goal short-circuit must also hold for Double-weighted graphs.
  let adj : Array[Array[(Int, Double)]] = [[(1, 3.14)]]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0]")
      inspect(cost, content="0")
    }
    None => inspect(false, content="true")
  }
}

///|
/// whitebox: 触发"过期条目跳过"continue 分支。
/// 同一节点先以较大距离 d=5 被 push,随后通过更优路径被更新为 d=2 并重新 push。
/// 当堆弹出旧条目 (5, 1) 时,`d > current` 为真,进入 `continue`。
/// 覆盖 `dijkstra.mbt` 中 `Some(current) => if d > current { continue }` 冷路径。
test "whitebox: dijkstra skips stale pq entry via continue branch" {
  // 0 --(5)--> 1       (慢路径,先压入)
  // 0 --(1)--> 2 --(1)--> 1   (快路径,把 dist[1] 改小为 2)
  // 1 --(100)--> 4      (goal = 4,确保不会提前终止)
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 5), (2, 1)], // 0
    [(4, 100)], // 1
    [(1, 1)], // 2
    [], // 3 占位
    [], // 4
  ]
  let result = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 4 })
  match result {
    Some((path, cost)) => {
      // 正确最短路应为 0 -> 2 -> 1 -> 4,总代价 102
      @debug.debug_inspect(path, content="[0, 2, 1, 4]")
      inspect(cost, content="102")
    }
    None => inspect(false, content="true")
  }
}
