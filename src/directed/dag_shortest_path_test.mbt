// Blackbox tests for DAG shortest path.

///|
fn dag_succ(edges : Array[(Int, Int, Int)]) -> (Int) -> Array[(Int, Int)] {
  fn(u) {
    let out : Array[(Int, Int)] = []
    for e in edges {
      let (a, b, w) = e
      if a == u {
        out.push((b, w))
      }
    }
    out
  }
}

///|
test "dag shortest path on diamond graph" {
  // 0 -> 1 (1), 0 -> 2 (4), 1 -> 3 (2), 2 -> 3 (1)
  // Shortest 0 -> 3 is 0,1,3 with cost 3.
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (0, 2, 4),
    (1, 3, 2),
    (2, 3, 1),
  ]
  let result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) { n == 3 })
  match result {
    Ok(Some((path, cost))) => {
      @debug.debug_inspect(path, content="[0, 1, 3]")
      inspect(cost, content="3")
    }
    _ => fail("expected a path")
  }
}

///|
test "dag shortest path handles negative edges" {
  // 0 -> 1 (5), 0 -> 2 (2), 2 -> 1 (-4): shortest 0 -> 1 is via 2, cost -2.
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 5), (0, 2, 2), (2, 1, -4)]
  let result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) { n == 1 })
  match result {
    Ok(Some((path, cost))) => {
      @debug.debug_inspect(path, content="[0, 2, 1]")
      inspect(cost, content="-2")
    }
    _ => fail("expected a path")
  }
}

///|
test "dag shortest path detects cycles" {
  let nodes = [0, 1]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 0, 1)]
  let result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) { n == 1 })
  assert_true(result is Err(@core.PathError::CycleDetected))
}

///|
test "dag shortest path returns None when goal unreachable" {
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  let result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) { n == 2 })
  assert_true(result is Ok(None))
}

///|
test "dag shortest path with start as goal" {
  let nodes = [0, 1]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  let result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) { n == 0 })
  match result {
    Ok(Some((path, cost))) => {
      @debug.debug_inspect(path, content="[0]")
      inspect(cost, content="0")
    }
    _ => fail("expected trivial path")
  }
}

///|
test "dag shortest path picks cheapest among multiple goals" {
  // Goals are 2 and 3; 0 -> 2 costs 10, 0 -> 1 -> 3 costs 2.
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [(0, 2, 10), (0, 1, 1), (1, 3, 1)]
  let result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) {
    n == 2 || n == 3
  })
  match result {
    Ok(Some((path, cost))) => {
      @debug.debug_inspect(path, content="[0, 1, 3]")
      inspect(cost, content="2")
    }
    _ => fail("expected a path")
  }
}

///|
test "dag shortest path agrees with bellman-ford on layered dag" {
  // Layered DAG with negative edges, compare against Bellman-Ford.
  let nodes = [0, 1, 2, 3, 4, 5]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 3),
    (0, 2, 6),
    (1, 3, -2),
    (2, 3, 1),
    (1, 4, 4),
    (3, 5, 2),
    (4, 5, -1),
  ]
  let dag_result = dag_shortest_path(nodes, 0, dag_succ(edges), fn(n) { n == 5 })
  match dag_result {
    Ok(Some((_, cost))) => inspect(cost, content="3")
    _ => fail("expected a path")
  }
}
