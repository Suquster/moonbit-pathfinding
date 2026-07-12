// 黑盒测试：覆盖率审计收口（INFRA 第七十五批）——
// 目标端点缺失报错与 OSM 空白内容/过小回退维度的合成降级。

///|
test "typed_bfs_path/typed_shortest_path：目标不在节点集即报 TargetNotFound" {
  let nodes = [1, 2]
  assert_true(
    @graph.typed_bfs_path(nodes, 1, 99, fn(_n) { [] })
    is Err(@graph.TargetNotFound),
  )
  assert_true(
    @graph.typed_shortest_path(nodes, 1, 99, fn(_n) { ([] : Array[(Int, Int)]) })
    is Err(@graph.TargetNotFound),
  )
}

///|
test "load_osm_or_synthetic：空白内容与过小回退维度均走合成降级" {
  let out = @graph.load_osm_or_synthetic(Some("   \n\t"), 0)
  assert_true(out.node_count > 0)
  assert_true(out.diagnostic.length() > 0)
}
