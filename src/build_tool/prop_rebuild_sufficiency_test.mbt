// prop_rebuild_sufficiency_test.mbt —— Property 5：最小重建集充分性。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag_with_dirty；以独立可达闭包
// oracle（reachable_from_any）对照 minimal_rebuild_set。

///|
/// Feature: build-tool, Property 5: 最小重建集充分性
///
/// 对任意无环构建图与脏输入子集，每个从某脏输入沿依赖边前向可达的目标都被
/// 包含在最小重建集中（受变更传递影响的目标无一遗漏）。
///
/// **Validates: Requirements 5.1, 5.2, 5.5, 6.4**
test "Feature: build-tool, Property 5: rebuild-set sufficiency" {
  let ok = @infra_pbt.holds_for_all(gen_dag_with_dirty(), fn(pair) {
    let (g, dirty) = pair
    let set = minimal_rebuild_set(g, dirty)
    let reach = reachable_from_any(g, dirty)
    // 每个可达目标必在重建集中。
    for n in g.nodes {
      if reach.contains(n) && !list_contains_target(set, n) {
        return false
      }
    }
    true
  })
  assert_true(ok)
}
