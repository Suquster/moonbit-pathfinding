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

// --- 通用方向无关谓词测试 ---

///|
test "round_trip_eq holds for identity encode/decode" {
  let r = round_trip_eq(42, fn(x) { x }, fn(y) { Some(y) })
  inspect(r, content="true")
}

///|
test "round_trip_eq fails when decode loses information" {
  // encode 丢弃符号，decode 无法还原负数 → 往返破坏
  let r = round_trip_eq(-3, fn(x) { if x < 0 { -x } else { x } }, fn(y) {
    Some(y)
  })
  inspect(r, content="false")
}

///|
test "round_trip_eq fails when decode returns None" {
  let r = round_trip_eq(7, fn(x) { x }, fn(_y) -> Int? { None })
  inspect(r, content="false")
}

///|
test "is_idempotent true for clamp-to-zero" {
  let clamp = fn(x : Int) -> Int { if x < 0 { 0 } else { x } }
  inspect(is_idempotent(-5, clamp), content="true")
}

///|
test "is_idempotent false for increment" {
  inspect(is_idempotent(1, fn(x) { x + 1 }), content="false")
}

///|
test "preserves true when transform keeps invariant" {
  let r = preserves(5, fn(x) { x + 1 }, fn(x) { x >= 0 })
  inspect(r, content="true")
}

///|
test "preserves vacuously true when precondition fails" {
  // x = -1 不满足 inv，前提不成立 → 平凡为真
  let r = preserves(-1, fn(x) { x - 1 }, fn(x) { x >= 0 })
  inspect(r, content="true")
}

///|
test "seq_eq true for identical sequences" {
  inspect(seq_eq([1, 2, 3], [1, 2, 3]), content="true")
}

///|
test "seq_eq false for differing length" {
  inspect(seq_eq([1, 2], [1, 2, 3]), content="false")
}

///|
test "seq_eq false for differing element" {
  inspect(seq_eq([1, 2, 3], [1, 9, 3]), content="false")
}
