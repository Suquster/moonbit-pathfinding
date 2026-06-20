// prop_p18_restart_stash_test.mbt —— Property 18：重启或停止清空暂存（任务 11.13）。
//
//   Feature: actor, Property 18: 重启或停止清空暂存
//   ------------------------------------------------------------------
//   *对任意* 暂存了若干消息后失败的 actor，重启或停止后暂存缓冲为空（暂存消息
//   不被重启后的行为重新处理）。
//
// **Validates: Requirements 6.4**
//
// 建模：actor 对正值消息 stash（暂存，不处理），对 -7 触发失败。重启后再发送一条
// 正常消息并 unstash_all：若暂存已被清空，则之前 stash 的消息不会回流被处理。

///|
/// 单次场景：stash 若干正值（记录为 deferred 计数），-7 失败触发 Restart，
/// 重启后发送消息 100（触发 unstash_all + 累加）。断言：暂存在重启时已清空，
/// 故仅消息 100 被累加（暂存的旧消息未回流），状态 = 100。
fn p18_restart_clears_stash(rng : @infra_pbt.Rng) -> Bool {
  let processed : Array[Int] = []
  let behavior : Behavior[Int, Int] = Behavior::new(fn(ctx, s, m) {
    if m == -7 {
      Errored("boom")
    } else if m == 100 {
      // 触发回流并处理自身。
      ctx.unstash_all()
      processed.push(m)
      Updated(s + m)
    } else {
      // 正值：暂存，不处理。
      ctx.stash()
      Updated(s)
    }
  })
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let child = sys.spawn(0, behavior, supervisor=sup, directive=Restart)
  sys.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [child],
  )
  // 暂存若干正值消息。
  let ns = rng.next_range(1, 5)
  for _i in 0..<ns {
    child.send(rng.next_range(1, 50))
  }
  child.send(-7) // 失败 → Restart 清空暂存
  child.send(100) // 重启后：unstash_all（应无暂存可回流）+ 处理 100
  sys.run_until_idle()
  // 仅 100 被处理（旧暂存消息已被清空，未回流）。
  if processed.length() != 1 {
    return false
  }
  if processed[0] != 100 {
    return false
  }
  sys.state_of(child) == Some(100) && sys.restart_count(child) == 1
}

///|
/// Feature: actor, Property 18: 重启清空暂存（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 6.4**
test "Feature: actor, Property 18: restart clears the stash buffer (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p18_restart_clears_stash(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
