// Blackbox edge-case tests for the advanced package: degenerate ALT
// preprocessing, CH witness/shortcut branches, and JPS forced-neighbour
// pruning in each axis direction.

///|
test "alt with zero landmarks degenerates to dijkstra" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 2)], [(2, 3)], []]
  let succ = fn(n : Int) { adj[n] }
  let lm = alt_preprocess([0, 1, 2], succ, 0)
  assert_eq(lm.landmarks.length(), 0)
  match alt_query(lm, 0, 2, succ) {
    Some((path, cost)) => {
      assert_eq(path, [0, 1, 2])
      assert_eq(cost, 5)
    }
    None => assert_true(false)
  }
}

///|
test "alt_preprocess on empty node set yields no landmarks" {
  let succ = fn(_n : Int) -> Array[(Int, Int)] { [] }
  let lm = alt_preprocess([], succ, 4)
  assert_eq(lm.landmarks.length(), 0)
}

///|
test "ch witness search suppresses redundant shortcuts" {
  // Contracting node 1 finds the direct 0 -> 2 witness (cost 1 <= 2),
  // so no shortcut is needed and queries stay exact. Pendant nodes raise
  // the edge difference of 0 and 2 so node 1 contracts while both
  // endpoints are still active, forcing a real witness search.
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 1)],
    [(2, 1)],
    [(4, 1), (6, 1)],
    [(0, 1)],
    [],
    [(0, 1)],
    [],
  ]
  let succ = fn(n : Int) { adj[n] }
  let graph = ch_preprocess([0, 1, 2, 3, 4, 5, 6], succ)
  match ch_query(graph, 0, 2) {
    Some((path, cost)) => {
      assert_eq(cost, 1)
      assert_eq(path, [0, 2])
    }
    None => assert_true(false)
  }
}

///|
test "ch shortcut replaces a more expensive existing edge" {
  // Direct 0 -> 2 costs 5; the path through node 1 costs 2. Contracting
  // node 1 must register the cheaper via-cost so queries return 2.
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 5)],
    [(2, 1)],
    [(4, 1), (6, 1)],
    [(0, 1)],
    [],
    [(0, 1)],
    [],
  ]
  let succ = fn(n : Int) { adj[n] }
  let graph = ch_preprocess([0, 1, 2, 3, 4, 5, 6], succ)
  match ch_query(graph, 0, 2) {
    Some((_, cost)) => assert_eq(cost, 2)
    None => assert_true(false)
  }
}

///|
test "ch handles a bidirected ring with a chord" {
  // Ring 0-1-2-3-4-5 (weight 1 each way) plus chord 0<->3 (weight 2).
  // Bidirectional edges create u -> v -> u pairs during contraction and
  // exercise the witness search on a denser residual graph.
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (5, 1), (3, 2)],
    [(0, 1), (2, 1)],
    [(1, 1), (3, 1)],
    [(2, 1), (4, 1), (0, 2)],
    [(3, 1), (5, 1)],
    [(4, 1), (0, 1)],
  ]
  let succ = fn(n : Int) { adj[n] }
  let graph = ch_preprocess([0, 1, 2, 3, 4, 5], succ)
  match ch_query(graph, 0, 3) {
    Some((_, cost)) => assert_eq(cost, 2)
    None => assert_true(false)
  }
  match ch_query(graph, 1, 4) {
    Some((_, cost)) => assert_eq(cost, 3)
    None => assert_true(false)
  }
  match ch_query(graph, 2, 5) {
    Some((_, cost)) => assert_eq(cost, 3)
    None => assert_true(false)
  }
}

///|
test "ch_query returns None for unreachable targets" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [], []]
  let succ = fn(n : Int) { adj[n] }
  let graph = ch_preprocess([0, 1, 2], succ)
  assert_true(ch_query(graph, 0, 2) is None)
}

///|
test "jps returns None when start or goal is blocked" {
  let blocked = Array::make(9, false)
  blocked[0] = true
  let grid = JPSGrid::new(3, 3, blocked).unwrap()
  assert_true(jps(grid, (0, 0), (2, 2)) is None)
  assert_true(jps(grid, (2, 2), (0, 0)) is None)
}

///|
test "jps grid constructor rejects malformed inputs" {
  assert_true(JPSGrid::new(0, 3, []) is None)
  assert_true(JPSGrid::new(3, 3, [false, false]) is None)
}

///|
test "jps handles forced neighbours during vertical travel" {
  // Walls on both sides of column 2 force neighbour expansion while
  // moving straight down; the optimal path remains the 4-step column.
  let blocked = Array::make(25, false)
  blocked[2 * 5 + 1] = true // (2,1)
  blocked[3 * 5 + 3] = true // (3,3)
  let grid = JPSGrid::new(5, 5, blocked).unwrap()
  match jps(grid, (0, 2), (4, 2)) {
    Some((path, cost)) => {
      assert_eq(cost, 4.0)
      assert_eq(path[0], (0, 2))
      assert_eq(path[path.length() - 1], (4, 2))
    }
    None => assert_true(false)
  }
}

///|
test "jps travels up and left across an open grid" {
  let blocked = Array::make(25, false)
  blocked[2 * 5 + 2] = true // (2,2) central obstacle
  let grid = JPSGrid::new(5, 5, blocked).unwrap()
  match jps(grid, (4, 4), (0, 0)) {
    Some((path, cost)) => {
      assert_true(cost > 0.0)
      assert_eq(path[0], (4, 4))
      assert_eq(path[path.length() - 1], (0, 0))
    }
    None => assert_true(false)
  }
}

///|
test "jps handles forced neighbours during horizontal travel" {
  // Walls above and below row 2 force neighbour expansion while moving
  // right; the optimal path remains the 4-step row.
  let blocked = Array::make(25, false)
  blocked[1 * 5 + 2] = true // (1,2)
  blocked[3 * 5 + 3] = true // (3,3)
  let grid = JPSGrid::new(5, 5, blocked).unwrap()
  match jps(grid, (2, 0), (2, 4)) {
    Some((path, cost)) => {
      assert_eq(cost, 4.0)
      assert_eq(path[0], (2, 0))
      assert_eq(path[path.length() - 1], (2, 4))
    }
    None => assert_true(false)
  }
}
