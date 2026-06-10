// Tests for the systematic API completion: full-table single-source search,
// all-pairs with path reconstruction, Johnson, min-cut, Dinic, MCMF,
// Eulerian paths and SCC condensation.

///|
test "dijkstra_all settles every reachable node" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 4), (2, 1)],
    [(3, 1)],
    [(1, 2), (3, 5)],
    [],
    [(0, 1)],
  ]
  let tree = dijkstra_all(0, fn(n : Int) { adj[n] })
  assert_eq(tree.distance_to(0), Some(0))
  assert_eq(tree.distance_to(1), Some(3))
  assert_eq(tree.distance_to(2), Some(1))
  assert_eq(tree.distance_to(3), Some(4))
  // Node 4 only has an edge towards 0; it is unreachable from 0.
  assert_eq(tree.distance_to(4), (None : Int?))
  assert_eq(tree.path_to(3), Some([0, 2, 1, 3]))
  assert_eq(tree.path_to(4), (None : Array[Int]?))
  assert_eq(tree.path_to(0), Some([0]))
}

///|
test "floyd_warshall_paths reconstructs routes" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 5),
    (0, 2, 1),
    (2, 1, 2),
    (1, 3, 1),
  ]
  let ap = floyd_warshall_paths(nodes, edges)
  assert_eq(ap.distance(0, 1), Some(3))
  assert_eq(ap.path(0, 1), Some([0, 2, 1]))
  assert_eq(ap.path(0, 3), Some([0, 2, 1, 3]))
  assert_eq(ap.path(0, 0), Some([0]))
  // 3 has no outgoing edges.
  assert_eq(ap.path(3, 0), (None : Array[Int]?))
}

///|
test "floyd_warshall_paths on an empty graph" {
  let ap = floyd_warshall_paths(([] : Array[Int]), [])
  assert_eq(ap.distance(0, 1), (None : Int?))
  assert_eq(ap.path(0, 1), (None : Array[Int]?))
}

