// prop_time_order_test.mbt —— Property 2：虚拟时间单调性与事件全序（任务 8.4）。
//
// Feature: dst, Property 2: 虚拟时间单调性与事件全序（trace 相邻事件逻辑时间戳单调
// 不减；同一时间戳内相邻事件按「(任务 id 升序, 次序键升序)」非降——本引擎为每个处理
// 动作分配严格递增时间戳且同动作事件归属同一节点，故等时间戳内任务 id 恒等）。
//
// **Validates: Requirements 1.2, 1.3, 1.6**

///|
/// 生成器：含消息与随机故障的小规模场景。
fn p2_gen() -> @infra_pbt.Gen[(UInt64, DesScenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 4)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "r\{i}"))
    }
    let fc = rng.next_range(0, 3)
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
/// 校验轨迹满足全序：相邻事件时间戳非降，且等时间戳内主任务 id 非降。
fn p2_in_total_order(trace : Array[SimEvent]) -> Bool {
  let mut i = 0
  while i < trace.length() - 1 {
    let a = trace[i]
    let b = trace[i + 1]
    if a.time_of() > b.time_of() {
      return false
    }
    if a.time_of() == b.time_of() && a.actor_of() > b.actor_of() {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// **Validates: Requirements 1.2, 1.3, 1.6**
test "Feature: dst, Property 2: virtual time monotonicity and event total order" {
  let ok = @infra_pbt.holds_for_all(p2_gen(), fn(pair) {
    let (seed, sc) = pair
    let r = run_des(seed, sc)
    p2_in_total_order(r.trace)
  })
  assert_true(ok)
}
