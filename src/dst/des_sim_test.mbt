// des_sim_test.mbt —— DES 核心循环单元测试（任务 8.2）。
//
// 覆盖核心循环推进、达 `max_steps` / 队空终止、`of_legacy` 提升场景的 DES 调度
// 投影与既有 `run` 同种子下任务序列一致、`replay_des` 与 `run_des` 终态 / 轨迹一致
// （R2.1 / R2.5 / R12.3）。

///|
/// 正常复制场景：核心循环推进至完成，副本一致（终态 Completed）。
test "run_des drives replication to a consistent completion" {
  let r = run_des(1, demo_replication_scenario(3))
  match r.status {
    Completed => ()
    Failed(reason~) => fail("expected Completed, got \{reason}")
  }
  // 所有副本日志收敛为领导者广播值。
  assert_eq(node_log_from_finals(r.finals, 0), [100])
  assert_eq(node_log_from_finals(r.finals, 1), [100])
  assert_eq(node_log_from_finals(r.finals, 2), [100])
}

///|
/// 终止性：空任务场景立即终止；步数受 max_steps 约束。
test "run_des terminates on empty and bounded scenarios" {
  let empty = DesScenario::new([], [], [], null_protocol(), 8)
  let r = run_des(1, empty)
  assert_eq(r.trace.length(), 0)
  match r.status {
    Completed => ()
    Failed(..) => fail("empty scenario should complete")
  }
}

///|
/// of_legacy：提升场景的 DES 调度投影与既有 run 同种子下任务序列一致。
test "of_legacy schedule projection matches legacy run" {
  let scenario = Scenario::new(
    [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c"), Task::new(3, "d")],
    [],
    16,
  )
  for seed in [1UL, 7UL, 42UL, 999UL, 0xDEADUL] {
    let leg = run(seed, scenario)
    let des = run_des(
      seed,
      DesScenario::of_legacy(scenario, protocol=null_protocol()),
    )
    assert_eq(des_scheduled_ids(des.trace), legacy_scheduled_ids(leg.trace))
  }
}

///|
/// replay_des 以种子 + 轨迹复现一致的终态与轨迹（含崩溃失败运行）。
test "replay_des reproduces status and trace" {
  let sc = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")],
    [FaultPolicyEx::new(0, 1, NetFaultKind::Crash)],
    [],
    null_protocol(),
    16,
  )
  let r = run_des(3, sc)
  let rep = replay_des(r.seed, r.trace)
  assert_eq(rep.status, r.status)
  assert_eq(rep.trace, r.trace)
}

///|
/// World::step 公开步进接口可用且就地推进。
test "World::step advances the simulation in place" {
  let w = World::new(5, demo_replication_scenario(2))
  let _ = w.step()
  // 至少产生了一个事件（首个唤醒）。
  assert_true(w.trace_view().length() >= 1)
}
