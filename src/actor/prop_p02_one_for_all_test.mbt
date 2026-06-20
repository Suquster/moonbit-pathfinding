// prop_p02_one_for_all_test.mbt —— Property 2：OneForAll 全体处置（任务 3.3）。
//
//   Feature: actor, Property 2: OneForAll 全体处置
//   ------------------------------------------------------------------
//   *对任意* 子 actor 集合，任一子在 `OneForAll` 策略下失败时，处置范围恒为全部子。
//
// **Validates: Requirements 1.3**

///|
/// 单次场景：affected_children(OneForAll) 恒为 [0, 1, ..., child_count-1]（全体且有序）。
fn p02_one_for_all(rng : @infra_pbt.Rng) -> Bool {
  let child_count = rng.next_range(1, 20)
  let failed = rng.next_range(0, child_count - 1)
  let affected = affected_children(OneForAll, child_count, failed)
  if affected.length() != child_count {
    return false
  }
  for i in 0..<child_count {
    if affected[i] != i {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 2: OneForAll 全体处置（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 1.3**
test "Feature: actor, Property 2: OneForAll affects all children (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p02_one_for_all(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
