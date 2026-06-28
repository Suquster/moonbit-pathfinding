// prop_p05_directive_test.mbt —— Property 5：重启指令语义（任务 11.8）。
//
//   Feature: actor, Property 5: 重启指令语义
//   ------------------------------------------------------------------
//   *对任意* 失败场景与后续消息序列：`Restart` 使失败 actor 状态重置为初始且恢复
//   Running；`Stop` 使其 Stopped 且其后续消息不再被处理。
//
// **Validates: Requirements 2.1, 2.2, 2.3**

///|
/// 消息：正数累加，-1 触发失败。
fn p05_behavior() -> Behavior[Int, Int] {
  Behavior::new(fn(_ctx, s, m) {
    if m < 0 {
      Errored("boom")
    } else {
      Updated(s + m)
    }
  })
}

///|
/// 单次场景（Restart）：actor 累加若干消息后失败，Restart 后状态重置为初始 0、
/// 恢复 Running，并继续处理后续消息。
fn p05_restart_semantics(rng : @infra_pbt.Rng) -> Bool {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let child = sys.spawn(0, p05_behavior(), supervisor=sup, directive=Restart)
  sys.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [child],
  )
  // 累加前缀。
  let pre = rng.next_range(0, 5)
  for _i in 0..<pre {
    child.send(rng.next_range(1, 10))
  }
  child.send(-1) // 触发失败 → Restart 重置为 0。
  // 后续消息。
  let post = rng.next_range(1, 5)
  let mut post_sum = 0
  for _i in 0..<post {
    let v = rng.next_range(1, 10)
    post_sum = post_sum + v
    child.send(v)
  }
  sys.run_until_idle()
  // 重启后状态 = 0 + post_sum（重置后只累加后续消息）。
  if sys.state_of(child) != Some(post_sum) {
    return false
  }
  if !sys.is_running(child) {
    return false
  }
  sys.restart_count(child) == 1
}

///|
/// 单次场景（Stop）：actor 失败且指令为 Stop → Stopped，后续消息不再处理。
fn p05_stop_semantics(rng : @infra_pbt.Rng) -> Bool {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let child = sys.spawn(0, p05_behavior(), supervisor=sup, directive=Stop)
  sys.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Stop),
    [child],
  )
  child.send(-1) // 立即失败 → Stop。
  let post = rng.next_range(1, 5)
  for _i in 0..<post {
    child.send(rng.next_range(1, 10))
  }
  sys.run_until_idle()
  // Stopped 且不再运行；状态保持失败前（此处初始 0，后续消息未处理）。
  match sys.status_of(child) {
    Some(Stopped) => ()
    _ => return false
  }
  if sys.is_running(child) {
    return false
  }
  sys.state_of(child) == Some(0)
}

///|
/// Feature: actor, Property 5: Restart 重置为初始并恢复 Running（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 2.1, 2.2**
test "Feature: actor, Property 5: Restart resets state to initial and resumes Running (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p05_restart_semantics(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: actor, Property 5: Stop 终止且不再处理后续消息（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 2.3**
test "Feature: actor, Property 5: Stop terminates and ignores subsequent messages (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p05_stop_semantics(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
