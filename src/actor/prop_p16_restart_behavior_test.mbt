// prop_p16_restart_behavior_test.mbt —— Property 16：重启重置行为栈（任务 11.12）。
//
//   Feature: actor, Property 16: 重启重置行为栈
//   ------------------------------------------------------------------
//   *对任意* 失败前的行为切换序列，重启后行为栈恢复为仅含初始行为。
//
// **Validates: Requirements 5.5**
//
// 建模：初始行为把消息累加（标记「初始行为」语义为 Updated(s + m)）；切换后的行为
// 把状态置为固定哨兵 -1。失败触发 Restart 后，发送一条正常消息：若行为栈已重置为
// 初始行为，则状态应为累加结果而非哨兵。

///|
/// 单次场景：消息 1 触发 become(哨兵行为)，消息 2(=-7) 触发失败，重启后发送消息 5：
/// 初始行为应生效（状态 = 0 + 5 = 5），而非哨兵行为（会把状态置 -1）。
fn p16_restart_resets_behavior(rng : @infra_pbt.Rng) -> Bool {
  ignore(rng)
  let sentinel : Behavior[Int, Int] = Behavior::new(fn(_c, _s, m) {
    if m == -7 {
      Errored("boom")
    } else {
      Updated(-1)
    }
  })
  let initial : Behavior[Int, Int] = Behavior::new(fn(ctx, s, m) {
    if m == 7 {
      // 切换到哨兵行为。
      ctx.become_(sentinel)
      Updated(s)
    } else if m == -7 {
      Errored("boom")
    } else {
      Updated(s + m)
    }
  })
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let child = sys.spawn(0, initial, supervisor=sup, directive=Restart)
  sys.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [child],
  )
  child.send(7) // become(sentinel)
  child.send(-7) // 失败 → Restart（行为栈重置为初始）
  child.send(5) // 应由初始行为处理 → 0 + 5
  sys.run_until_idle()
  sys.state_of(child) == Some(5) && sys.restart_count(child) == 1
}

///|
/// Feature: actor, Property 16: 重启重置行为栈（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 5.5**
test "Feature: actor, Property 16: restart resets the behavior stack to the initial behavior (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p16_restart_resets_behavior(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
