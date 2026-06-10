// Blackbox tests for the bfs function — exercising the public package API.
//
// These tests deliberately live outside `src/unweighted/` and consume the
// library through its published alias `@uw` (imported in moon.pkg), so they
// validate exactly what a downstream user of mooncakes.io will see.

///|
test "bfs on tiny 4-node graph finds length-3 path" {
  // graph:  0 -> 1 -> 2 -> 3
  //         0 -------> 3 (no direct edge)
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let path = @uw.bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
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
  let path = @uw.bfs(0, fn(n) { adj[n] }, fn(n) { n == 0 })
  match path {
    Some(p) => assert_true(p.length() == 1 && p[0] == 0)
    None => assert_true(false)
  }
}

///|
test "bfs unreachable target returns None" {
  // node 0 -> 1 ; node 2 is isolated
  let adj : Array[Array[Int]] = [[1], [], []]
  let path = @uw.bfs(0, fn(n) { adj[n] }, fn(n) { n == 2 })
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
  let path = @uw.bfs((1, 1), successors, fn(p) { p == (4, 6) })
  // From the Rust docs: `assert_eq!(result.expect("no path found").len(), 5);`
  let len = match path {
    Some(p) => p.length()
    None => 0
  }
  inspect(len, content="5")
}
