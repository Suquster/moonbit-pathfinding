// prop_termination_test.mbt —— Property 4：仿真循环终止性（任务 8.5）。
//
// Feature: dst, Property 4: 仿真循环终止性（run_des 在有限步内终止，执行步数不超过
// max_steps，终止时队空或达上限，不存在无限循环）。
//
// **Validates: Requirements 2.5**

///|
/// 生成器：含消息与故障的小规模场景，且 max_steps 可能很小以检验步数上界。
fn p4_gen() -> @infra_pbt.Gen[(UInt64, DesScenario, Int, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 5)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "r\{i}"))
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
    let ms = rng.next_range(1, n + 5)
    let sc = DesScenario::new(tasks, faults, [], replication_protocol(n), ms)
    (rng.next(), sc, n, ms)
  })
}

///|
/// **Validates: Requirements 2.5**
test "Feature: dst, Property 4: simulation loop terminates within max_steps" {
  let ok = @infra_pbt.holds_for_all(p4_gen(), fn(t) {
    let (seed, sc, n, ms) = t
    let r = run_des(seed, sc)
    // 唤醒（调度）步数不超过任务数，且不超过步数上限。
    let scheduled = des_scheduled_ids(r.trace).length()
    scheduled <= n && scheduled <= ms
  })
  assert_true(ok)
}
