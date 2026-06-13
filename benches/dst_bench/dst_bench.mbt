// benches/dst_bench — native benchmarks and smoke guards for DST_Framework.
//
// Workloads (Requirement 10.1): run_des / replay_des / explore_bounded /
// explore_dpor / shrink. Plus a DPOR partial-order reduction-ratio guard
// (Requirement 10.3): for n independent tasks, bounded exhaustive explores
// n! interleavings while DPOR explores a single representative.
//
// Run (native): `export LIBRARY_PATH=/usr/lib64:/usr/lib && moon bench --target native`.
//
// _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

///|
/// 构造 n 个相互独立任务的场景（空协议，无消息）—— 交错探索基准工作负载。
fn indep_scenario(n : Int) -> @dst.DesScenario {
  let tasks : Array[@dst.Task] = []
  for i in 0..<n {
    tasks.push(@dst.Task::new(i, "t"))
  }
  @dst.DesScenario::new(tasks, [], [], @dst.null_protocol(), n + 6)
}

///|
/// 构造必然失败的场景（附恒假不变量 + 若干故障）—— 收缩基准工作负载。
fn failing_scenario(n : Int) -> @dst.DesScenario {
  let tasks : Array[@dst.Task] = []
  for i in 0..<n {
    tasks.push(@dst.Task::new(i, "t"))
  }
  let faults : Array[@dst.FaultPolicyEx] = []
  for i in 0..<n {
    faults.push(@dst.FaultPolicyEx::new(i % 3, i, @dst.NetFaultKind::Drop))
  }
  let inv = @dst.Invariant::new("bad", fn(_w) { false })
  @dst.DesScenario::new(tasks, faults, [inv], @dst.null_protocol(), n + 6)
}

///|
/// Smoke guard：大规模复制场景的 run_des 推进并产生事件轨迹。
test "smoke: run_des drives a large replication scenario" {
  let r = @dst.run_des(1, @dst.demo_replication_scenario(8))
  assert_true(r.trace.length() >= 1)
}

///|
/// Smoke guard / 回归 guard：DPOR 偏序约简比——独立任务下有界穷尽探索枚举 6! = 720
/// 个交错，而 DPOR 仅探索 1 个代表（约简比 720:1）。
test "smoke: DPOR reduction ratio for independent tasks" {
  let sc = indep_scenario(6)
  let b = @dst.explore_bounded(1, sc, 6)
  let d = @dst.explore_dpor(1, sc, 6)
  assert_eq(b.explored, 720)
  assert_eq(d.explored, 1)
  assert_true(d.explored <= b.explored)
}

///|
/// Smoke guard：收缩对失败场景产出最小反例。
test "smoke: shrink minimizes a failing scenario" {
  let oc = @dst.shrink(1, failing_scenario(6))
  assert_true(oc.is_minimal())
}

///|
/// Bench：大规模复制场景的 run_des。
test "bench: run_des on a 24-replica scenario" (b : @bench.T) {
  let sc = @dst.demo_replication_scenario(24)
  b.bench(name="dst_run_des_24replicas", fn() { b.keep(@dst.run_des(1, sc)) })
}

///|
/// Bench：记录轨迹的 replay_des 复现。
test "bench: replay_des on a recorded trace" (b : @bench.T) {
  let r = @dst.run_des(1, @dst.demo_replication_scenario(24))
  b.bench(name="dst_replay_des_24replicas", fn() {
    b.keep(@dst.replay_des(r.seed, r.trace))
  })
}

///|
/// Bench：7 个独立任务的有界穷尽交错探索（7! = 5040 个交错）。
test "bench: explore_bounded on 7 independent tasks" (b : @bench.T) {
  let sc = indep_scenario(7)
  b.bench(name="dst_explore_bounded_7tasks", fn() {
    b.keep(@dst.explore_bounded(1, sc, 7))
  })
}

///|
/// Bench：7 个独立任务的 DPOR 偏序约简探索（约简至 1 个代表交错）。
test "bench: explore_dpor on 7 independent tasks" (b : @bench.T) {
  let sc = indep_scenario(7)
  b.bench(name="dst_explore_dpor_7tasks", fn() {
    b.keep(@dst.explore_dpor(1, sc, 7))
  })
}

///|
/// Bench：失败场景的 delta-debugging 收缩。
test "bench: shrink on a failing scenario" (b : @bench.T) {
  let sc = failing_scenario(10)
  b.bench(name="dst_shrink_10tasks", fn() { b.keep(@dst.shrink(1, sc)) })
}
