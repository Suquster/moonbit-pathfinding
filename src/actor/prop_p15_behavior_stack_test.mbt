// prop_p15_behavior_stack_test.mbt —— Property 15：行为栈往返与不弹空（任务 1.3）。
//
//   Feature: actor, Property 15: 行为栈往返与不弹空
//   ------------------------------------------------------------------
//   *对任意* 行为序列：`become(b)` 紧随 `unbecome()` 后行为栈恢复为操作前的状态；
//   且行为栈仅含初始行为时执行 `unbecome()` 保持当前行为不变（不弹空初始行为）。
//
// **Validates: Requirements 5.4, 5.7**
//
// 建模方式：以整数标记标识每个行为，比较「操作前栈顶标记/深度」与「become 后
// 立即 unbecome」后的栈顶标记/深度逐位一致；并单独验证深度 == 1 时 unbecome 空操作。

///|
/// 标记为 `bid` 的行为（处理时写入 bid）。
fn p15_tagged(bid : Int) -> Behavior[Int, Int] {
  Behavior::new(fn(_ctx, _s, _m) { Updated(bid) })
}

///|
/// 取行为栈顶标记（应用一次得到其写入的 bid）；空栈返回 -1。
fn p15_top_tag(stack : Array[Behavior[Int, Int]]) -> Int {
  let ctx : ActorContext[Int, Int] = ActorContext::new({ value: 1 })
  match behavior_stack_top(stack) {
    Some(b) =>
      match b.apply(ctx, 0, 0) {
        Updated(bid) => bid
        Errored(_) => -1
      }
    None => -1
  }
}

///|
/// 单次场景：随机构造一个行为栈，记录其栈顶标记与深度；执行 `become(x)` 紧随
/// `unbecome()`，断言栈顶标记与深度恢复如初（往返不变）。
fn p15_become_unbecome_roundtrip(rng : @infra_pbt.Rng) -> Bool {
  let stack = behavior_stack_new(p15_tagged(0))
  // 随机预置若干 become，构造任意深度栈。
  let pre = rng.next_range(0, 8)
  let mut bid = 1
  for _i in 0..<pre {
    behavior_stack_push(stack, p15_tagged(bid))
    bid = bid + 1
  }
  let before_top = p15_top_tag(stack)
  let before_depth = behavior_stack_depth(stack)
  // become(x) 紧随 unbecome()：应恢复操作前状态。
  behavior_stack_push(stack, p15_tagged(bid))
  behavior_stack_pop(stack)
  let after_top = p15_top_tag(stack)
  let after_depth = behavior_stack_depth(stack)
  before_top == after_top && before_depth == after_depth
}

///|
/// 单次场景：仅含初始行为时 `unbecome()` 为空操作 —— 栈顶与深度保持不变。
fn p15_unbecome_on_initial_is_noop(rng : @infra_pbt.Rng) -> Bool {
  let init_tag = rng.next_range(0, 1000)
  let stack = behavior_stack_new(p15_tagged(init_tag))
  // 反复 unbecome 任意次，深度恒为 1、栈顶恒为初始行为。
  let times = rng.next_range(1, 6)
  for _i in 0..<times {
    behavior_stack_pop(stack)
    if behavior_stack_depth(stack) != 1 {
      return false
    }
    if p15_top_tag(stack) != init_tag {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 15: 行为栈往返（become 后 unbecome 恢复如初）
///
/// **Validates: Requirements 5.7**
test "Feature: actor, Property 15: become followed by unbecome restores the stack (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p15_become_unbecome_roundtrip(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: actor, Property 15: 不弹空初始行为（深度 == 1 时 unbecome 空操作）
///
/// **Validates: Requirements 5.4**
test "Feature: actor, Property 15: unbecome on the initial behavior is a no-op (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p15_unbecome_on_initial_is_noop(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
