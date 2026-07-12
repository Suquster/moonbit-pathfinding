// 黑盒测试：覆盖率审计收口（INFRA 第七十五批）——
// 索引化最短路四个入口的端点越界拒绝。

///|
test "indexed 搜索：起终点越界一律返回 None" {
  let g = @directed.WeightedCsr::from_edges(3, [(0, 1, 1), (1, 2, 1)])
  let h = fn(_n : Int) { 0 }
  assert_true(@directed.astar_indexed(g, -1, 2, h) is None)
  assert_true(@directed.astar_indexed(g, 0, 3, h) is None)
  let cf = @directed.SearchCtx::new(3)
  let cb = @directed.SearchCtx::new(3)
  assert_true(@directed.dijkstra_bidirectional_ctx(g, g, cf, cb, -1, 2) is None)
  assert_true(
    @directed.astar_bidirectional_ctx(g, g, cf, cb, 0, 99, h, h) is None,
  )
  assert_true(@directed.astar_indexed_ctx(g, cf, 5, 0, h) is None)
}
