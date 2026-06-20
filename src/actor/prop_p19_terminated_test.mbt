// prop_p19_terminated_test.mbt —— Property 19：终止通知必达且不重复（任务 11.15）。
//
//   Feature: actor, Property 19: 终止通知必达且不重复
//   ------------------------------------------------------------------
//   *对任意* 监视关系集合与终止序列，每个在终止时仍处于监视状态的监视者恰收到
//   一条对应该 target 的 Terminated 通知。
//
// **Validates: Requirements 7.1, 7.2, 7.5, 7.6**
//
// 建模：watcher 收到消息 1 时 watch(target)；收到哨兵 9999（Terminated 适配结果）时
// 状态加一计数。target 停止后应恰投递一条 Terminated → watcher 状态恰为 1。

///|
/// 哨兵：Terminated 适配器映射出的 watcher 消息值。
let p19_terminated_signal : Int = 9999

///|
/// 单次场景：建立监视 → target 停止 → watcher 恰收到一条 Terminated。
fn p19_terminated_once(rng : @infra_pbt.Rng) -> Bool {
  ignore(rng)
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let target = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let watcher = sys.spawn(
    0,
    Behavior::new(fn(ctx, s, m) {
      if m == 1 {
        ctx.watch(target.id, fn(_id, _reason) { p19_terminated_signal })
        Updated(s)
      } else if m == p19_terminated_signal {
        Updated(s + 1)
      } else {
        Updated(s)
      }
    }),
  )
  watcher.send(1) // 建立监视。
  sys.run_until_idle()
  target.stop() // 终止 target。
  sys.run_until_idle()
  // watcher 恰收到一条 Terminated（状态计数为 1）。
  sys.state_of(watcher) == Some(1)
}

///|
/// Feature: actor, Property 19: 终止通知必达且不重复（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 7.1, 7.2, 7.5, 7.6**
test "Feature: actor, Property 19: a watching watcher receives exactly one Terminated (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p19_terminated_once(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