///|
test "johnson matches floyd_warshall on a graph with negative edges" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 3),
    (0, 2, 8),
    (1, 2, -4),
    (2, 3, 2),
    (3, 1, 3),
  ]
  match johnson(nodes, edges) {
    Ok(dist) => {
      assert_eq(dist.get((0, 2)), Some(-1))
      assert_eq(dist.get((0, 3)), Some(1))
      assert_eq(dist.get((3, 2)), Some(-1))
      assert_eq(dist.get((0, 0)), Some(0))
      // Cross-check every pair against Floyd-Warshall.
      let fw = floyd_warshall(nodes, edges)
      for u in nodes {
        for v in nodes {
          match dist.get((u, v)) {
            Some(d) => assert_eq(fw.get((u, v)), Some(d))
            None => ()
          }
        }
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "johnson detects negative cycles" {
  let nodes = [0, 1]
  let edges : Array[(Int, Int, Int)] = [(0, 1, -2), (1, 0, -2)]
  assert_true(johnson(nodes, edges) is Err(NegativeCycle))
}

///|
test "johnson on an empty graph" {
  match johnson(([] : Array[Int]), []) {
    Ok(dist) => assert_eq(dist.size(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "bellman_ford_paths reconstructs paths through negative edges" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 5),
    (0, 2, 2),
    (2, 1, -1),
    (1, 3, 1),
  ]
  match bellman_ford_paths(nodes, edges, 0) {
    Ok(tree) => {
      assert_eq(tree.distance_to(1), Some(1))
      assert_eq(tree.path_to(3), Some([0, 2, 1, 3]))
      assert_eq(tree.path_to(0), Some([0]))
      // No node points at 0 other than itself, and 4 is unknown.
      assert_eq(tree.distance_to(4), (None : Int?))
      assert_eq(tree.path_to(4), (None : Array[Int]?))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "bellman_ford_paths rejects negative cycles" {
  let nodes = [0, 1]
  let edges : Array[(Int, Int, Int)] = [(0, 1, -1), (1, 0, -1)]
  assert_true(bellman_ford_paths(nodes, edges, 0) is Err(NegativeCycle))
}

///|
test "min_cut value equals max flow and separates source from sink" {
  let nodes = [0, 1, 2, 3]
  let capacity : Map[(Int, Int), Int] = Map([])
  capacity[(0, 1)] = 3
  capacity[(0, 2)] = 2
  capacity[(1, 3)] = 2
  capacity[(2, 3)] = 3
  let (value, cut_edges, source_side) = min_cut(nodes, capacity, 0, 3)
  assert_eq(value, edmonds_karp(nodes, capacity, 0, 3))
  assert_eq(value, 4)
  // The cut capacity must equal the flow value.
  let mut cut_cap = 0
  for e in cut_edges {
    cut_cap += capacity.get(e).unwrap_or(0)
  }
  assert_eq(cut_cap, value)
  // Source on the source side, sink not.
  let mut has_source = false
  let mut has_sink = false
  for n in source_side {
    if n == 0 {
      has_source = true
    }
    if n == 3 {
      has_sink = true
    }
  }
  assert_true(has_source)
  assert_true(!has_sink)
}

///|
test "dinic matches edmonds_karp on a classic network" {
  let nodes = [0, 1, 2, 3, 4, 5]
  let capacity : Map[(Int, Int), Int] = Map([])
  capacity[(0, 1)] = 10
  capacity[(0, 2)] = 10
  capacity[(1, 2)] = 2
  capacity[(1, 3)] = 4
  capacity[(1, 4)] = 8
  capacity[(2, 4)] = 9
  capacity[(3, 5)] = 10
  capacity[(4, 3)] = 6
  capacity[(4, 5)] = 10
  assert_eq(dinic(nodes, capacity, 0, 5), 19)
  assert_eq(edmonds_karp(nodes, capacity, 0, 5), 19)
}

///|
test "dinic handles degenerate inputs" {
  let capacity : Map[(Int, Int), Int] = Map([])
  capacity[(0, 1)] = 5
  // Source == sink, unknown source, disconnected sink.
  assert_eq(dinic([0, 1], capacity, 0, 0), 0)
  assert_eq(dinic([0, 1], capacity, 7, 1), 0)
  assert_eq(dinic([0, 1, 2], capacity, 0, 2), 0)
}

///|
test "min_cost_max_flow routes flow through the cheaper branch first" {
  let nodes = [0, 1, 2, 3]
  // Two parallel routes 0→3: via 1 (cost 1+1) and via 2 (cost 3+3).
  let edges : Array[(Int, Int, Int, Int)] = [
    (0, 1, 2, 1),
    (1, 3, 2, 1),
    (0, 2, 2, 3),
    (2, 3, 2, 3),
  ]
  let (flow, cost) = min_cost_max_flow(nodes, edges, 0, 3)
  assert_eq(flow, 4)
  // 2 units at cost 2 each + 2 units at cost 6 each.
  assert_eq(cost, 16)
}

///|
test "min_cost_max_flow degenerate inputs" {
  let edges : Array[(Int, Int, Int, Int)] = [(0, 1, 5, 2)]
  assert_eq(min_cost_max_flow([0, 1], edges, 0, 0), (0, 0))
  assert_eq(min_cost_max_flow([0, 1], edges, 9, 1), (0, 0))
  assert_eq(min_cost_max_flow([0, 1, 2], edges, 0, 2), (0, 0))
}

///|
test "eulerian_path finds a circuit when all degrees balance" {
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int)] = [(0, 1), (1, 2), (2, 0)]
  match eulerian_path(nodes, edges) {
    Some(path) => {
      assert_eq(path.length(), 4)
      assert_eq(path[0], path[3])
    }
    None => assert_true(false)
  }
}

///|
test "eulerian_path finds an open path with one surplus node" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int)] = [(0, 1), (1, 2), (2, 0), (0, 3)]
  match eulerian_path(nodes, edges) {
    Some(path) => {
      assert_eq(path.length(), 5)
      assert_eq(path[0], 0)
      assert_eq(path[4], 3)
    }
    None => assert_true(false)
  }
}

///|
test "eulerian_path rejects unbalanced and disconnected graphs" {
  // Two nodes with out-in surplus of 1 each.
  assert_true(eulerian_path([0, 1, 2, 3], [(0, 1), (2, 3)]) is None)
  // Balanced degrees but two disconnected cycles.
  assert_true(
    eulerian_path([0, 1, 2, 3], [(0, 1), (1, 0), (2, 3), (3, 2)]) is None,
  )
  // Edge referencing an unknown node.
  assert_true(eulerian_path([0, 1], [(0, 7)]) is None)
  // No edges at all.
  assert_eq(eulerian_path([0, 1], []), Some(([] : Array[Int])))
}

///|
test "new algorithms ignore edges with unknown endpoints" {
  // bellman_ford_paths: edge out of an unreachable node is never relaxed.
  match bellman_ford_paths([0, 1, 2], [(0, 1, 1), (2, 1, 1)], 0) {
    Ok(tree) => assert_eq(tree.distance_to(1), Some(1))
    Err(_) => assert_true(false)
  }
  // floyd_warshall_paths / johnson skip edges naming unknown nodes.
  let ap = floyd_warshall_paths([0, 1], [(0, 1, 1), (0, 9, 1)])
  assert_eq(ap.distance(0, 1), Some(1))
  match johnson([0, 1], [(0, 1, 1), (9, 1, 1), (0, 8, 1)]) {
    Ok(dist) => assert_eq(dist.get((0, 1)), Some(1))
    Err(_) => assert_true(false)
  }
  // condensation: successors outside `nodes` become components of their own.
  let c = condensation([0, 1], fn(n : Int) {
    if n == 0 {
      [1, 9]
    } else {
      ([] : Array[Int])
    }
  })
  assert_eq(c.dag_edges.length(), 2)
  assert_true(c.component_of.get(9) is Some(_))
  // min_cost_max_flow skips unknown-endpoint edges; unknown sink yields 0.
  let edges : Array[(Int, Int, Int, Int)] = [(0, 1, 2, 1), (0, 9, 2, 1)]
  assert_eq(min_cost_max_flow([0, 1], edges, 0, 1), (2, 2))
  assert_eq(min_cost_max_flow([0, 1], edges, 0, 9), (0, 0))
}

///|
test "flow algorithms merge antiparallel and duplicate capacity entries" {
  // Capacities in both directions exercise reverse-slot reuse in dinic
  // and duplicate-neighbor detection in min_cut.
  let nodes = [0, 1, 2]
  let capacity : Map[(Int, Int), Int] = Map([])
  capacity[(0, 1)] = 3
  capacity[(1, 0)] = 2
  capacity[(1, 2)] = 3
  capacity[(2, 1)] = 1
  assert_eq(dinic(nodes, capacity, 0, 2), 3)
  assert_eq(dinic(nodes, capacity, 0, 9), 0)
  let (value, _, _) = min_cut(nodes, capacity, 0, 2)
  assert_eq(value, 3)
}

///|
test "eulerian_path rejects a node with degree surplus above one" {
  assert_true(eulerian_path([0, 1, 2], [(0, 1), (0, 2)]) is None)
}

///|
test "condensation collapses cycles into a DAG" {
  // Components: {0,1,2} (cycle), {3,4} (cycle), {5}.
  let adj : Array[Array[Int]] = [[1], [2], [0, 3], [4], [3, 5], []]
  let nodes = [0, 1, 2, 3, 4, 5]
  let c = condensation(nodes, fn(n : Int) { adj[n] })
  assert_eq(c.components.length(), 3)
  // All nodes are assigned, and DAG edges link distinct components.
  for n in nodes {
    assert_true(c.component_of.get(n) is Some(_))
  }
  assert_eq(c.dag_edges.length(), 2)
  for e in c.dag_edges {
    let (a, b) = e
    assert_true(a != b)
  }
  // Nodes of the same cycle share a component id.
  assert_eq(c.component_of.get(0), c.component_of.get(2))
  assert_eq(c.component_of.get(3), c.component_of.get(4))
  assert_true(c.component_of.get(0) != c.component_of.get(5))
}
