// scheduler_gaps81_test.mbt —— 观测辅助对未登记 actor 的余臂（第八十一批）。

///|
/// 跨调度器查询：他处派生的 actor 未登记于本调度器，观测辅助返回缺省值。
test "scheduler：未登记 actor 观测缺省" {
  let sched_a : Scheduler[Int, Int] = Scheduler::new()
  let sched_b : Scheduler[Int, Int] = Scheduler::new()
  let foreign = sched_b.spawn(0, fn(s, m) { Updated(s + m) })
  assert_true(sched_a.state_of(foreign) is None)
  assert_true(sched_a.status_of(foreign) is None)
  assert_false(sched_a.is_running(foreign))
  assert_eq(sched_a.pending(foreign), 0)
}
