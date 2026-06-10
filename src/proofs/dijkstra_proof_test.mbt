// Runtime tests for dijkstra_proof.mbt post-condition predicates.

///|
test "check_non_negativity true for zero cost" {
  let r : (Array[Int], Int)? = Some(([0], 0))
  inspect(check_non_negativity(r), content="true")
}

///|
test "check_non_negativity true for None" {
  let r : (Array[Int], Int)? = None
  inspect(check_non_negativity(r), content="true")
}

///|
test "check_termination_measure validates natural-number bounds" {
  let nodes = [0, 1, 2, 3]
  inspect(check_termination_measure(nodes, 0), content="true")
  inspect(check_termination_measure(nodes, 4), content="true")
  inspect(check_termination_measure(nodes, 5), content="false") // > |V|
  inspect(check_termination_measure(nodes, -1), content="false") // negative
}

///|
test "check_edges_valid_weighted accepts chain with Int weights" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(2, 1)], [(3, 1)], []]
  let r : (Array[Int], Int)? = Some(([0, 1, 2, 3], 3))
  inspect(check_edges_valid_weighted(r, 0, fn(n) { adj[n] }), content="true")
}

///|
test "check_cost_matches_path catches cost-path mismatches" {
  let edge_weight = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(1)
    } else {
      None
    }
  }
  // Correct cost = 3
  let good : (Array[Int], Int)? = Some(([0, 1, 2, 3], 3))
  inspect(check_cost_matches_path(good, edge_weight), content="true")
  // Wrong cost = 99
  let bad : (Array[Int], Int)? = Some(([0, 1, 2, 3], 99))
  inspect(check_cost_matches_path(bad, edge_weight), content="false")
}

///|
test "require_non_negative_edges true on simple positive chain" {
  let edges = [(0, 1), (1, 2)]
  let ew = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(3)
    } else {
      None
    }
  }
  inspect(require_non_negative_edges(edges, ew), content="true")
}

///|
test "dijkstra_post aggregate passes on well-formed Dijkstra result" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(2, 1)], [(3, 1)], []]
  let ew = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(1)
    } else {
      None
    }
  }
  let r : (Array[Int], Int)? = Some(([0, 1, 2, 3], 3))
  inspect(dijkstra_post(r, 0, fn(n) { adj[n] }, ew), content="true")
}

///|
test "bad witness: dijkstra_post rejects invalid edge transition" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(2, 1)], []]
  let ew = fn(u : Int, v : Int) -> Int? {
    if u + 1 == v {
      Some(1)
    } else {
      None
    }
  }
  let r : (Array[Int], Int)? = Some(([0, 2], 1))
  inspect(dijkstra_post(r, 0, fn(n) { adj[n] }, ew), content="false")
}

///|
test "bad witness: dijkstra_post rejects mismatched returned cost" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 2)], [(2, 3)], []]
  let ew = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(2)
    } else if u == 1 && v == 2 {
      Some(3)
    } else {
      None
    }
  }
  let r : (Array[Int], Int)? = Some(([0, 1, 2], 99))
  inspect(dijkstra_post(r, 0, fn(n) { adj[n] }, ew), content="false")
}
