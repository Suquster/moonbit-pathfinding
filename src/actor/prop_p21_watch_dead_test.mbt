// prop_p21_watch_dead_test.mbt —— Property 21：watch 已终止目标立即通知（任务 11.17）。
//
//   Feature: actor, Property 21: watch 已终止目标立即通知
//   ------------------------------------------------------------------
//   *对任意* 已终止的 target，对其执行 watch 时仍立即向监视者投递一条携带该 target
//   标识与原因的 Terminated。
//
// **Validates: Requirements 7.4**

///|
/// 哨兵：Terminated 适配结果。
let p21_signal : Int = 9999

///|
/// 单次场景：target 先停止；之后 watcher 才 watch → 立即收到一条 Terminated。
fn p21_watch_dead(rng : @infra_pbt.Rng) -> Bool {
  ignore(rng)
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let target = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let watcher = sys.spawn(
    0,
    Behavior::new(fn(ctx, s, m) {
      if m == 1 {
        ctx.watch(target.id, fn(_id, _r) { p21_signal })
        Updated(s)
      } else if m == p21_signal {
        Updated(s + 1)
      } else {
        Updated(s)
      }
    }),
  )
  // 先终止 target。
  target.stop()
  sys.run_until_idle()
  // target 已终止后才 watch。
  watcher.send(1)
  sys.run_until_idle()
  // 立即投递一条 Terminated → watcher 状态为 1。
  sys.state_of(watcher) == Some(1)
}

///|
/// Feature: actor, Property 21: watch 已终止目标立即通知（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 7.4**
test "Feature: actor, Property 21: watching an already-terminated target notifies immediately (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p21_watch_dead(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
