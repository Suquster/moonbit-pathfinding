// prop_rebuild_minimality_test.mbt —— Property 6：最小重建集最小性。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag_with_dirty；以独立可达闭包
// oracle（reachable_from_any）对照 minimal_rebuild_set。

///|
/// Feature: build-tool, Property 6: 最小重建集最小性
///
/// 对任意无环构建图与脏输入子集，最小重建集中的每个目标都可由某脏输入沿依赖
/// 边到达（不含任何未受影响目标）。
///
/// **Validates: Requirements 5.3, 5.6**
test "Feature: build-tool, Property 6: rebuild-set minimality" {
  let ok = @infra_pbt.holds_for_all(gen_dag_with_dirty(), fn(pair) {
    let (g, dirty) = pair
    let set = minimal_rebuild_set(g, dirty)
    let reach = reachable_from_any(g, dirty)
    // 重建集中每个目标必由某脏输入可达。
    for t in set {
      if !reach.contains(t) {
        return false
      }
    }
    true
  })
  assert_true(ok)
}
