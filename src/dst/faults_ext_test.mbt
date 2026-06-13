// faults_ext_test.mbt —— 丰富故障语义单元测试（任务 5.2）。
//
// 经 `run_des` 观测代表性效果：`Partition` 阻断跨组投递、`Duplicate` 产生两条独立
// `EvDeliver`、`ClockSkew` 改变投递调度而保留投递、`Reorder` 调换投递顺序而不丢失
// 消息；并断言 `of_legacy` 桥对 `Crash` / `Delay` / `Drop` 与既有语义等价
// （R3.2 / R3.3 / R3.4 / R3.5 / R12.4）。

///|
/// Partition：跨组投递被阻断（节点 0 与节点 1 分属不同分组）。
test "Partition blocks cross-group delivery" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b")]
  let faults = [
    FaultPolicyEx::new(0, 0, NetFaultKind::Partition(group=0, until_step=100)),
    FaultPolicyEx::new(0, 1, NetFaultKind::Partition(group=1, until_step=100)),
  ]
  let sc = DesScenario::new(tasks, faults, [], one_send_protocol(), 30)
  let r = run_des(7, sc)
  assert_eq(count_deliveries(r.trace), 0)
}

///|
/// Duplicate：受影响发送方的消息被投递两次（同一 id 两条独立 EvDeliver）。
test "Duplicate fault delivers a message twice" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b")]
  let faults = [FaultPolicyEx::new(0, 0, NetFaultKind::Duplicate)]
  let sc = DesScenario::new(tasks, faults, [], one_send_protocol(), 30)
  let r = run_des(123, sc)
  assert_eq(count_deliveries_to(r.trace, 1), 2)
}

///|
/// ClockSkew：偏移目标节点本地时钟，改变其后行为轨迹，但消息仍被投递。
test "ClockSkew shifts scheduling yet preserves delivery" {
  let base = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [],
    [],
    one_send_protocol(),
    30,
  )
  let skewed = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [FaultPolicyEx::new(0, 0, NetFaultKind::ClockSkew(offset=5L))],
    [],
    one_send_protocol(),
    30,
  )
  let r0 = run_des(9, base)
  let r1 = run_des(9, skewed)
  assert_eq(count_deliveries(r1.trace), 1)
  // 注入时钟偏移使轨迹有别于无故障运行（至少多出 EvFaulted 记录）。
  assert_not_eq(r0.trace, r1.trace)
}

///|
/// Reorder：调换同时刻、同目标的两条消息投递顺序，而不丢失消息。
test "Reorder swaps co-temporal delivery order without loss" {
  let normal = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [],
    [],
    double_send_protocol(),
    30,
  )
  let reordered = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [FaultPolicyEx::new(0, 0, NetFaultKind::Reorder)],
    [],
    double_send_protocol(),
    30,
  )
  let rn = run_des(5, normal)
  let rr = run_des(5, reordered)
  assert_eq(node_log_from_finals(rn.finals, 1), [7, 8])
  assert_eq(node_log_from_finals(rr.finals, 1), [8, 7])
}

///|
/// of_legacy 桥：Crash / Delay / Drop 提升后与既有故障语义等价（调度投影一致）。
test "of_legacy bridges Crash/Delay/Drop equivalently to legacy run" {
  let scenario = Scenario::new(
    [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")],
    [
      FaultPolicy::new(0, 1, FaultKind::Crash),
      FaultPolicy::new(1, 2, FaultKind::Delay),
      FaultPolicy::new(0, 0, FaultKind::Drop),
    ],
    16,
  )
  let legacy = run(42, scenario)
  let des = run_des(42, DesScenario::of_legacy(scenario, protocol=null_protocol()))
  assert_eq(des_scheduled_ids(des.trace), legacy_scheduled_ids(legacy.trace))
  // 崩溃使两条流水线终态同为 Failed。
  let leg_failed = match legacy.status {
    Failed(..) => true
    _ => false
  }
  let des_failed = match des.status {
    Failed(..) => true
    _ => false
  }
  assert_eq(leg_failed, des_failed)
}

///|
/// NetFaultKind::of_legacy 的逐项映射见证。
test "NetFaultKind::of_legacy maps each legacy kind" {
  assert_eq(NetFaultKind::of_legacy(FaultKind::Crash), NetFaultKind::Crash)
  assert_eq(NetFaultKind::of_legacy(FaultKind::Delay), NetFaultKind::Delay(by=1UL))
  assert_eq(NetFaultKind::of_legacy(FaultKind::Drop), NetFaultKind::Drop)
}
