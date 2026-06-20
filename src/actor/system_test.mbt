// system_test.mbt —— ActorSystem 集成单元测试（任务 11.20）。
//
// 覆盖：两层监督升级、unbecome 弹空空操作、向已停止 actor send 丢弃见证。
// _Requirements: 1.5, 5.4, 14.3_

///|
/// 两层监督升级见证：leaf(Escalate) 失败 → 升级至 root → root 重启 mid（级联 leaf）。
test "two-level supervision escalation restarts the mid supervisor (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let root = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let mid = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let leaf = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      if m < 0 {
        Errored("boom")
      } else {
        Updated(s + m)
      }
    }),
  )
  sys.supervise(
    root,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [mid],
  )
  sys.supervise(
    mid,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [leaf],
  )
  sys.set_directive(leaf, Escalate)
  leaf.send(-1)
  sys.run_until_idle()
  assert_eq(sys.restart_count(mid), 1)
  assert_true(sys.restart_count(leaf) >= 1)
  assert_true(sys.is_running(mid))
  assert_true(sys.is_running(leaf))
}

///|
/// unbecome 弹空空操作见证：仅含初始行为时 unbecome 不改变后续处理行为。
test "unbecome on initial behavior is a no-op in ActorSystem (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(
    0,
    Behavior::new(fn(ctx, s, m) {
      // 每条消息都尝试 unbecome（栈仅含初始行为时为空操作），并累加。
      ctx.unbecome()
      Updated(s + m)
    }),
  )
  a.send(3)
  a.send(4)
  sys.run_until_idle()
  // 初始行为始终生效（unbecome 空操作），状态 = 3 + 4。
  assert_eq(sys.state_of(a), Some(7))
  assert_true(sys.is_running(a))
}

///|
/// 向已停止 actor send 丢弃见证：stop 后 send 的消息不被处理。
test "sending to a stopped actor drops the message (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, Behavior::new(fn(_c, s, m) { Updated(s + m) }))
  a.send(10)
  sys.run_until_idle()
  assert_eq(sys.state_of(a), Some(10))
  a.stop()
  sys.run_until_idle()
  // 已停止：后续 send 被丢弃（邮箱关闭）。
  a.send(99)
  sys.run_until_idle()
  assert_eq(sys.state_of(a), Some(10))
  match sys.status_of(a) {
    Some(Stopped) => ()
    _ => fail("expected Stopped")
  }
}
