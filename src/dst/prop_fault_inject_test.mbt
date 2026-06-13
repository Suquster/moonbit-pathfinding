// prop_fault_inject_test.mbt —— Property 5：故障注入点确定性与可重放（任务 5.3）。
//
// Feature: dst, Property 5: 故障注入点确定性与可重放（两次 run_des 的 EvFaulted 序列
// 完全一致，且以 seed+trace 调用 replay_des 复现一致的 status 与 trace）。
//
// **Validates: Requirements 3.1, 3.7**

///|
/// 生成器：含至少一条故障、无运行时不变量的小规模消息场景（终态由故障 / 轨迹确定）。
fn p5_gen() -> @infra_pbt.Gen[(UInt64, DesScenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 4)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "r\{i}"))
    }
    let fc = rng.next_range(1, 3)
    let faults : Array[FaultPolicyEx] = []
    for _ in 0..<fc {
      faults.push(
        FaultPolicyEx::new(
          rng.next_range(0, n),
          rng.next_below(n),
          sample_netfault(rng, n),
        ),
      )
    }
    let sc = DesScenario::new(
      tasks,
      faults,
      [],
      replication_protocol(n),
      4 * n + 16,
    )
    (rng.next(), sc)
  })
}

///|
/// **Validates: Requirements 3.1, 3.7**
test "Feature: dst, Property 5: fault injection determinism and replayability" {
  let ok = @infra_pbt.holds_for_all(p5_gen(), fn(pair) {
    let (seed, sc) = pair
    let r1 = run_des(seed, sc)
    let r2 = run_des(seed, sc)
    // 故障事件序列在两次运行间完全一致（同一注入点触发）。
    if faulted_events(r1.trace) != faulted_events(r2.trace) {
      return false
    }
    // 以 seed + trace 重放，复现一致的终态与轨迹。
    let rep = replay_des(r1.seed, r1.trace)
    rep.status == r1.status && rep.trace == r1.trace
  })
  assert_true(ok)
}
