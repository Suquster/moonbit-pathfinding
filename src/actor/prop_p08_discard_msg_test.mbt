// prop_p08_discard_msg_test.mbt —— Property 8：重启丢弃当前消息（任务 11.9）。
//
//   Feature: actor, Property 8: 重启丢弃当前消息
//   ------------------------------------------------------------------
//   *对任意* 触发失败的消息，重启后该消息不被重放，从下一条继续处理。
//
// **Validates: Requirements 3.4**

///|
/// 单次场景：actor 记录其处理过的消息序列；某条「毒丸」触发失败并 Restart。
/// 断言处理序列中毒丸只出现一次（失败那次，未被重放）。
fn p08_discard_current(rng : @infra_pbt.Rng) -> Bool {
  // 用状态数组记录被「成功累加」的消息；毒丸值固定为 -999。
  let processed : Array[Int] = []
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let child = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      if m == -999 {
        Errored("poison")
      } else {
        processed.push(m)
        Updated(s + 1)
      }
    }),
    supervisor=sup,
    directive=Restart,
  )
  sys.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [child],
  )
  // 前缀正常消息 + 毒丸 + 后缀正常消息。
  let pre = rng.next_range(0, 4)
  for _i in 0..<pre {
    child.send(rng.next_range(1, 100))
  }
  child.send(-999)
  let post = rng.next_range(0, 4)
  for _i in 0..<post {
    child.send(rng.next_range(1, 100))
  }
  sys.run_until_idle()
  // 毒丸不应出现在成功处理序列中（它触发失败被丢弃，且未被重放）。
  for v in processed {
    if v == -999 {
      return false
    }
  }
  // 成功处理条数 = pre + post（毒丸被丢弃，未重放）。
  if processed.length() != pre + post {
    return false
  }
  // 重启发生一次。
  sys.restart_count(child) == 1
}

///|
/// Feature: actor, Property 8: 重启丢弃当前消息（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.4**
test "Feature: actor, Property 8: the failing message is discarded and not replayed after restart (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p08_discard_current(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
