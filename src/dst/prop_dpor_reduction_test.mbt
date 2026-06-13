// prop_dpor_reduction_test.mbt —— Property 11：DPOR 约简有效性（任务 12.4）。
//
// Feature: dst, Property 11: DPOR 约简有效性（explore_dpor(...).explored 不超过
// explore_bounded(...).explored）。
//
// **Validates: Requirements 6.6**
//
// 复用 prop_dpor_sound_test.mbt 的 `p10_gen` / `p10_scenario`。

///|
/// **Validates: Requirements 6.6**
test "Feature: dst, Property 11: DPOR explores no more interleavings than bounded" {
  let ok = @infra_pbt.holds_for_all(p10_gen(), fn(t) {
    let (seed, n, fail) = t
    let sc = p10_scenario(n, fail)
    let b = explore_bounded(seed, sc, n)
    let d = explore_dpor(seed, sc, n)
    d.explored <= b.explored
  })
  assert_true(ok)
}
