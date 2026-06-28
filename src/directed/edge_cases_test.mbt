// Blackbox edge-case tests for the directed package: degenerate inputs
// (empty graphs, dangling edges) and less common branches of Yen,
// Bellman-Ford, topological sort and bidirectional BFS.

///|
test "floyd_warshall on empty node set returns empty map" {
  let edges : Array[(Int, Int, Int)] = []
  let result = floyd_warshall([], edges)
  @test.assert_eq(result.length(), 0)
}

///|
test "floyd_warshall ignores edges touching unknown nodes" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 2), (5, 1, 1), (0, 9, 1)]
  let result = floyd_warshall([0, 1], edges)
  @test.assert_eq(result.get((0, 1)), Some(2))
  assert_true(result.get((5, 1)) is None)
}

///|
test "bellman_ford reports negative cycle via dangling relaxation" {
  // A single declared node with an edge to an undeclared one: the final
  // verification pass can still relax it, which is reported as NegativeCycle.
  let edges : Array[(Int, Int, Int)] = [(0, 1, -1)]
  let result = bellman_ford([0], edges, 0)
  assert_true(result is Err(NegativeCycle))
}

///|
test "topological_sort flags successors outside the node set" {
  // Node 1 is referenced as a successor but never declared in `nodes`,
  // so the output length cannot match and the sort is rejected.
  let succ = fn(n : Int) -> Array[Int] { if n == 0 { [1] } else { [] } }
  let result = topological_sort([0], succ)
  assert_true(result is Err(CycleDetected))
}

///|
test "yen keeps the cheaper of parallel edges" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 5), (0, 1, 1), (1, 2, 1)]
  let result = yen_k_shortest(0, 2, edges, 1)
  match result {
    Ok(paths) => {
      @test.assert_eq(paths.length(), 1)
      let (path, cost) = paths[0]
      @test.assert_eq(path, [0, 1, 2])
      @test.assert_eq(cost, 2)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "yen enumerates equal-cost alternatives deterministically" {
  // Diamond: two distinct paths of equal cost, plus a longer detour.
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (0, 2, 1),
    (1, 3, 1),
    (2, 3, 1),
    (0, 3, 5),
  ]
  let result = yen_k_shortest(0, 3, edges, 3)
  match result {
    Ok(paths) => {
      @test.assert_eq(paths.length(), 3)
      @test.assert_eq(paths[0].1, 2)
      @test.assert_eq(paths[1].1, 2)
      @test.assert_eq(paths[2].1, 5)
      // Equal-cost paths must not be duplicates of each other.
      assert_true(paths[0].0 != paths[1].0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "yen enumerates many alternatives in a dense overlap graph" {
  // Several spur points share sub-paths, so identical candidates are
  // generated more than once and must be deduplicated.
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (0, 2, 2),
    (1, 2, 1),
    (1, 3, 3),
    (2, 3, 1),
    (2, 4, 4),
    (3, 4, 1),
    (0, 4, 10),
  ]
  let result = yen_k_shortest(0, 4, edges, 6)
  match result {
    Ok(paths) => {
      assert_true(paths.length() >= 3)
      // Costs must be non-decreasing and paths pairwise distinct.
      let mut i = 1
      while i < paths.length() {
        assert_true(paths[i - 1].1 <= paths[i].1)
        let mut j = 0
        while j < i {
          assert_true(paths[j].0 != paths[i].0)
          j += 1
        }
        i += 1
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "yen spur search skips banned root-path nodes" {
  // Node 1 has a back edge to node 0; during the spur computation at
  // node 1, node 0 is on the root path and must be skipped.
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 1),
    (1, 0, 1),
    (0, 2, 5),
  ]
  let result = yen_k_shortest(0, 2, edges, 2)
  match result {
    Ok(paths) => {
      @test.assert_eq(paths.length(), 2)
      @test.assert_eq(paths[0].1, 2)
      @test.assert_eq(paths[1].1, 5)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "bidirectional_bfs ignores already-visited duplicate successors" {
  let succ = fn(n : Int) -> Array[Int] {
    match n {
      0 => [1, 1, 2]
      1 => [3]
      2 => [3]
      _ => []
    }
  }
  let pred = fn(n : Int) -> Array[Int] {
    match n {
      3 => [1, 2]
      1 => [0, 0]
      2 => [0]
      _ => []
    }
  }
  match bidirectional_bfs(0, 3, succ, pred) {
    Some(path) => {
      @test.assert_eq(path.length(), 3)
      @test.assert_eq(path[0], 0)
      @test.assert_eq(path[2], 3)
    }
    None => assert_true(false)
  }
}

///|
test "bidirectional_dijkstra on a long chain meets in the middle" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1)],
    [(2, 1)],
    [(3, 1)],
    [(4, 1)],
    [],
  ]
  let radj : Array[Array[(Int, Int)]] = [
    [],
    [(0, 1)],
    [(1, 1)],
    [(2, 1)],
    [(3, 1)],
  ]
  let succ = fn(n : Int) { adj[n] }
  let pred = fn(n : Int) { radj[n] }
  match bidirectional_dijkstra(0, 4, succ, pred) {
    Some((path, cost)) => {
      @test.assert_eq(cost, 4)
      @test.assert_eq(path, [0, 1, 2, 3, 4])
    }
    None => assert_true(false)
  }
}

///|
test "bidirectional_dijkstra returns None when goal is unreachable" {
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    if n == 0 {
      [(1, 1)]
    } else {
      []
    }
  }
  let pred = fn(n : Int) -> Array[(Int, Int)] {
    if n == 1 {
      [(0, 1)]
    } else {
      []
    }
  }
  assert_true(bidirectional_dijkstra(0, 2, succ, pred) is None)
}

///|
test "bidirectional_dijkstra skips stale heap entries" {
  // Two routes to node 2 force a decrease-key, leaving a stale entry
  // that must be discarded when popped a second time.
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 10)],
    [(2, 1)],
    [(3, 1)],
    [],
  ]
  let radj : Array[Array[(Int, Int)]] = [
    [],
    [(0, 1)],
    [(1, 1), (0, 10)],
    [(2, 1)],
  ]
  let succ = fn(n : Int) { adj[n] }
  let pred = fn(n : Int) { radj[n] }
  match bidirectional_dijkstra(0, 3, succ, pred) {
    Some((path, cost)) => {
      @test.assert_eq(cost, 3)
      @test.assert_eq(path, [0, 1, 2, 3])
    }
    None => assert_true(false)
  }
}

///|
test "bidirectional_bfs expands the backward frontier when smaller" {
  // Fan-out from start makes the forward frontier larger, forcing the
  // search to grow the backward side (including predecessor revisits).
  let succ = fn(n : Int) -> Array[Int] {
    match n {
      0 => [1, 2, 3]
      1 => [4]
      2 => [4]
      3 => [4]
      4 => [5]
      _ => []
    }
  }
  let pred = fn(n : Int) -> Array[Int] {
    match n {
      1 => [0]
      2 => [0]
      3 => [0]
      4 => [1, 2, 3, 1]
      5 => [4, 4]
      _ => []
    }
  }
  let result = bidirectional_bfs(0, 5, succ, pred)
  match result {
    Some(path) => {
      @test.assert_eq(path.length(), 4)
      @test.assert_eq(path[0], 0)
      @test.assert_eq(path[3], 5)
    }
    None => assert_true(false)
  }
}
