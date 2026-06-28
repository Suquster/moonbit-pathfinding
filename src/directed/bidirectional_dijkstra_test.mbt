// Blackbox tests for bidirectional Dijkstra.

///|
fn weighted_succ(edges : Array[(Int, Int, Int)]) -> (Int) -> Array[(Int, Int)] {
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
fn weighted_pred(edges : Array[(Int, Int, Int)]) -> (Int) -> Array[(Int, Int)] {
  fn(u) {
    let out : Array[(Int, Int)] = []
    for e in edges {
      let (a, b, w) = e
      if b == u {
        out.push((a, w))
      }
    }
    out
  }
}

///|
test "bidirectional dijkstra on a simple chain" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, 2), (2, 3, 3)]
  let result = bidirectional_dijkstra(
    0,
    3,
    weighted_succ(edges),
    weighted_pred(edges),
  )
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0, 1, 2, 3]")
      inspect(cost, content="6")
    }
    None => fail("expected a path")
  }
}

///|
test "bidirectional dijkstra picks the cheaper of two routes" {
  // Direct 0 -> 3 costs 10; route 0 -> 1 -> 2 -> 3 costs 6.
  let edges : Array[(Int, Int, Int)] = [
    (0, 3, 10),
    (0, 1, 2),
    (1, 2, 2),
    (2, 3, 2),
  ]
  let result = bidirectional_dijkstra(
    0,
    3,
    weighted_succ(edges),
    weighted_pred(edges),
  )
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0, 1, 2, 3]")
      inspect(cost, content="6")
    }
    None => fail("expected a path")
  }
}

///|
test "bidirectional dijkstra start equals goal" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  let result = bidirectional_dijkstra(
    0,
    0,
    weighted_succ(edges),
    weighted_pred(edges),
  )
  match result {
    Some((path, cost)) => {
      @debug.debug_inspect(path, content="[0]")
      inspect(cost, content="0")
    }
    None => fail("expected trivial path")
  }
}

///|
test "bidirectional dijkstra unreachable goal" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (2, 3, 1)]
  let result = bidirectional_dijkstra(
    0,
    3,
    weighted_succ(edges),
    weighted_pred(edges),
  )
  assert_true(result is None)
}

///|
test "bidirectional dijkstra respects edge direction" {
  // Only 1 -> 0 exists, so 0 cannot reach 1.
  let edges : Array[(Int, Int, Int)] = [(1, 0, 1)]
  let result = bidirectional_dijkstra(
    0,
    1,
    weighted_succ(edges),
    weighted_pred(edges),
  )
  assert_true(result is None)
}

///|
test "bidirectional dijkstra agrees with dijkstra on a grid" {
  // 10x10 grid, moving right or down, weight = (x + y) % 3 + 1.
  let size = 10
  let succ = fn(u : Int) {
    let x = u % size
    let y = u / size
    let out : Array[(Int, Int)] = []
    let w = (x + y) % 3 + 1
    if x + 1 < size {
      out.push((u + 1, w))
    }
    if y + 1 < size {
      out.push((u + size, w))
    }
    out
  }
  let pred = fn(u : Int) {
    let out : Array[(Int, Int)] = []
    let x = u % size
    let y = u / size
    if x > 0 {
      let v = u - 1
      out.push((v, (v % size + v / size) % 3 + 1))
    }
    if y > 0 {
      let v = u - size
      out.push((v, (v % size + v / size) % 3 + 1))
    }
    ignore(x)
    ignore(y)
    out
  }
  let goal_node = size * size - 1
  let bi = bidirectional_dijkstra(0, goal_node, succ, pred)
  let uni = dijkstra(0, succ, fn(n) { n == goal_node })
  match (bi, uni) {
    (Some((bi_path, bi_cost)), Some((uni_path, uni_cost))) => {
      @test.assert_eq(bi_cost, uni_cost)
      @test.assert_eq(bi_path.length(), uni_path.length())
      @test.assert_eq(bi_path[0], 0)
      @test.assert_eq(bi_path[bi_path.length() - 1], goal_node)
    }
    _ => fail("both searches should find a path")
  }
}
