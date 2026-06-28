// Blackbox tests for A*.

///|
test "astar with zero heuristic equals dijkstra" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 10), (2, 1)],
    [(3, 10)],
    [(3, 1)],
    [],
  ]
  let a = astar(0, fn(n) { adj[n] }, fn(_n) { 0 }, fn(n) { n == 3 })
  let d = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match (a, d) {
    (Some((_pa, ca)), Some((_pd, cd))) => inspect(ca == cd, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "astar finds goal on small grid with manhattan heuristic" {
  // 3x3 grid: move 4-directionally. Start (0,0), goal (2,2).
  let successors = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let neighbors = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let filtered : Array[((Int, Int), Int)] = []
    for p in neighbors {
      let (nx, ny) = p
      if nx >= 0 && nx < 3 && ny >= 0 && ny < 3 {
        filtered.push((p, 1))
      }
    }
    filtered
  }
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    (2 - x).abs() + (2 - y).abs()
  }
  let result = astar((0, 0), successors, heuristic, fn(p) { p == (2, 2) })
  match result {
    Some((_path, cost)) => inspect(cost, content="4")
    None => inspect(false, content="true")
  }
}

///|
test "astar finds goal on 8x8 grid with manhattan heuristic" {
  // 8x8 grid, 4-directional moves, unit edge weights.
  // Start (0,0) -> goal (7,7): Manhattan distance = 14, and in an
  // open grid with unit edges the shortest path cost equals the
  // Manhattan distance itself.
  let successors = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let neighbors = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let filtered : Array[((Int, Int), Int)] = []
    for p in neighbors {
      let (nx, ny) = p
      if nx >= 0 && nx < 8 && ny >= 0 && ny < 8 {
        filtered.push((p, 1))
      }
    }
    filtered
  }
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    (7 - x).abs() + (7 - y).abs()
  }
  let result = astar((0, 0), successors, heuristic, fn(p) { p == (7, 7) })
  match result {
    Some((path, cost)) => {
      // Diagonal distance across an 8x8 grid with 4-directional moves is 14.
      inspect(cost, content="14")
      // Path must start at (0,0) and end at (7,7), and have length cost+1.
      inspect(path.length() == 15, content="true")
      inspect(path[0] == (0, 0), content="true")
      inspect(path[path.length() - 1] == (7, 7), content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
test "astar converges to None when every node is a dead end" {
  // 3-node graph where successors always returns [].
  // Goal node 2 is declared as target, but it is unreachable because
  // no node has any outgoing edges. A* must terminate (not hang) and
  // return None. Validates R3-AC5 / Requirement 3.5.
  let successors : (Int) -> Array[(Int, Int)] = fn(_n) { [] }
  let heuristic : (Int) -> Int = fn(n) { (2 - n).abs() }
  let result = astar(0, successors, heuristic, fn(n) { n == 2 })
  match result {
    None => inspect(true, content="true")
    Some(_) => inspect(false, content="true")
  }
}

///|
/// whitebox: heuristic 恒高估 — 算法仍应返回最优路径(但会多扩展节点)。
/// 当 heuristic 不可采纳(inadmissible)时,A* 不再保证最优,但只要目标可达且
/// `improve` 分支能不断放松,最终返回的 (path, cost) 仍取决于 g_cost 的松弛。
/// 本用例构造一条有唯一可达路径的图,heuristic 对所有节点返回极大常量 100,
/// 确保 improve 分支与 `g_cost.get(v) => None => true` 首次访问路径被覆盖。
test "whitebox: astar with inflated heuristic still reaches goal correctly" {
  // 0 --(1)--> 1 --(1)--> 2 --(1)--> 3  (唯一路径,总代价 3)
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(2, 1)], [(3, 1)], []]
  let successors = fn(n : Int) { adj[n] }
  // heuristic 对每个节点都返回 100 —— 严重高估,但目标仍可达。
  let heuristic = fn(_n : Int) -> Int { 100 }
  let result = astar(0, successors, heuristic, fn(n) { n == 3 })
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0, 1, 2, 3]")
      inspect(cost, content="3")
    }
    None => inspect(false, content="true")
  }
}
