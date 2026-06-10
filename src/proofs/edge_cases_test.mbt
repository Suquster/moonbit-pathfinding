// Blackbox edge-case tests for the proofs package: exercising the
// negative/rejecting branches of every predicate so the proof oracles
// are themselves validated against violating inputs.

///|
test "path_cost of empty path is zero" {
  let ew = fn(_u : Int, _v : Int) -> Int? { None }
  assert_eq(path_cost(([] : Array[Int]), ew), Some(0))
}

///|
test "path_cost of a path with a missing edge is None" {
  let ew = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(2)
    } else {
      None
    }
  }
  assert_true(path_cost([0, 1, 7], ew) is None)
}

///|
test "is_reachable handles revisits and unreachable goals" {
  // 0 <-> 1 cycle, 2 isolated: revisiting 0 exercises the skip branch.
  let succ = fn(n : Int) -> Array[Int] {
    match n {
      0 => [1, 1]
      1 => [0]
      _ => []
    }
  }
  assert_true(is_reachable(0, fn(n) { n == 1 }, succ, [0, 1, 2]))
  assert_true(!is_reachable(0, fn(n) { n == 2 }, succ, [0, 1, 2]))
}

///|
test "all_edges_non_negative skips absent edges" {
  let ew = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(3)
    } else {
      None
    }
  }
  assert_true(all_edges_non_negative([(0, 1), (4, 5)], ew))
}

///|
test "check_minimality rejects malformed results" {
  let succ = fn(n : Int) -> Array[Int] {
    match n {
      0 => [1, 2]
      1 => [2]
      _ => []
    }
  }
  let is_two = fn(n : Int) { n == 2 }
  // Empty path.
  assert_true(!check_minimality((Some([]) : Array[Int]?), 0, succ, is_two))
  // Path with a non-existent edge.
  assert_true(!check_minimality(Some([0, 2, 1]), 0, succ, is_two))
  // Path that does not end at the goal.
  assert_true(!check_minimality(Some([0, 1]), 0, succ, is_two))
  // start == goal must come back as a single-node path.
  assert_true(check_minimality(Some([0]), 0, succ, fn(n) { n == 0 }))
  assert_true(!check_minimality(Some([0, 1]), 0, succ, fn(_n) { true }))
  // Suboptimal: the detour 0 -> 1 -> 2 loses to the direct 0 -> 2 edge.
  assert_true(!check_minimality(Some([0, 1, 2]), 0, succ, is_two))
  // Optimal path is accepted.
  assert_true(check_minimality(Some([0, 2]), 0, succ, is_two))
}

///|
test "check_minimality accepts optimal multi-edge paths" {
  // Chain with duplicate successor listings: the minimality BFS must
  // skip already-visited nodes while confirming no shorter path exists.
  let succ = fn(n : Int) -> Array[Int] {
    match n {
      0 => [1, 1]
      1 => [2, 0]
      2 => [3]
      _ => []
    }
  }
  assert_true(check_minimality(Some([0, 1, 2, 3]), 0, succ, fn(n) { n == 3 }))
}

///|
test "weighted post-condition oracles accept None results" {
  let succ = fn(_n : Int) -> Array[(Int, Int)] { [] }
  let ew = fn(_u : Int, _v : Int) -> Int? { None }
  assert_true(check_edges_valid_weighted((None : (Array[Int], Int)?), 0, succ))
  assert_true(check_cost_matches_path((None : (Array[Int], Int)?), ew))
}

///|
test "check_cost_matches_path rejects mismatched costs" {
  let ew = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(2)
    } else {
      None
    }
  }
  assert_true(!check_cost_matches_path(Some(([0, 1], 99)), ew))
  // A path containing a missing edge can never match any cost.
  assert_true(!check_cost_matches_path(Some(([0, 5], 0)), ew))
}
