// dijkstra_indexed_test.mbt —— 稠密整数节点 Dijkstra/A* 快路径黑盒测试：
// 定向 + 与通用 Map 版差分 PBT（同图同查询最短代价一致、路径合法）。

///|
test "dijkstra_indexed basic: shortest cost + valid path" {
  // 0 →(1) 1 →(1) 2；0 →(5) 2：最短 0→1→2 代价 2。
  let g = @directed.WeightedCsr::from_edges(3, [(0, 1, 1), (1, 2, 1), (0, 2, 5)])
  match @directed.dijkstra_indexed(g, 0, 2) {
    Some((path, cost)) => {
      assert_eq(cost, 2)
      @debug.debug_inspect(path, content="[0, 1, 2]")
    }
    None => abort("expected reachable")
  }
  // 不可达 / 自身。
  assert_true(@directed.dijkstra_indexed(g, 2, 0) is None)
  match @directed.dijkstra_indexed(g, 1, 1) {
    Some((path, cost)) => {
      assert_eq(cost, 0)
      @debug.debug_inspect(path, content="[1]")
    }
    None => abort("self must be reachable")
  }
  // 越界起终点。
  assert_true(@directed.dijkstra_indexed(g, -1, 2) is None)
  assert_true(@directed.dijkstra_indexed(g, 0, 3) is None)
}

///|
test "dijkstra_indexed differential PBT vs generic Map-based (150 iterations)" {
  let rng = @infra_pbt.rng_new(0xD1_57A6_5EUL)
  for _iter in 0..<150 {
    let n = 2 + rng.next_below(60)
    let m = rng.next_below(n * 4)
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v, 1 + rng.next_below(100)))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_i) { [] })
    for e in edges {
      let (u, v, w) = e
      adj[u].push((v, w))
    }
    for _q in 0..<8 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let fast = @directed.dijkstra_indexed(g, s, t)
      let slow = @directed.dijkstra(s, fn(node) { adj[node] }, fn(node) {
        node == t
      })
      match (fast, slow) {
        (Some((fpath, fcost)), Some((_spath, scost))) => {
          assert_eq(fcost, scost)
          // 路径合法性：首尾正确、每步是真实边、代价求和一致。
          assert_eq(fpath[0], s)
          assert_eq(fpath[fpath.length() - 1], t)
          let mut acc = 0
          for i in 0..<(fpath.length() - 1) {
            let mut found = -1
            for pr in adj[fpath[i]] {
              let (v, w) = pr
              if v == fpath[i + 1] && (found < 0 || w < found) {
                found = w
              }
            }
            assert_true(found >= 0)
            acc = acc + found
          }
          assert_true(acc <= scost || fpath.length() == 1)
        }
        (None, None) => ()
        _ => abort("reachability mismatch")
      }
    }
  }
}

///|
test "astar_indexed with zero heuristic equals dijkstra_indexed (80 iterations)" {
  let rng = @infra_pbt.rng_new(0xA5_7A12UL)
  for _iter in 0..<80 {
    let n = 2 + rng.next_below(40)
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<rng.next_below(n * 3) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v, 1 + rng.next_below(50)))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let s = rng.next_below(n)
    let t = rng.next_below(n)
    let a = @directed.astar_indexed(g, s, t, fn(_node) { 0 })
    let d = @directed.dijkstra_indexed(g, s, t)
    match (a, d) {
      (Some((_, ac)), Some((_, dc))) => assert_eq(ac, dc)
      (None, None) => ()
      _ => abort("astar/dijkstra reachability mismatch")
    }
  }
}
