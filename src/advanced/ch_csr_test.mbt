// ch_csr_test.mbt —— 生产级 CSR CH 的差分正确性验证（任务 19.1）。
//
// 验证策略（与 `ch_test.mbt` 同源的差分对拍，规模面向 CSR 特化版）：
//   * **代价一致**：`ch_csr_query` 的最短代价与基线 `@dir.dijkstra`
//     逐位相等（边权取小整数值的 Double，加法在任意顺序下均精确）。
//   * **路径合法**：展开后的路径首尾正确、逐边存在于原图、且逐边权重
//     和与返回代价逐位相等（捷径展开的「权重精确匹配」不变量）。
//   * **不可达一致**：基线不可达 ⇔ CH 查询返回 `None`。
//   * **对抗拓扑**：自环、平行边、非连通分量、单节点均安全。
//   * **随机图 PBT**：LCG 驱动的 30 张随机有向图 × 多查询全对拍。

///|
/// 自包含线性同余发生器（与各 `*_bench` 一致，三后端逐元素可复现）。
priv struct CsrTestLcg {
  mut state : Int
}

///|
fn CsrTestLcg::new(seed : Int) -> CsrTestLcg {
  let s = if seed <= 0 { (-seed).lor(1) } else { seed }
  { state: s.land(0x7fffffff) }
}

///|
fn CsrTestLcg::next(self : CsrTestLcg) -> Int {
  let v = (self.state * 1103515245 + 12345).land(0x7fffffff)
  self.state = v
  v
}

///|
/// 由边表物化 CSR 图（两趟计数/填充，保持输入次序稳定）。
fn build_csr(
  n : Int,
  edges : Array[(Int, Int, Double)],
) -> @graph.CsrGraph[Double] {
  let cnt : Array[Int] = Array::make(n, 0)
  for e in edges {
    cnt[e.0] = cnt[e.0] + 1
  }
  let row_ptr : Array[Int] = Array::make(n + 1, 0)
  for i in 0..<n {
    row_ptr[i + 1] = row_ptr[i] + cnt[i]
  }
  let m = row_ptr[n]
  let col_idx : Array[Int] = Array::make(m, 0)
  let weights : Array[Double] = Array::make(m, 0.0)
  let fill : Array[Int] = Array::make(n, 0)
  for e in edges {
    let (u, v, w) = e
    let k = row_ptr[u] + fill[u]
    col_idx[k] = v
    weights[k] = w
    fill[u] = fill[u] + 1
  }
  { n, row_ptr, col_idx, weights }
}

///|
/// CSR 图的后继闭包（供基线 Dijkstra 使用）。
fn csr_successors(g : @graph.CsrGraph[Double]) -> (Int) -> Array[(Int, Double)] {
  fn(u : Int) -> Array[(Int, Double)] {
    let out : Array[(Int, Double)] = []
    if u >= 0 && u < g.n {
      for k in g.row_ptr[u]..<g.row_ptr[u + 1] {
        out.push((g.col_idx[k], g.weights[k]))
      }
    }
    out
  }
}

///|
/// 断言一条路径在原图上合法且逐边权重和与 `cost` 逐位相等。
fn assert_valid_path(
  g : @graph.CsrGraph[Double],
  path : Array[Int],
  source : Int,
  target : Int,
  cost : Double,
) -> Unit raise {
  assert_true(path.length() >= 1)
  @test.assert_eq(path[0], source)
  @test.assert_eq(path[path.length() - 1], target)
  let mut total = 0.0
  for i in 0..<(path.length() - 1) {
    let u = path[i]
    let v = path[i + 1]
    // 取 u -> v 的最小平行边权（Dijkstra 松弛等价于取最小平行边）。
    let mut best = -1.0
    for k in g.row_ptr[u]..<g.row_ptr[u + 1] {
      if g.col_idx[k] == v {
        if best < 0.0 || g.weights[k] < best {
          best = g.weights[k]
        }
      }
    }
    assert_true(best >= 0.0)
    total = total + best
  }
  @test.assert_eq(total, cost)
}

