// ch_test.mbt —— Contraction Hierarchies 黑盒测试：代价与 Dijkstra
// 差分 PBT（含大/小权、不可达、路径合法性逐边校验）。

///|
test "ContractionHierarchy basic: chain with shortcut" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  match ch.query(0, 3) {
    Some((path, c)) => {
      assert_eq(c, 9)
      assert_true(path == [0, 1, 2, 3])
    }
    None => abort("expected reachable")
  }
  assert_true(ch.query(3, 0) is None)
  match ch.query(2, 2) {
    Some((path, c)) => {
      assert_eq(c, 0)
      assert_true(path == [2])
    }
    None => abort("expected trivial")
  }
}

///|
test "ContractionHierarchy differential PBT vs dijkstra (120 iterations, 大/小权 + 路径合法性)" {
  let rng = @infra_pbt.rng_new(0xC0_47AC7UL)
  for iter in 0..<120 {
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
          if iter % 3 == 2 {
            1 + rng.next_below(60) + 2000
          } else {
            1 + rng.next_below(60)
          },
        ),
      )
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ch = @directed.ContractionHierarchy::build(g)
    // 邻接查询表：路径合法性校验用。
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let expect = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
      let got = ch.query(s, t)
      match (expect, got) {
        (Some((_, ec)), Some((path, gc))) => {
          assert_eq(gc, ec)
          // 路径合法：首尾正确、逐边存在且权和 = 代价。
          assert_eq(path[0], s)
          assert_eq(path[path.length() - 1], t)
          let mut sum = 0
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
            sum = sum + best
          }
          assert_eq(sum, ec)
        }
        (None, None) => ()
        _ => abort("reachability mismatch")
      }
    }
  }
}
