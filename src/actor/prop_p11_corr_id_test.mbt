// prop_p11_corr_id_test.mbt —— Property 11：ask 关联 id 唯一性（任务 5.2）。
//
//   Feature: actor, Property 11: ask 关联 id 唯一性
//   ------------------------------------------------------------------
//   *对任意* ask 交互序列，同一运行内 `allocate` 的关联 id 两两不同。
//
// **Validates: Requirements 4.2, 4.7**

///|
/// 单次场景：随机分配 n 个关联 id，断言它们两两不同（且单调递增）。
fn p11_corr_id_unique(rng : @infra_pbt.Rng) -> Bool {
  let broker : AskBroker[Int] = AskBroker::new()
  let n = rng.next_range(0, 50)
  let seen : Map[Int, Bool] = Map([])
  let mut prev = 0
  for _i in 0..<n {
    let id = broker.allocate()
    // 两两不同。
    if seen.get(id.value) is Some(_) {
      return false
    }
    seen.set(id.value, true)
    // 单调递增。
    if id.value <= prev {
      return false
    }
    prev = id.value
  }
  true
}

///|
/// Feature: actor, Property 11: ask 关联 id 唯一性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 4.2, 4.7**
test "Feature: actor, Property 11: allocated correlation ids are pairwise distinct (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p11_corr_id_unique(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
