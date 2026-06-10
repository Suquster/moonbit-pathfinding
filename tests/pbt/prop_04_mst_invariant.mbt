// Property 4 · Minimum Spanning Tree structural invariants.
//
// Validates: Requirements 13.4, 13.7.
//
// Three invariants for Kruskal MST on a connected graph:
//   (a) |MST| = |V| - 1 edges
//   (b) MST is acyclic (no cycle)  — guaranteed by DSU-union skip
//   (c) MST covers every node      — guaranteed by (a) + acyclicity on a
//                                     connected graph
// For a **disconnected** input, (a) drops to |V| − #components and becomes
// a minimum spanning **forest**; we test both regimes.

///|
test "PBT 4: MST on connected graph satisfies |E| = |V| - 1" {
  // Start from a complete cycle 0-1-2-...-(n-1)-0 so the graph is
  // definitely connected; then optionally add random chords.
  let seeds = [5, 31, 71, 131, 271]
  for s in seeds {
    let n = 8
    let (nodes, extras) = gen_nonneg_graph(s, n, 0.25, 10)
    // Build a guaranteed-connected edge list: the cycle + random extras.
    let edges : Array[(Int, Int, Int)] = []
    for i in 0..<n {
      let j = (i + 1) % n
      edges.push((i, j, 1))
    }
    for e in extras {
      let (u, v, w) = e
      // Keep the extras but shift their index to avoid parallel-edge
      // duplicates muddling the invariant.
      if u != v {
        edges.push((u, v, w + 2))
      }
    }
    let mst = @und.kruskal_mst(nodes, edges)
    // (a) |MST| = |V| - 1
    assert_true(mst.length() == n - 1)
    // (b) acyclic: re-union the MST edges with a fresh DSU and check none
    //     of them connect already-connected nodes (if any did, we have
    //     a cycle and Kruskal would have skipped it).
    let dsu : @core.DSU[Int] = @core.DSU::new()
    for v in nodes {
      dsu.make_set(v)
    }
    for edge in mst {
      let (u, v, _w) = edge
      // `union` returns true iff the two nodes WERE in different sets,
      // which is exactly the "no cycle introduced" condition.
      assert_true(dsu.union(u, v))
    }
    // (c) covers every node: after adding all |V|-1 MST edges, DSU should
    //     report one single component for every pair.
    for i in 0..<n {
      assert_true(dsu.same(0, i))
    }
  }
}

///|
test "PBT 4b: MST on disconnected graph is minimum spanning forest" {
  // Two disjoint triangles: {0,1,2} and {3,4,5}. MSF should have 4 edges
  // (|V| - #components = 6 - 2 = 4).
  let nodes = [0, 1, 2, 3, 4, 5]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 2),
    (2, 0, 3),
    (3, 4, 4),
    (4, 5, 5),
    (5, 3, 6),
  ]
  let mst = @und.kruskal_mst(nodes, edges)
  assert_true(mst.length() == 4)
}
