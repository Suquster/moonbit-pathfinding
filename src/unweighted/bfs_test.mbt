// Blackbox tests for the bfs function — verifying against known shortest paths.

///|
test "bfs on tiny 4-node graph finds length-3 path" {
  // graph:  0 -> 1 -> 2 -> 3
  //         0 -------> 3 (no direct edge)
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let path = bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match path {
    Some(p) =>
      assert_true(
        p.length() == 4 && p[0] == 0 && p[1] == 1 && p[2] == 2 && p[3] == 3,
      )
    None => assert_true(false)
  }
}

///|
test "bfs start equals goal returns singleton path" {
  let adj : Array[Array[Int]] = [[1], [0]]
  let path = bfs(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match path {
    Some(p) => assert_true(p.length() == 1 && p[0] == 0)
    None => assert_true(false)
  }
}

///|
test "bfs unreachable target returns None" {
  // node 0 -> 1 ; node 2 is isolated
  let adj : Array[Array[Int]] = [[1], [], []]
  let path = bfs(0, fn(n) { adj[n] }, fn(n) { n == 2 })
  assert_true(path is None)
}

///|
test "bfs knight's tour: 1,1 to 4,6 in 5 moves (Rust crate example)" {
  // Reproducing the famous example from Rust pathfinding crate README.
  let successors = fn(pos : (Int, Int)) -> Array[(Int, Int)] {
    let (x, y) = pos
    [
      (x + 1, y + 2),
      (x + 1, y - 2),
      (x - 1, y + 2),
      (x - 1, y - 2),
      (x + 2, y + 1),
      (x + 2, y - 1),
      (x - 2, y + 1),
      (x - 2, y - 1),
    ]
  }
  let path = bfs((1, 1), successors, fn(p) { p == (4, 6) })
  // From the Rust docs: `assert_eq!(result.expect("no path found").len(), 5);`
  let len = match path {
    Some(p) => p.length()
    None => 0
  }
  inspect(len, content="5")
}

///|
/// Case 5 — generic node type: `String`.
/// Validates R4-AC5: the library must accept `String` as a node type
/// because it satisfies `Eq + Hash`.
test "bfs with String node type finds shortest hop chain" {
  // Simple DAG over city names: A -> B -> C -> D, A -> C (shortcut 1 hop).
  let adj : Map[String, Array[String]] = Map::new()
  adj["A"] = ["B", "C"]
  adj["B"] = ["C"]
  adj["C"] = ["D"]
  adj["D"] = []
  let successors = fn(n : String) -> Array[String] {
    match adj.get(n) {
      Some(xs) => xs
      None => []
    }
  }
  let path = bfs("A", successors, fn(n) { n == "D" })
  // BFS takes the shortcut A -> C -> D, path length = 3.
  let len = match path {
    Some(p) => p.length()
    None => 0
  }
  inspect(len, content="3")
}

///|
/// Case 6 — generic node type: user-defined struct `Pos` with
/// `derive(Eq, Hash)`.
/// Validates R4-AC3: custom structs only need `Eq + Hash` to be used as
/// nodes; no extra trait (e.g. `Compare`) should be required.
struct Pos {
  x : Int
  y : Int
} derive(Eq, Hash)

///|
test "bfs with custom struct Pos node type reaches target in 4 moves" {
  // 3x3 grid with 4-directional moves. Start (0,0), goal (2,2).
  let successors = fn(p : Pos) -> Array[Pos] {
    let neighbors = [
      Pos::{ x: p.x + 1, y: p.y },
      Pos::{ x: p.x - 1, y: p.y },
      Pos::{ x: p.x, y: p.y + 1 },
      Pos::{ x: p.x, y: p.y - 1 },
    ]
    let filtered : Array[Pos] = []
    for q in neighbors {
      if q.x >= 0 && q.x < 3 && q.y >= 0 && q.y < 3 {
        filtered.push(q)
      }
    }
    filtered
  }
  let start = Pos::{ x: 0, y: 0 }
  let goal = Pos::{ x: 2, y: 2 }
  let path = bfs(start, successors, fn(p) { p == goal })
  // Manhattan distance from (0,0) to (2,2) is 4 edges -> path has 5 nodes.
  let len = match path {
    Some(p) => p.length()
    None => 0
  }
  inspect(len, content="5")
}

///|
/// whitebox: 单节点图 — 触发 `goal(start)` 立即返回分支,不进入 while 循环。
/// 覆盖 `bfs.mbt` 第 34-36 行的快速返回路径。
test "whitebox: bfs single-node graph start equals goal skips main loop" {
  // 图 nodes=[0],无任何出边,start=goal=0 -> 立即 Some([0])
  let adj : Array[Array[Int]] = [[]]
  let path = bfs(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match path {
    Some(p) => assert_true(p.length() == 1 && p[0] == 0)
    None => assert_true(false)
  }
}
