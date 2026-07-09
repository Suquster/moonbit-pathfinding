// 黑盒测试：ALT 地标启发式闭包、一到全 Dijkstra、索引化搜索越界防御。

///|
fn cg3_csr() -> WeightedCsr {
  WeightedCsr::from_edges(4, [(0, 1, 2), (1, 2, 3), (2, 3, 1), (0, 3, 9)])
}

///|
test "alt：h_to/h_from 闭包非负且不超过真实距离" {
  let g = cg3_csr()
  let rg = WeightedCsr::from_edges(4, [
    (1, 0, 2),
    (2, 1, 3),
    (3, 2, 1),
    (3, 0, 9),
  ])
  let lm = AltLandmarks::build(g, rg, 2)
  let h_to = lm.h_to_closure(3)
  let h_from = lm.h_from_closure(0)
  assert_true(h_to(0) >= 0 && h_to(0) <= 6)
  assert_true(h_to(3) == 0)
  assert_true(h_from(0) == 0)
  assert_true(h_from(3) >= 0 && h_from(3) <= 6)
}

///|
test "alt：dijkstra_one_to_all 全量距离" {
  let g = cg3_csr()
  let dist : Array[Int64] = Array::make(4, 0L)
  dijkstra_one_to_all(g, 0, dist)
  assert_eq(dist[0], 0L)
  assert_eq(dist[1], 2L)
  assert_eq(dist[2], 5L)
  assert_eq(dist[3], 6L)
}

///|
test "dijkstra_indexed_ctx：端点越界直返 None" {
  let g = cg3_csr()
  let ctx = SearchCtx::new(4)
  assert_true(dijkstra_indexed_ctx(g, ctx, -1, 3) is None)
  assert_true(dijkstra_indexed_ctx(g, ctx, 0, 9) is None)
  assert_true(dijkstra_indexed_ctx(g, ctx, 0, 3) is Some(_))
}
