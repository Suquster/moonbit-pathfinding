// prop_shrink_termination_test.mbt —— Property 8：收缩终止与单调（任务 10.4）。
//
// Feature: dst, Property 8: 收缩终止与单调（shrink 有限步内终止，返回的 s' 满足
// size(s') <= size(scenario)）。每次接受候选规模严格递减且有下界，故有限步终止。
//
// **Validates: Requirements 4.2, 4.4, 4.7**
//
// 复用 prop_shrink_fidelity_test.mbt 的失败场景生成器 `p7_gen`。

///|
/// **Validates: Requirements 4.2, 4.4, 4.7**
test "Feature: dst, Property 8: shrink terminates and is monotone in size" {
  let ok = @infra_pbt.holds_for_all(p7_gen(), fn(pair) {
    let (seed, sc) = pair
    if !default_fails(run_des(seed, sc)) {
      return false
    }
    // shrink 必在有限步内返回（holds_for_all 完成即见证终止）。
    match shrink(seed, sc).scenario() {
      Some(s2) => s2.size() <= sc.size()
      None => false
    }
  })
  assert_true(ok)
}
