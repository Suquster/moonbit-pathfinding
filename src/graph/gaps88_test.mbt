// gaps88_test.mbt —— OSM 加载降级余臂（第八十八批）。

///|
/// 仅含表头、无有效边的内容：解析成功但 n=0 → 降级合成网格。
test "load_osm_or_synthetic：仅表头无有效边降级" {
  let outcome = @graph.load_osm_or_synthetic(Some("src dst weight\n"), 8)
  assert_true(outcome.source is SyntheticFallback)
  assert_true(outcome.diagnostic.contains("无有效边"))
  assert_true(outcome.node_count > 0)
}
