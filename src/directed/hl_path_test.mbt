// hl_path_test.mbt —— HL 路径还原黑盒测试：与 Dijkstra 差分 PBT
// （距离最优 + 路径合法性逐边校验）。

///|
test "HL query_path 基本用例" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let hl = @directed.HubLabels::build(ch)
  match hl.query_path(ch, 0, 3) {
    Some((path, d)) => {
      assert_eq(d, 9L)
      assert_eq(path[0], 0)
      assert_eq(path[path.length() - 1], 3)
    }
    None => abort("expected path")
  }
  assert_true(hl.query_path(ch, 3, 0) is None)
}

///|
test "HL query_path 差分 PBT：距离最优 + 路径合法（80 迭代）" {
  let rng = @infra_pbt.rng_new(0x41_9A7_2026UL)
  for it in 0..<80 {
    let n = 2 + rng.next_below(40)
    let m = rng.next_below(4 * n + 1)
    let big = it % 3 == 0
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let v = rng.next_below(n)
      let w = if big {
        1 + rng.next_below(100000) * 79
      } else {
        1 + rng.next_below(64)
      }
      edges.push((u, v, w))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ch = @directed.ContractionHierarchy::build(g)
    let hl = @directed.HubLabels::build(ch)
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<5 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let expect = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
      match (expect, hl.query_path(ch, s, t)) {
        (Some((_, ec)), Some((path, d))) => {
          assert_eq(d, ec.to_int64())
          assert_eq(path[0], s)
          assert_eq(path[path.length() - 1], t)
          // 逐边存在且权和 = 代价。
          let mut sum = 0L
          for i = 0; i + 1 < path.length(); i = i + 1 {
            let u = path[i]
            let v = path[i + 1]
            let mut best = -1
            let stop = g.offsets[u + 1]
            for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
              if g.targets[ei] == v && (best < 0 || g.weights[ei] < best) {
                best = g.weights[ei]
              }
            }
            assert_true(best >= 0)
            sum = sum + best.to_int64()
          }
          assert_eq(sum, d)
        }
        (None, None) => ()
        _ => abort("reachability mismatch")
      }
    }
  }
}
