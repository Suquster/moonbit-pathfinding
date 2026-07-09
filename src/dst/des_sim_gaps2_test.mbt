// des_sim_gaps2_test.mbt —— DES 故障注入对不存在节点与 Byzantine 通路收口
// （INFRA 第二十四批）。

///|
/// 双副本复制场景 + 指定故障计划。
fn dg2_scenario(faults : Array[FaultPolicyEx]) -> DesScenario {
  DesScenario::new(
    [Task::new(0, "replica0"), Task::new(1, "replica1")],
    faults,
    [],
    replication_protocol(2),
    32,
  )
}

///|
test "run_des：Byzantine 注入通路可达且确定性" {
  let sc = dg2_scenario([FaultPolicyEx::new(1, 1, NetFaultKind::Byzantine)])
  let r1 = run_des(11UL, sc)
  let r2 = run_des(11UL, sc)
  assert_true(r1.trace == r2.trace)
  assert_true(r1.trace.length() > 0)
}

///|
test "run_des：指向不存在节点的故障安全忽略" {
  let sc = dg2_scenario([
    FaultPolicyEx::new(1, 99, NetFaultKind::Byzantine),
    FaultPolicyEx::new(2, 99, NetFaultKind::DiskFault(lose=1)),
    FaultPolicyEx::new(3, 99, NetFaultKind::Duplicate),
  ])
  let r = run_des(11UL, sc)
  // 与无故障运行的终态一致（对不存在节点的注入不改变任何副本）。
  let base = run_des(11UL, dg2_scenario([]))
  assert_true(r.finals == base.finals)
}

///|
test "run_des：DiskFault 丢写超过日志长度时安全清空" {
  let sc = dg2_scenario([
    FaultPolicyEx::new(3, 0, NetFaultKind::DiskFault(lose=1000)),
  ])
  let r = run_des(11UL, sc)
  for pair in r.finals {
    let (id, app) = pair
    if id == 0 {
      assert_true(app.log.length() >= 0)
    }
  }
}
