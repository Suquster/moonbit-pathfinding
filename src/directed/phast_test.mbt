// phast_test.mbt —— PHAST 黑盒测试：基本用例 + 与 Dijkstra 的
// 一到全差分 PBT（大/小权、不可达全对拍）。

///|
test "PHAST 基本链 + 不可达" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let dist = Array::make(4, 0L)
  ch.one_to_all(0, dist)
  assert_eq(dist[0], 0L)
  assert_eq(dist[1], 2L)
  assert_eq(dist[2], 5L)
  assert_eq(dist[3], 9L)
  ch.one_to_all(3, dist)
  assert_eq(dist[3], 0L)
  assert_true(@directed.ContractionHierarchy::is_unreachable(dist[0]))
}

///|
test "PHAST 差分 PBT：随机图一到全 vs Dijkstra 全对拍（80 迭代）" {
  let rng = @infra_pbt.rng_new(0xF457_2026UL)
  for it in 0..<80 {
    let n = 2 + rng.next_below(40)
    let m = rng.next_below(4 * n + 1)
    let big = it % 3 == 0
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let v = rng.next_below(n)
      let w = if big {
        1 + rng.next_below(100000) * 97
      } else {
        1 + rng.next_below(64)
      }
      edges.push((u, v, w))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ch = @directed.ContractionHierarchy::build(g)
    let ctx = @directed.SearchCtx::new(n)
    let dist = Array::make(n, 0L)
    let s = rng.next_below(n)
    ch.one_to_all(s, dist)
    for t in 0..<n {
      match @directed.dijkstra_indexed_ctx(g, ctx, s, t) {
        Some((_, c)) => assert_eq(c.to_int64(), dist[t])
        None =>
          assert_true(@directed.ContractionHierarchy::is_unreachable(dist[t]))
      }
    }
  }
}
