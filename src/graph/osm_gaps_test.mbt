// osm_gaps_test.mbt —— OSM 边表解析与合成网格参数校验收口
// （INFRA 第二十四批）。

///|
test "from_osm_edge_list：负权与 NaN 权拒绝" {
  assert_true(CsrGraph::from_osm_edge_list("0\t1\t-2.5") is Err(_))
  assert_true(CsrGraph::from_osm_edge_list("0\t1\tnan") is Err(_))
}

///|
test "from_osm_edge_list：表头跳过一次，后续畸形行报错" {
  // 首个内容行首字段非数字 → 表头跳过。
  match CsrGraph::from_osm_edge_list("src\tdst\tweight\n0\t1\t2.0") {
    Ok(g) => assert_true(g.n >= 2)
    Err(_) => assert_true(false)
  }
  // 非首行的畸形字段 → 结构化报错。
  assert_true(
    CsrGraph::from_osm_edge_list("0\t1\t2.0\nfoo\tbar\t1.0") is Err(_),
  )
}

///|
test "synthetic_grid_csr：非法行列与权重拒绝" {
  assert_true(synthetic_grid_csr(0, 3, 1.0) is Err(_))
  assert_true(synthetic_grid_csr(3, -1, 1.0) is Err(_))
  assert_true(synthetic_grid_csr(2, 2, -1.0) is Err(_))
  assert_true(synthetic_grid_csr(2, 2, 1.0) is Ok(_))
}
