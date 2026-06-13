// prop_replay_persist_test.mbt —— Property 15：跨会话重放保真（任务 15.4）。
//
// Feature: dst, Property 15: 跨会话重放保真（r = run_des(seed, scenario) 经
// serialize_result 持久化再 deserialize_result 还原为 r'，以 r'.seed+r'.trace 调用
// replay_des 复现的 DesResult 其 status 与 trace 与 r 逐字段一致）。
//
// **Validates: Requirements 8.4, 8.7**

///|
/// 生成器：含故障、无运行时不变量的小规模消息场景（终态由故障 / 轨迹确定）。
fn p15_gen() -> @infra_pbt.Gen[(UInt64, DesScenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 4)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "t\{i}"))
    }
    let fc = rng.next_range(0, 2)
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
/// **Validates: Requirements 8.4, 8.7**
test "Feature: dst, Property 15: persist-restore-replay fidelity" {
  let ok = @infra_pbt.holds_for_all(p15_gen(), fn(pair) {
    let (seed, sc) = pair
    let r = run_des(seed, sc)
    let text = serialize_result(r)
    match deserialize_result(text) {
      Ok(rp) => {
        let replayed = replay_des(rp.seed, rp.trace)
        replayed.status == r.status && replayed.trace == r.trace
      }
      Err(_) => false
    }
  })
  assert_true(ok)
}
