// prop_p13_ask_timeout_test.mbt —— Property 13：ask 超时确定性（任务 12.2）。
//
//   Feature: actor, Property 13: ask 超时确定性
//   ------------------------------------------------------------------
//   *对任意* 在预算内未收到匹配响应的 ask，结果确定性地判定为 Timeout，重复执行
//   结果一致。
//
// **Validates: Requirements 4.4**
//
// 建模：请求消息携带关联 id（编码为 Int = id*2）；被请求 actor 只对「会回填」的
// 模式回填。当请求 actor 不回填（沉默 actor）时，ask 在任意预算下恒得 Timeout。

///|
/// 单次场景：沉默 actor（从不回填 broker）→ ask 恒 Timeout；两次独立运行结果一致。
fn p13_ask_timeout(rng : @infra_pbt.Rng) -> Bool {
  let budget = rng.next_range(0, 20)
  // 沉默 actor：处理请求但不回填。
  let run = fn() -> AskResult[Int] {
    let sys : ActorSystem[Int, Int] = ActorSystem::new()
    let broker : AskBroker[Int] = AskBroker::new()
    let target = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
    ask(sys, broker, target, fn(id) { id.value }, budget)
  }
  let r1 = run()
  let r2 = run()
  // 恒 Timeout 且两次一致。
  match (r1, r2) {
    (Timeout, Timeout) => true
    _ => false
  }
}

///|
/// Feature: actor, Property 13: ask 超时确定性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 4.4**
test "Feature: actor, Property 13: ask without a reply deterministically times out (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p13_ask_timeout(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
