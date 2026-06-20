// prop_p20_unwatch_test.mbt —— Property 20：unwatch 撤销监视（任务 11.16）。
//
//   Feature: actor, Property 20: unwatch 撤销监视
//   ------------------------------------------------------------------
//   *对任意* 监视关系，unwatch 后该 target 其后的终止不再向该监视者投递 Terminated。
//
// **Validates: Requirements 7.3**

///|
/// 哨兵：Terminated 适配结果。
let p20_signal : Int = 9999

///|
/// 单次场景：watch → unwatch → target 停止 → watcher 不应收到 Terminated（状态保持 0）。
fn p20_unwatch(rng : @infra_pbt.Rng) -> Bool {
  ignore(rng)
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let target = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let watcher = sys.spawn(
    0,
    Behavior::new(fn(ctx, s, m) {
      if m == 1 {
        ctx.watch(target.id, fn(_id, _r) { p20_signal })
        Updated(s)
      } else if m == 2 {
        ctx.unwatch(target.id)
        Updated(s)
      } else if m == p20_signal {
        Updated(s + 1)
      } else {
        Updated(s)
      }
    }),
  )
  watcher.send(1) // watch
  watcher.send(2) // unwatch
  sys.run_until_idle()
  target.stop()
  sys.run_until_idle()
  // 已撤销监视：watcher 不收到 Terminated。
  sys.state_of(watcher) == Some(0)
}

///|
/// Feature: actor, Property 20: unwatch 撤销监视（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 7.3**
test "Feature: actor, Property 20: unwatch cancels termination notification (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p20_unwatch(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
