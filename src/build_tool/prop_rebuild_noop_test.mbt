// prop_rebuild_noop_test.mbt —— Property 7：增量空操作幂等。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag；模拟「一次成功构建后输入未变」
// （observe + mark_built 固化基线 == 当前），校验连续两次重建集均空且相等。

///|
/// Feature: build-tool, Property 7: 增量空操作幂等
///
/// 对任意构建图，当所有目标的当前指纹与基线指纹一致（无输入变更）时，连续
/// 两次计算的最小重建集均为空且彼此相等。
///
/// **Validates: Requirements 6.1, 6.3, 6.5**
test "Feature: build-tool, Property 7: incremental no-op idempotence" {
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    let cache = BuildCache::new()
    // 一次成功构建：固化基线，基线 == 当前。
    for n in g.nodes {
      cache.observe(n.name, 1L, "h-" + n.name)
      cache.mark_built(n.name)
    }
    let d1 = dirty_targets(g, cache)
    let s1 = minimal_rebuild_set(g, d1)
    let d2 = dirty_targets(g, cache)
    let s2 = minimal_rebuild_set(g, d2)
    d1.length() == 0 &&
    s1.length() == 0 &&
    s2.length() == 0 &&
    targets_eq(s1, s2)
  })
  assert_true(ok)
}
