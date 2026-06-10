// Property 6 · Topological sort edge consistency.
//
// Validates: Requirements 2.4, 13.6.
//
// Statement: for every edge (u, v) in a DAG, u must precede v in the
// returned topological order. `gen_dag(seed, n, density)` enforces
// `u < v` for every generated edge, so ANY permutation with
// `idx[u] < idx[v] forall (u, v) in edges` is a valid answer; we just
// check the invariant on the output.

///|
test "PBT 6: topological_sort respects edge direction on DAGs" {
  let seeds = [8, 33, 72, 145, 289]
  for s in seeds {
    let (nodes, edges) = gen_dag(s, 10, 0.3)
    let n = nodes.length()
    let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
    for e in edges {
      let (u, v) = e
      adj[u].push(v)
    }
    match @dir.topological_sort(nodes, fn(i) { adj[i] }) {
      Ok(order) => {
        // Build index: node -> position in `order`.
        let idx : Map[Int, Int] = Map([])
        let mut i = 0
        while i < order.length() {
          idx[order[i]] = i
          i += 1
        }
        // Every edge (u, v) must have idx[u] < idx[v].
        for e in edges {
          let (u, v) = e
          let pos_u = idx.get(u).unwrap()
          let pos_v = idx.get(v).unwrap()
          assert_true(pos_u < pos_v)
        }
      }
      Err(_) =>
        // gen_dag guarantees acyclicity, so Err is a bug.
        assert_true(false)
    }
  }
}

///|
test "PBT 6b: cycle detection on graphs with a known back-edge" {
  // 构造一个确定有环的图: 0 -> 1 -> 2 -> 0 是一个三角环。
  // 这直接利用 back-edge 手动构造,避免依赖 gen_dag 输出的偶然性。
  let nodes = [0, 1, 2, 3]
  let adj : Array[Array[Int]] = [[1], [2], [0], [2]]
  // 0→1→2→0 是环; 节点 3 指向 2 但自身不形成环。
  // topo_sort 对含环图必须返回 Err(CycleDetected)。
  match @dir.topological_sort(nodes, fn(i) { adj[i] }) {
    Err(@core.CycleDetected) => assert_true(true)
    _ => assert_true(false)
  }
  // 再构造一个 self-loop 图: 单节点自环也必须被检测为环。
  let nodes2 = [0]
  let adj2 : Array[Array[Int]] = [[0]]
  match @dir.topological_sort(nodes2, fn(i) { adj2[i] }) {
    Err(@core.CycleDetected) => assert_true(true)
    _ => assert_true(false)
  }
}
