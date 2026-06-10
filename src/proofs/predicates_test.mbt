// Runtime tests for predicates.mbt.
//
// These tests exercise every predicate on small concrete fixtures so the
// proof scaffolding (R8.1, tasks.md 33.x / 34.x) is also validated at
// runtime, giving us confidence that the predicate definitions match the
// mathematical statements in docs/zh/algorithms/bfs.md and dijkstra.md.

///|
test "is_valid_path accepts chain 0->1->2->3" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let path = [0, 1, 2, 3]
  inspect(is_valid_path(path, 0, fn(n) { adj[n] }), content="true")
}

///|
test "is_valid_path rejects empty path" {
  let adj : Array[Array[Int]] = [[1]]
  let path : Array[Int] = []
  inspect(is_valid_path(path, 0, fn(n) { adj[n] }), content="false")
}

///|
test "is_valid_path rejects wrong start" {
  let adj : Array[Array[Int]] = [[1]]
  let path = [1]
  inspect(is_valid_path(path, 0, fn(n) { adj[n] }), content="false")
}

///|
test "is_valid_path rejects non-edge transition" {
  let adj : Array[Array[Int]] = [[1], [], [3], []]
  let path = [0, 2, 3] // no edge 0->2 in this graph
  inspect(is_valid_path(path, 0, fn(n) { adj[n] }), content="false")
}

///|
test "is_reachable finds goal via chain" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let nodes = [0, 1, 2, 3]
  let r = is_reachable(0, fn(n) { n == 3 }, fn(n) { adj[n] }, nodes)
  inspect(r, content="true")
}

///|
test "is_reachable short-circuits when start is goal" {
  let adj : Array[Array[Int]] = [[]]
  let r = is_reachable(0, fn(n) { n == 0 }, fn(n) { adj[n] }, [0])
  inspect(r, content="true")
}

///|
test "is_reachable returns false for unreachable goal" {
  let adj : Array[Array[Int]] = [[1], [], []]
  let r = is_reachable(0, fn(n) { n == 2 }, fn(n) { adj[n] }, [0, 1, 2])
  inspect(r, content="false")
}

///|
test "path_cost sums integer weights along a chain" {
  let path = [0, 1, 2, 3]
  let edge_weight = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(1)
    } else {
      None
    }
  }
  match path_cost(path, edge_weight) {
    Some(c) => inspect(c, content="3")
    None => assert_true(false)
  }
}

///|
test "path_cost returns None on missing edge" {
  let path = [0, 5] // no edge 0->5 under u+1==v rule
  let edge_weight = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(1)
    } else {
      None
    }
  }
  match path_cost(path, edge_weight) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}

///|
test "is_non_negative true for zero and positive" {
  inspect(is_non_negative(0), content="true")
  inspect(is_non_negative(42), content="true")
}

///|
test "is_non_negative false for negative" {
  inspect(is_non_negative(-1), content="false")
}

///|
test "all_edges_non_negative true on positive weights" {
  let edges = [(0, 1), (1, 2)]
  let ew = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(5)
    } else {
      None
    }
  }
  inspect(all_edges_non_negative(edges, ew), content="true")
}

///|
test "all_edges_non_negative false when any weight negative" {
  let edges = [(0, 1), (1, 2)]
  let ew = fn(u : Int, _v : Int) -> Int? {
    if u == 0 {
      Some(-1)
    } else {
      Some(5)
    }
  }
  inspect(all_edges_non_negative(edges, ew), content="false")
}
