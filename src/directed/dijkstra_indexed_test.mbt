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

///|
test "dijkstra_indexed_ctx differential PBT vs dijkstra_indexed (120 iterations, ctx reused)" {
  let rng = @infra_pbt.rng_new(0xC7_D115UL)
  for _iter in 0..<120 {
    let n = 2 + rng.next_below(50)
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<rng.next_below(n * 3) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v, 1 + rng.next_below(100)))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ctx = @directed.SearchCtx::new(n)
    // 同一 ctx 连续复用多条查询：generation 戳必须彻底隔离前后查询状态。
    for _q in 0..<10 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let a = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
      let b = @directed.dijkstra_indexed(g, s, t)
      match (a, b) {
        (Some((pa, ca)), Some((pb, cb))) => {
          assert_eq(ca, cb)
          assert_eq(pa[0], pb[0])
          assert_eq(pa[pa.length() - 1], t)
        }
        (None, None) => ()
        _ => abort("ctx/plain reachability mismatch")
      }
    }
  }
}

///|
test "astar_indexed_ctx differential PBT vs astar_indexed (100 iterations, ctx reused)" {
  let rng = @infra_pbt.rng_new(0xA5_C7C5UL)
  for _iter in 0..<100 {
    let n = 2 + rng.next_below(50)
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<rng.next_below(n * 3) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v, 1 + rng.next_below(100)))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<8 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let a = @directed.astar_indexed_ctx(g, ctx, s, t, fn(_node) { 0 })
      let b = @directed.astar_indexed(g, s, t, fn(_node) { 0 })
      match (a, b) {
        (Some((_, ca)), Some((_, cb))) => assert_eq(ca, cb)
        (None, None) => ()
        _ => abort("ctx/plain astar reachability mismatch")
      }
    }
  }
}

///|
test "dijkstra_indexed_ctx Dial vs heap paths agree on large weights (60 iterations)" {
  // 边权含 > 1024 的用例走 4 叉堆路径；≤ 1024 走 Dial——两路径与
  // 无 ctx 参照必须一致。
  let rng = @infra_pbt.rng_new(0xD1A1UL)
  for _iter in 0..<60 {
    let n = 2 + rng.next_below(40)
    let big = _iter % 2 == 0
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<rng.next_below(n * 3) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      let w = if big {
        1 + rng.next_below(100000)
      } else {
        1 + rng.next_below(30)
      }
      edges.push((u, v, w))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let a = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
      let b = @directed.dijkstra_indexed(g, s, t)
      match (a, b) {
        (Some((_, ca)), Some((_, cb))) => assert_eq(ca, cb)
        (None, None) => ()
        _ => abort("dial/heap reachability mismatch")
      }
    }
  }
}

///|
test "astar_indexed_ctx bucket path with perfect (consistent) heuristic PBT (80 iterations)" {
  // 完美启发式 h(v) = dist(v, t)（一致），走桶式 Dial A* 路径；
  // 与无 ctx 堆版 astar_indexed 差分。
  let rng = @infra_pbt.rng_new(0xBEEF_A5UL)
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
    let t = rng.next_below(n)
    // 反图上从 t 跑 Dijkstra 得每点到 t 的真实距离（完美一致启发式）。
    let redges : Array[(Int, Int, Int)] = []
    for e in edges {
      let (u, v, w) = e
      redges.push((v, u, w))
    }
    let rg = @directed.WeightedCsr::from_edges(n, redges)
    let hdist : Array[Int] = Array::make(n, 0)
    for v in 0..<n {
      match @directed.dijkstra_indexed(rg, t, v) {
        Some((_, c)) => hdist[v] = c
        // 不可达节点只可能连向不可达节点（否则它就可达），
        // 大常数在这类节点间仍满足一致性 h(u) ≤ w + h(v)。
        None => hdist[v] = 1000000
      }
    }
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let a = @directed.astar_indexed_ctx(g, ctx, s, t, fn(v) { hdist[v] })
      let b = @directed.astar_indexed(g, s, t, fn(v) { hdist[v] })
      match (a, b) {
        (Some((pa, ca)), Some((_, cb))) => {
          assert_eq(ca, cb)
          assert_eq(pa[0], s)
          assert_eq(pa[pa.length() - 1], t)
        }
        (None, None) => ()
        _ => abort("bucket/heap astar reachability mismatch")
      }
    }
  }
}

