// prop_p01_one_for_one_test.mbt —— Property 1：OneForOne 兄弟隔离（任务 3.2）。
//
//   Feature: actor, Property 1: OneForOne 兄弟隔离
//   ------------------------------------------------------------------
//   *对任意* 子 actor 集合与失败者下标，`OneForOne` 策略下处置范围恒为 `{failed}`，
//   未失败兄弟不在处置范围内（隔离）。
//
// **Validates: Requirements 1.2, 1.6**

///|
/// 单次场景：随机 child_count 与 failed_index，affected_children(OneForOne) 恒为
/// 仅含 failed_index 的单元素列表，其余兄弟均不受影响。
fn p01_one_for_one_isolation(rng : @infra_pbt.Rng) -> Bool {
  let child_count = rng.next_range(1, 20)
  let failed = rng.next_range(0, child_count - 1)
  let affected = affected_children(OneForOne, child_count, failed)
  if affected.length() != 1 {
    return false
  }
  if affected[0] != failed {
    return false
  }
  // 隔离：任一非失败兄弟都不在处置范围。
  for i in 0..<child_count {
    if i != failed && affected.contains(i) {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 1: OneForOne 兄弟隔离（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 1.2, 1.6**
test "Feature: actor, Property 1: OneForOne affects only the failed child (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p01_one_for_one_isolation(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
