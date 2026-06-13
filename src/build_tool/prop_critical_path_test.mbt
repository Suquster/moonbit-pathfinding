// prop_critical_path_test.mbt —— Property 12：关键路径等于最小批次层数。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag；校验 DAG 最长路径（节点数）
// 等于不限并行度（jobs<=0，整层一批）下的批次层数。

///|
/// Feature: build-tool, Property 12: 关键路径等于最小批次层数
///
/// 对任意无环构建图，关键路径长度等于不限并行度（`jobs <= 0`）下完成构建所需
/// 的批次层数：`critical_path_length(g) == len(schedule(g, 0))`。
///
/// **Validates: Requirements 7.3, 7.4**
test "Feature: build-tool, Property 12: critical-path equals minimal layers" {
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    critical_path_length(g) == schedule(g, 0).length() &&
    min_layers(g) == schedule(g, 0).length()
  })
  assert_true(ok)
}
