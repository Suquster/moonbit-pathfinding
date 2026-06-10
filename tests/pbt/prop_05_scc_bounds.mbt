// Property 5 · SCC partition invariants.
//
// Validates: Requirements 13.5.
//
// Three invariants for Tarjan's SCC output on a directed graph:
//   (a) #SCCs <= |V|
//   (b) Union of all SCCs covers every node in the input
//   (c) SCCs are pairwise disjoint
// A failing SCC returns `sccs.length() == 0` only when the input is empty.

///|
test "PBT 5: tarjan_scc partitions every input node exactly once" {
  let seeds = [4, 29, 61, 127, 263, 521]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 9, 0.22, 1)
    let n = nodes.length()
    let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
    for e in edges {
      let (u, v, _w) = e
      adj[u].push(v)
    }
    let sccs = @dir.tarjan_scc(nodes, fn(i) { adj[i] })
    // (a) bound
    assert_true(sccs.length() <= n)
    // (b + c) coverage + disjoint: build a seen map.
    let seen : Map[Int, Bool] = Map([])
    for comp in sccs {
      for node in comp {
        // Disjoint: each node appears in at most one SCC.
        assert_true(!seen.contains(node))
        seen[node] = true
      }
    }
    // Coverage: every input node appears in exactly one SCC.
    for node in nodes {
      assert_true(seen.contains(node))
    }
    // Size equality as a sanity check.
    assert_true(seen.length() == n)
  }
}
