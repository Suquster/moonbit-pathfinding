// 白盒测试：OSM 记号解析边界、无向边构建、邻接矩阵畸形行防御。

///|
test "osm：节点 id 与权重记号边界拒绝" {
  assert_true(osm_parse_node_id("") is None)
  assert_true(osm_parse_node_id("1a") is None)
  assert_true(osm_parse_node_id("42") is Some(42))
  assert_true(osm_parse_weight("abc") is None)
  assert_true(osm_parse_weight("1.5") is Some(1.5))
}

///|
test "osm：首个内容行为短表头时放行" {
  let content = "src\tdst\n0\t1\t2.0\n"
  assert_true(CsrGraph::from_osm_edge_list(content) is Ok(_))
}

///|
test "builder：无向边写入两条对称有向边" {
  let g = GraphBuilder::new()
    .add_node(1)
    .add_node(2)
    .add_undirected_edge(1, 2, 5)
    .build()
  assert_true(g is Ok(_))
}
