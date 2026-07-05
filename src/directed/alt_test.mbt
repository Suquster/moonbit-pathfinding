// alt_test.mbt —— ALT 地标启发式黑盒测试：下界可采纳性 + 一致性 +
// 与 Dijkstra 的差分 PBT（ALT 喂给单向/双向 A* 代价均最优）。

///|
test "AltLandmarks basic: bounds admissible and astar optimal" {
  // 链 0→1→2→3 加一条捷径 0→3(10)。
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let redges : Array[(Int, Int, Int)] = []
  for e in edges {
    let (u, v, w) = e
    redges.push((v, u, w))
  }
  let rg = @directed.WeightedCsr::from_edges(4, redges)
  let alt = @directed.AltLandmarks::build(g, rg, 2)
  // 下界不超过真实距离：dist(0,3)=9。
  assert_true(alt.h_to(0, 3) <= 9)
  assert_true(alt.h_to(0, 3) >= 0)
  let ctx = @directed.SearchCtx::new(4)
  match @directed.astar_indexed_ctx(g, ctx, 0, 3, fn(v) { alt.h_to(v, 3) }) {
    Some((_, c)) => assert_eq(c, 9)
    None => abort("expected reachable")
  }
}

///|
test "AltLandmarks differential PBT vs dijkstra (100 iterations, 单向 + 双向, Dial + heap 权域)" {
  let rng = @infra_pbt.rng_new(0xA17_1A2DUL)
  for _iter in 0..<100 {
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
            1 + rng.next_below(60) + 2000 // 大权：heap 分支
          } else {
            1 + rng.next_below(60) // 小权：Dial 分支
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
    let alt = @directed.AltLandmarks::build(g, rg, 1 + rng.next_below(4))
    let cf = @directed.SearchCtx::new(n)
    let cb = @directed.SearchCtx::new(n)
    let ctx = @directed.SearchCtx::new(n)
    for _q in 0..<6 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let oracle = @directed.dijkstra_indexed(g, s, t)
      // 可采纳性：下界 ≤ 真实距离。
      match oracle {
        Some((_, c)) => {
          assert_true(alt.h_to(s, t) <= c)
          assert_true(alt.h_from(t, s) <= c)
        }
        None => ()
      }
      // 一致性（逐边）：h(u) ≤ w(u,v) + h(v)。
      for e in edges {
        let (u, v, w) = e
        assert_true(alt.h_to(u, t) <= w + alt.h_to(v, t))
        assert_true(alt.h_from(v, s) <= w + alt.h_from(u, s))
      }
      // 单向 A* + ALT 与 Dijkstra 代价一致。
      let a1 = @directed.astar_indexed_ctx(g, ctx, s, t, fn(v) {
        alt.h_to(v, t)
      })
      // 双向 A* + ALT 与 Dijkstra 代价一致。
      let a2 = @directed.astar_bidirectional_ctx(
        g,
        rg,
        cf,
        cb,
        s,
        t,
        fn(v) { alt.h_to(v, t) },
        fn(v) { alt.h_from(v, s) },
      )
      match (oracle, a1, a2) {
        (Some((_, c)), Some((p1, c1)), Some((p2, c2))) => {
          assert_eq(c1, c)
          assert_eq(c2, c)
          assert_eq(p1[0], s)
          assert_eq(p1[p1.length() - 1], t)
          assert_eq(p2[0], s)
          assert_eq(p2[p2.length() - 1], t)
        }
        (None, None, None) => ()
        _ => abort("ALT astar reachability mismatch vs dijkstra")
      }
    }
  }
}
