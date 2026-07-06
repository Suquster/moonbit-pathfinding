// cch_test.mbt —— Customizable CH 黑盒测试：距离与 Dijkstra 差分 PBT，
// 核心场景是**换权重后 customize 再对拍**（CCH 相对 CH 的价值所在）。

///|
test "CustomizableCch basic: chain with recustomization" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let cch = @directed.CustomizableCch::build(g)
  assert_true(cch.query_dist(0, 3) is Some(9L))
  assert_true(cch.query_dist(3, 0) is None)
  assert_true(cch.query_dist(2, 2) is Some(0L))
  // 换权重（同拓扑）：直连边变便宜，链路变贵。
  let edges2 : Array[(Int, Int, Int)] = [
    (0, 1, 20),
    (1, 2, 30),
    (2, 3, 40),
    (0, 3, 10),
  ]
  let g2 = @directed.WeightedCsr::from_edges(4, edges2)
  cch.customize(g2)
  assert_true(cch.query_dist(0, 3) is Some(10L))
  assert_true(cch.query_dist(0, 2) is Some(50L))
}

///|
test "CustomizableCch differential PBT vs dijkstra (100 iterations, 含换权重 customize 再对拍)" {
  let rng = @infra_pbt.rng_new(0xCC_47AC7UL)
  for iter in 0..<100 {
    let n = 2 + rng.next_below(50)
    let m = rng.next_below(n * 3)
    let us : Array[Int] = []
    let vs : Array[Int] = []
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      if v == u {
        v = (u + 1) % n
      }
      us.push(u)
      vs.push(v)
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
    let cch = @directed.CustomizableCch::build(g)
    // 嵌套剖分序变体：同图另一收缩序，结果必须与 min-degree 版一致。
    let cch_nd = @directed.CustomizableCch::build_with_order(
      g,
      @directed.cch_nd_order(g),
    )
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let expect = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
      let got = cch.query_dist(s, t)
      match (expect, got) {
        (Some((_, ec)), Some(gc)) => assert_eq(gc, ec.to_int64())
        (None, None) => ()
        _ => abort("reachability mismatch (initial customize)")
      }
      let got_nd = cch_nd.query_dist(s, t)
      match (expect, got_nd) {
        (Some((_, ec)), Some(gc)) => assert_eq(gc, ec.to_int64())
        (None, None) => ()
        _ => abort("reachability mismatch (nd order)")
      }
    }
    // 同拓扑换权重：只跑 customize（不重建），再与 Dijkstra 对拍。
    let edges2 : Array[(Int, Int, Int)] = []
    for i = 0; i < m; i = i + 1 {
      edges2.push((us[i], vs[i], 1 + rng.next_below(500)))
    }
    let g2 = @directed.WeightedCsr::from_edges(n, edges2)
    cch.customize(g2)
    cch_nd.customize(g2)
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let expect = @directed.dijkstra_indexed_ctx(g2, ctx, s, t)
      let got = cch.query_dist(s, t)
      match (expect, got) {
        (Some((_, ec)), Some(gc)) => assert_eq(gc, ec.to_int64())
        (None, None) => ()
        _ => abort("reachability mismatch (recustomize)")
      }
      let got_nd = cch_nd.query_dist(s, t)
      match (expect, got_nd) {
        (Some((_, ec)), Some(gc)) => assert_eq(gc, ec.to_int64())
        (None, None) => ()
        _ => abort("reachability mismatch (nd recustomize)")
      }
    }
  }
}
