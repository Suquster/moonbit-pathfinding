// prop_p10_post_stop_test.mbt —— Property 10：post_stop 调用一次（任务 11.11）。
//
//   Feature: actor, Property 10: post_stop 调用一次
//   ------------------------------------------------------------------
//   *对任意* 因 stop 请求或 Stop 指令终止的 actor，其 post_stop 恰被调用一次。
//
// **Validates: Requirements 3.2**

///|
/// 单次场景（显式 stop）：处理若干消息后 stop，post_stop 恰一次。
fn p10_post_stop_on_stop(rng : @infra_pbt.Rng) -> Bool {
  let stops : Array[Int] = []
  let hooks : LifecycleHooks[Int] = LifecycleHooks::new(
    fn(s) { s },
    fn(_s) { stops.push(1) },
    fn(_s, _r) {  },
    fn(s) { s },
  )
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, Behavior::new(fn(_c, s, m) { Updated(s + m) }), hooks~)
  let n = rng.next_range(0, 5)
  for _i in 0..<n {
    a.send(rng.next_range(1, 10))
  }
  sys.run_until_idle()
  a.stop()
  sys.run_until_idle()
  // 多跑几次确保不会重复调用。
  sys.run_until_idle()
  stops.length() == 1
}

///|
/// 单次场景（Stop 指令）：失败 + Stop 指令 → post_stop 恰一次。
fn p10_post_stop_on_directive(rng : @infra_pbt.Rng) -> Bool {
  ignore(rng)
  let stops : Array[Int] = []
  let hooks : LifecycleHooks[Int] = LifecycleHooks::new(
    fn(s) { s },
    fn(_s) { stops.push(1) },
    fn(_s, _r) {  },
    fn(s) { s },
  )
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let child = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      if m < 0 {
        Errored("x")
      } else {
        Updated(s + m)
      }
    }),
    hooks~,
    supervisor=sup,
    directive=Stop,
  )
  sys.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Stop),
    [child],
  )
  child.send(-1)
  sys.run_until_idle()
  sys.run_until_idle()
  stops.length() == 1
}

///|
/// Feature: actor, Property 10: post_stop 调用一次（显式 stop）（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.2**
test "Feature: actor, Property 10: post_stop is called exactly once on stop (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p10_post_stop_on_stop(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: actor, Property 10: post_stop 调用一次（Stop 指令）（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.2**
test "Feature: actor, Property 10: post_stop is called exactly once on Stop directive (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p10_post_stop_on_directive(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