///|
test "dijkstra_bidirectional_ctx differential PBT vs dijkstra_indexed (150 iterations)" {
  let rng = @infra_pbt.rng_new(0xB1D1D1UL)
  for _iter in 0..<150 {
    let n = 2 + rng.next_below(50)
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<rng.next_below(n * 3) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v, 1 + rng.next_below(60)))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let redges : Array[(Int, Int, Int)] = []
    for e in edges {
      let (u, v, w) = e
      redges.push((v, u, w))
    }
    let rg = @directed.WeightedCsr::from_edges(n, redges)
    let cf = @directed.SearchCtx::new(n)
    let cb = @directed.SearchCtx::new(n)
    for _q in 0..<8 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let a = @directed.dijkstra_bidirectional_ctx(g, rg, cf, cb, s, t)
      let b = @directed.dijkstra_indexed(g, s, t)
      match (a, b) {
        (Some((pa, ca)), Some((_, cb2))) => {
          assert_eq(ca, cb2)
          assert_eq(pa[0], s)
          assert_eq(pa[pa.length() - 1], t)
          // 路径逐边合法 + 边权和等于代价。
          let mut sum = 0
          for i in 0..<(pa.length() - 1) {
            let u = pa[i]
            let v = pa[i + 1]
            let mut wt = -1
            let stop = g.offsets[u + 1]
            for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
              if g.targets[ei] == v {
                if wt < 0 || g.weights[ei] < wt {
                  wt = g.weights[ei]
                }
              }
            }
            assert_true(wt >= 0)
            sum = sum + wt
          }
          assert_eq(sum, ca)
        }
        (None, None) => ()
        _ =>
          abort("bidirectional/unidirectional dijkstra reachability mismatch")
      }
    }
  }
}

///|
test "astar_bidirectional_ctx differential PBT vs astar_indexed (120 iterations, zero + perfect h, Dial + heap 权域)" {
  let rng = @infra_pbt.rng_new(0xB1A5UL)
  for _iter in 0..<120 {
    let n = 2 + rng.next_below(50)
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<rng.next_below(n * 3) {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      edges.push(
        (
          u,
          v,
          if _iter % 3 == 2 {
            1 + rng.next_below(60) + 2000 // 大权：走 NBA* 编码堆分支
          } else {
            1 + rng.next_below(60) // 小权：走桶式 Dial 分支
          },
        ),
      )
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let redges : Array[(Int, Int, Int)] = []
    for e in edges {
      let (u, v, w) = e
      redges.push((v, u, w))
    }
    let rg = @directed.WeightedCsr::from_edges(n, redges)
    let cf = @directed.SearchCtx::new(n)
    let cb = @directed.SearchCtx::new(n)
    let use_perfect = _iter % 2 == 0
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      // 完美一致启发式：h_f(v)=dist(v,t)（反图从 t）、h_b(v)=dist(s,v)（正图从 s）。
      let hf : Array[Int] = Array::make(n, 0)
      let hb : Array[Int] = Array::make(n, 0)
      if use_perfect {
        for v in 0..<n {
          match @directed.dijkstra_indexed(rg, t, v) {
            Some((_, c)) => hf[v] = c
            None => hf[v] = 1000000
          }
          match @directed.dijkstra_indexed(g, s, v) {
            Some((_, c)) => hb[v] = c
            None => hb[v] = 1000000
          }
        }
      }
      let a = @directed.astar_bidirectional_ctx(
        g,
        rg,
        cf,
        cb,
        s,
        t,
        fn(v) { hf[v] },
        fn(v) { hb[v] },
      )
      let b = @directed.astar_indexed(g, s, t, fn(_v) { 0 })
      match (a, b) {
        (Some((pa, ca)), Some((_, cb2))) => {
          assert_eq(ca, cb2)
          assert_eq(pa[0], s)
          assert_eq(pa[pa.length() - 1], t)
          let mut sum = 0
          for i in 0..<(pa.length() - 1) {
            let u = pa[i]
            let v = pa[i + 1]
            let mut wt = -1
            let stop = g.offsets[u + 1]
            for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
              if g.targets[ei] == v {
                if wt < 0 || g.weights[ei] < wt {
                  wt = g.weights[ei]
                }
              }
            }
            assert_true(wt >= 0)
            sum = sum + wt
          }
          assert_eq(sum, ca)
        }
        (None, None) => ()
        _ => abort("bidirectional/plain astar reachability mismatch")
      }
    }
  }
}
