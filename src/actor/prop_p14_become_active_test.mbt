// prop_p14_become_active_test.mbt —— Property 14：become 当前行为生效（任务 1.2）。
//
//   Feature: actor, Property 14: become 当前行为生效
//   ------------------------------------------------------------------
//   *对任意* 消息序列与行为切换（become / unbecome）序列，每条消息由其被处理
//   时刻的栈顶行为处理。
//
// **Validates: Requirements 5.1, 5.2, 5.3, 5.6**
//
// 建模方式：每个「行为」用一个整数标记 `bid` 标识，其处理函数把 `bid` 写入状态。
// 维护一个**纯整数参照栈**（push bid / pop 但不弹空栈底）与一个真实
// `Array[Behavior]` 行为栈，逐操作同步演进；每步取真实栈顶行为应用于一条消息，
// 断言其写入的 `bid` 等于参照栈顶 —— 即「当前生效行为恒为栈顶」。

///|
/// 构造一个标记为 `bid` 的行为：处理时把状态置为 `bid`（便于辨识哪个行为在生效）。
fn p14_tagged_behavior(bid : Int) -> Behavior[Int, Int] {
  Behavior::new(fn(_ctx, _s, _m) { Updated(bid) })
}

///|
/// 单次场景：随机生成 become(bid) / unbecome 操作序列，逐操作同步参照栈与真实栈，
/// 每步用栈顶行为处理一条消息，断言写入标记等于参照栈顶。
fn p14_become_active(rng : @infra_pbt.Rng) -> Bool {
  // 栈底初始行为标记 0。
  let ref_stack : Array[Int] = [0]
  let real_stack = behavior_stack_new(p14_tagged_behavior(0))
  let ctx : ActorContext[Int, Int] = ActorContext::new({ value: 1 })
  let ops = rng.next_range(0, 30)
  let mut next_bid = 1
  for _i in 0..<ops {
    // 50% become、50% unbecome。
    if rng.next_bool() {
      let bid = next_bid
      next_bid = next_bid + 1
      ref_stack.push(bid)
      behavior_stack_push(real_stack, p14_tagged_behavior(bid))
    } else {
      if ref_stack.length() > 1 {
        let _ = ref_stack.pop()
      }
      behavior_stack_pop(real_stack)
    }
    // 取真实栈顶行为处理一条消息，校验其写入标记 == 参照栈顶。
    let expected_top = ref_stack[ref_stack.length() - 1]
    match behavior_stack_top(real_stack) {
      Some(b) =>
        match b.apply(ctx, 0, 0) {
          Updated(written) => if written != expected_top { return false }
          Errored(_) => return false
        }
      None => return false
    }
    // 真实栈与参照栈深度恒一致。
    if behavior_stack_depth(real_stack) != ref_stack.length() {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 14: become 当前行为生效（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 5.1, 5.2, 5.3, 5.6**
test "Feature: actor, Property 14: each message handled by current top-of-stack behavior (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p14_become_active(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
