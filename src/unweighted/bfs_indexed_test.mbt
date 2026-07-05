// bfs_indexed_test.mbt —— 稠密整数节点 BFS 快路径黑盒测试：定向 +
// 与通用 Map 版差分 PBT（同图同查询最短边数一致、路径合法）。

///|
test "bfs_indexed basic: shortest hop path + boundaries" {
  // 0 → 1 → 2 → 3；0 → 3 直连：最短 0→3 一跳。
  let g = @unweighted.CsrGraph::from_edges(4, [(0, 1), (1, 2), (2, 3), (0, 3)])
  match @unweighted.bfs_indexed(g, 0, 3) {
    Some(path) => assert_eq(path.length() - 1, 1)
    None => abort("expected reachable")
  }
  match @unweighted.bfs_indexed(g, 0, 2) {
    Some(path) => assert_eq(path.length() - 1, 2)
    None => abort("expected reachable")
  }
  // 自身 / 不可达 / 越界。
  match @unweighted.bfs_indexed(g, 1, 1) {
    Some(path) => assert_eq(path.length(), 1)
    None => abort("self must be reachable")
  }
  assert_true(@unweighted.bfs_indexed(g, 3, 0) is None)
  assert_true(@unweighted.bfs_indexed(g, -1, 0) is None)
  assert_true(@unweighted.bfs_indexed(g, 0, 4) is None)
}

///|
test "bfs_indexed differential PBT vs generic Map-based (150 iterations)" {
  let rng = @infra_pbt.rng_new(0xBF_51DEUL)
  for _iter in 0..<150 {
    let n = 2 + rng.next_below(60)
    let edges : Array[(Int, Int)] = []
    for _ in 0..<rng.next_below(n * 4) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v))
    }
    let g = @unweighted.CsrGraph::from_edges(n, edges)
    let adj : Array[Array[Int]] = Array::makei(n, fn(_i) { [] })
    for e in edges {
      let (u, v) = e
      adj[u].push(v)
    }
    for _q in 0..<8 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let fast = @unweighted.bfs_indexed(g, s, t)
      let slow = @unweighted.bfs(s, fn(node) { adj[node] }, fn(node) {
        node == t
      })
      match (fast, slow) {
        (Some(fpath), Some(spath)) => {
          // 最短边数一致 + 路径合法（首尾正确、每步是真实边）。
          assert_eq(fpath.length(), spath.length())
          assert_eq(fpath[0], s)
          assert_eq(fpath[fpath.length() - 1], t)
          for i in 0..<(fpath.length() - 1) {
            assert_true(adj[fpath[i]].contains(fpath[i + 1]))
          }
        }
        (None, None) => ()
        _ => abort("reachability mismatch")
      }
    }
  }
}
