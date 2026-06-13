// prop_net_fault_test.mbt —— Property 6：网络故障语义（任务 5.4）。
//
// Feature: dst, Property 6: 网络故障语义（Partition 生效区间内不存在跨组 EvDeliver；
// 命中 Duplicate 的同一 id 消息恰对应两条独立 EvDeliver）。
//
// **Validates: Requirements 3.2, 3.4**

///|
/// 生成器：将 n 个副本划分到两个分区分组并对每个副本注入对应分区故障。
/// 强制副本 0（广播发起者）属组 0、副本 n-1 属组 1，确保存在被阻断的跨组目标。
fn p6_gen() -> @infra_pbt.Gen[(UInt64, DesScenario, Array[Int])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 5)
    let groups : Array[Int] = []
    for _ in 0..<n {
      groups.push(rng.next_below(2))
    }
    groups[0] = 0
    groups[n - 1] = 1
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "r\{i}"))
    }
    let faults : Array[FaultPolicyEx] = []
    for i in 0..<n {
      faults.push(
        FaultPolicyEx::new(
          0,
          i,
          NetFaultKind::Partition(group=groups[i], until_step=1000),
        ),
      )
    }
    let sc = DesScenario::new(tasks, faults, [], replication_protocol(n), 4 * n + 20)
    (rng.next(), sc, groups)
  })
}

///|
/// Partition：生效区间内不存在跨组投递。
///
/// **Validates: Requirements 3.2**
test "Feature: dst, Property 6a: partition blocks all cross-group deliveries" {
  let ok = @infra_pbt.holds_for_all(p6_gen(), fn(t) {
    let (seed, sc, groups) = t
    let r = run_des(seed, sc)
    for e in r.trace {
      match e {
        EvDeliver(from~, to~, ..) => if groups[from] != groups[to] { return false }
        _ => ()
      }
    }
    true
  })
  assert_true(ok)
}

///|
/// Duplicate：受影响发送方的消息恰被投递两次。
///
/// **Validates: Requirements 3.4**
test "Feature: dst, Property 6b: duplicate fault delivers an affected message twice" {
  let ok = @infra_pbt.holds_for_all(@infra_pbt.gen_int_range(1, 100000), fn(k) {
    let sc = DesScenario::new(
      [Task::new(0, "a"), Task::new(1, "b")],
      [FaultPolicyEx::new(0, 0, NetFaultKind::Duplicate)],
      [],
      one_send_protocol(),
      30,
    )
    let r = run_des(k.to_uint64(), sc)
    count_deliveries_to(r.trace, 1) == 2
  })
  assert_true(ok)
}
