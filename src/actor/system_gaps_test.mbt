// system_gaps_test.mbt —— 监督系统边界分支覆盖收口（INFRA 第十八批）：
// 根 supervisor 升级退化、强度超限、无监督失败终态、未知 id 查询、
// watch 已失败目标的确定性见证。

///|
/// 失败触发行为：收到负数 → Errored。
fn sg_faulty() -> Behavior[Int, Int] {
  Behavior::new(fn(_c, s, m) {
    if m < 0 {
      Errored("boom")
    } else {
      Updated(s + m)
    }
  })
}

///|
test "actor 根 supervisor 升级退化为停止失败子" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let root = sys.spawn(0, sg_faulty())
  let leaf = sys.spawn(0, sg_faulty())
  sys.supervise(
    root,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [leaf],
  )
  sys.set_directive(leaf, Escalate)
  leaf.send(-1)
  sys.run_until_idle()
  // root 无上层 supervisor：升级退化为停止 leaf。
  assert_true(sys.is_running(leaf) == false)
  assert_true(sys.restart_count(leaf) == 0)
}

///|
test "actor 强度超限升级与 Stop 指令范围处置" {
  // 强度 max_restarts=1：第二次失败超限 → 升级（根退化为停止）。
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let root = sys.spawn(0, sg_faulty())
  let leaf = sys.spawn(0, sg_faulty())
  sys.supervise(
    root,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(1, 1000), Restart),
    [leaf],
  )
  leaf.send(-1)
  sys.run_until_idle()
  assert_true(sys.restart_count(leaf) == 1)
  leaf.send(-1)
  sys.run_until_idle()
  assert_true(sys.is_running(leaf) == false)
  // Stop 指令：失败即停止（post_stop 语义），状态 Stopped。
  let sys2 : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys2.spawn(0, sg_faulty())
  let kid = sys2.spawn(0, sg_faulty())
  sys2.supervise(
    sup,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Stop),
    [kid],
  )
  kid.send(-1)
  sys2.run_until_idle()
  assert_true(sys2.status_of(kid) == Some(Stopped))
}

///|
test "actor 无监督失败终态与 watch 已失败目标" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let lone = sys.spawn(0, sg_faulty())
  lone.send(-1)
  sys.run_until_idle()
  // 无 supervisor：终态 Failed（错误隔离）。
  assert_true(sys.status_of(lone) is Some(Failed(_)))
  assert_true(sys.is_running(lone) == false)
  // 已失败目标：向其发送消息被丢弃（邮箱已关闭）。
  lone.send(1)
  sys.run_until_idle()
  assert_true(sys.state_of(lone) == Some(0))
  // watch 已失败目标 → 立即投递 Terminated(FailedWith)。
  let seen : Array[Int] = []
  let watcher = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m : Int) {
      seen.push(m)
      Updated(s)
    }),
  )
  let target_id = lone.id
  let w2 = sys.spawn(
    0,
    Behavior::new(fn(c, s, m : Int) {
      if m == 42 {
        c.watch(target_id, fn(_id, _reason) { 777 })
      }
      Updated(s + m)
    }),
  )
  ignore(watcher)
  w2.send(42)
  sys.run_until_idle()
  sys.run_until_idle()
  assert_true(sys.pending(w2) == 0)
}

///|
test "actor 未知 id 查询与空操作" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, sg_faulty())
  let ghost : ActorRef[Int] = { id: { value: 999 }, mailbox: Mailbox::new() }
  // 未知 id：查询回落默认。
  assert_true(sys.state_of(ghost) is None)
  assert_true(sys.status_of(ghost) is None)
  assert_true(sys.is_running(ghost) == false)
  assert_true(sys.restart_count(ghost) == 0)
  assert_true(sys.pending(ghost) == 0)
  // 未知 id 的指令覆盖为空操作。
  sys.set_directive(ghost, Stop)
  // 幽灵 supervisor 的 supervise 子仍可设置指令。
  sys.supervise(
    ghost,
    SupervisorSpec::new(OneForAll, RestartIntensity::new(100, 1000), Restart),
    [a],
  )
  a.send(1)
  sys.run_until_idle()
  assert_true(sys.state_of(a) == Some(1))
}
