// prop_p03_rest_for_one_test.mbt —— Property 3：RestForOne 影响范围（任务 3.4）。
//
//   Feature: actor, Property 3: RestForOne 影响范围
//   ------------------------------------------------------------------
//   *对任意* 按启动顺序的子序列与失败者下标，`RestForOne` 仅处置失败者及按启动
//   顺序在其之后的子，其前启动的子不受影响。
//
// **Validates: Requirements 1.4, 1.7**

///|
/// 单次场景：affected_children(RestForOne) 恒为 [failed, failed+1, ..., n-1]；
/// 其前启动者（下标 < failed）均不在处置范围。
fn p03_rest_for_one(rng : @infra_pbt.Rng) -> Bool {
  let child_count = rng.next_range(1, 20)
  let failed = rng.next_range(0, child_count - 1)
  let affected = affected_children(RestForOne, child_count, failed)
  // 范围长度 = n - failed。
  if affected.length() != child_count - failed {
    return false
  }
  // 逐位等于 failed..<n。
  for k in 0..<affected.length() {
    if affected[k] != failed + k {
      return false
    }
  }
  // 其前启动者不受影响。
  for i in 0..<failed {
    if affected.contains(i) {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 3: RestForOne 影响范围（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 1.4, 1.7**
test "Feature: actor, Property 3: RestForOne affects the failed child and later-started siblings (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p03_rest_for_one(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