///|
/// 在给定 CSR 图上对拍 `query_pairs` 组查询：代价逐位一致 + 路径合法 +
/// 不可达一致。
fn differential_check(
  g : @graph.CsrGraph[Double],
  ch : @advanced.ChCsr,
  pairs : Array[(Int, Int)],
) -> Unit raise {
  let succ = csr_successors(g)
  for p in pairs {
    let (s, t) = p
    let base = @dir.dijkstra(s, succ, fn(x : Int) { x == t })
    let got = @advanced.ch_csr_query(ch, s, t)
    // 代价查询（无路径）与全查询/基线三方对拍。
    let got_cost = @advanced.ch_csr_query_cost(ch, s, t)
    match (base, got) {
      (Some((_, bcost)), Some((path, cost))) => {
        @test.assert_eq(cost, bcost)
        @test.assert_eq(got_cost, Some(bcost))
        assert_valid_path(g, path, s, t, cost)
      }
      (None, None) => @test.assert_eq(got_cost, None)
      (Some(_), None) => {
        println("CH 漏报可达: \{s} -> \{t}")
        assert_true(false)
      }
      (None, Some(_)) => {
        println("CH 误报可达: \{s} -> \{t}")
        assert_true(false)
      }
    }
  }
}

///|
/// 构造带确定性随机小整数权的 `side × side` 4-连通无向网格 CSR。
fn build_weighted_grid(seed : Int, side : Int) -> @graph.CsrGraph[Double] {
  let rng = CsrTestLcg::new(seed)
  let edges : Array[(Int, Int, Double)] = []
  for r in 0..<side {
    for c in 0..<side {
      let u = r * side + c
      if c + 1 < side {
        let w = (1 + rng.next() % 9).to_double()
        edges.push((u, u + 1, w))
        edges.push((u + 1, u, w))
      }
      if r + 1 < side {
        let w = (1 + rng.next() % 9).to_double()
        edges.push((u, u + side, w))
        edges.push((u + side, u, w))
      }
    }
  }
  build_csr(side * side, edges)
}

///|
test "ch_csr: 加权网格全差分（代价逐位一致 + 路径合法）" {
  let side = 10
  let g = build_weighted_grid(20240607, side)
  let ch = @advanced.ch_csr_preprocess(g)
  let rng = CsrTestLcg::new(911)
  let pairs : Array[(Int, Int)] = [(0, side * side - 1), (0, 0)]
  for _ in 0..<40 {
    pairs.push((rng.next() % (side * side), rng.next() % (side * side)))
  }
  differential_check(g, ch, pairs)
}

///|
test "ch_csr: 非连通分量与单节点安全（不可达一致）" {
  // 两个互不连通的三角形 + 一个孤立节点。
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0),
    (1, 2, 2.0),
    (2, 0, 3.0),
    (3, 4, 1.0),
    (4, 5, 2.0),
    (5, 3, 3.0),
  ]
  let g = build_csr(7, edges)
  let ch = @advanced.ch_csr_preprocess(g)
  let pairs : Array[(Int, Int)] = [
    (0, 2),
    (2, 1),
    (0, 3),
    (3, 0),
    (5, 4),
    (6, 6),
    (0, 6),
    (6, 1),
  ]
  differential_check(g, ch, pairs)
  // 越界安全：返回 None 而非崩溃。
  assert_true(@advanced.ch_csr_query(ch, -1, 0) is None)
  assert_true(@advanced.ch_csr_query(ch, 0, 7) is None)
}

///|
test "ch_csr: 自环与平行边不产生退化捷径" {
  let edges : Array[(Int, Int, Double)] = [
    (0, 0, 1.0), // 自环
    (0, 1, 5.0),
    (0, 1, 2.0), // 平行边（更优）
    (1, 2, 3.0),
    (1, 2, 7.0), // 平行边（更劣）
    (2, 3, 1.0),
    (0, 3, 100.0), // 会被多跳路径完胜的直边
    (3, 3, 4.0), // 自环
  ]
  let g = build_csr(4, edges)
  let ch = @advanced.ch_csr_preprocess(g)
  let pairs : Array[(Int, Int)] = [(0, 3), (0, 2), (1, 3), (0, 1), (3, 0)]
  differential_check(g, ch, pairs)
}

///|
test "ch_csr: 随机有向图 PBT 全对拍（30 图 × 8 查询）" {
  let rng = CsrTestLcg::new(424242)
  for gi in 0..<30 {
    let n = 2 + rng.next() % 28
    let m = n * 2 + rng.next() % (n + 1)
    let edges : Array[(Int, Int, Double)] = []
    for _ in 0..<m {
      let u = rng.next() % n
      let v = rng.next() % n
      let w = (1 + rng.next() % 9).to_double()
      edges.push((u, v, w))
    }
    let g = build_csr(n, edges)
    let ch = @advanced.ch_csr_preprocess(g)
    let pairs : Array[(Int, Int)] = []
    for _ in 0..<8 {
      pairs.push((rng.next() % n, rng.next() % n))
    }
    ignore(gi)
    differential_check(g, ch, pairs)
  }
}
