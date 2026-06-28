// behavior_test.mbt —— behavior.mbt 单元测试（任务 1.4）。
//
// 覆盖：弹空空操作见证、效果记录顺序见证。
// _Requirements: 5.1, 5.4_

///|
/// 行为栈：初始仅含初始行为，深度为 1（Requirement 5.1）。
test "behavior stack starts with the initial behavior only" {
  let stack : Array[Behavior[Int, Int]] = behavior_stack_new(
    Behavior::new(fn(_ctx, s, _m) { Updated(s) }),
  )
  @test.assert_eq(behavior_stack_depth(stack), 1)
}

///|
/// 弹空空操作见证：深度 == 1 时反复 unbecome，深度恒为 1（Requirement 5.4）。
test "unbecome on initial-only stack is a no-op witness" {
  let stack : Array[Behavior[Int, Int]] = behavior_stack_new(
    Behavior::new(fn(_ctx, _s, _m) { Updated(0) }),
  )
  behavior_stack_pop(stack)
  behavior_stack_pop(stack)
  @test.assert_eq(behavior_stack_depth(stack), 1)
}

///|
/// push 后深度增加、pop 后回落；栈顶行为随之切换。
test "behavior stack push and pop change depth and top" {
  let stack : Array[Behavior[Int, Int]] = behavior_stack_new(
    Behavior::new(fn(_ctx, _s, _m) { Updated(0) }),
  )
  behavior_stack_push(stack, Behavior::new(fn(_ctx, _s, _m) { Updated(1) }))
  @test.assert_eq(behavior_stack_depth(stack), 2)
  let ctx : ActorContext[Int, Int] = ActorContext::new({ value: 1 })
  match behavior_stack_top(stack) {
    Some(b) =>
      match b.apply(ctx, 0, 0) {
        Updated(v) => @test.assert_eq(v, 1)
        Errored(_) => fail("expected Updated")
      }
    None => fail("expected a top behavior")
  }
  behavior_stack_pop(stack)
  @test.assert_eq(behavior_stack_depth(stack), 1)
  match behavior_stack_top(stack) {
    Some(b) =>
      match b.apply(ctx, 0, 0) {
        Updated(v) => @test.assert_eq(v, 0)
        Errored(_) => fail("expected Updated")
      }
    None => fail("expected a top behavior")
  }
}

///|
/// 效果记录顺序见证：become / stash / unstash_all / watch / unwatch / unbecome 的
/// 记录顺序与调用顺序一致（由 ActorSystem 在 step 末尾按此顺序应用）。
test "context records effects in invocation order witness" {
  let ctx : ActorContext[Int, Int] = ActorContext::new({ value: 7 })
  @test.assert_eq(ctx.id(), { value: 7 })
  ctx.become_(Behavior::new(fn(_c, s, _m) { Updated(s) }))
  ctx.stash()
  ctx.unstash_all()
  ctx.watch({ value: 9 }, fn(_id, _reason) { 0 })
  ctx.unwatch({ value: 9 })
  ctx.unbecome()
  // 6 个效果被依序记录。
  @test.assert_eq(ctx.effect_count(), 6)
}
