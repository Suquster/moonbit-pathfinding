// demo_test.mbt —— 受监督工作池端到端单元测试（任务 14.3）。
//
// 覆盖两个代表性场景的可观测见证（复用 demo.mbt 的 `worker_pool_demo` /
// `Task` / `WorkerPoolReport`）：
//
//   ① 无失败场景（fault_at = None）：所有任务完成、零重启、coordinator 收到
//      全部 worker 的 `Terminated`（R11.4）、ask 取回各 worker 完成计数（R11.5）；
//   ② 单点失败场景（fault_at = Some(i)）：OneForOne 仅重启该 worker（R11.3）、
//      未失败结果不丢失（completed == 可完成任务数）、coordinator 收到 `Terminated`
//      （R11.4）、ask 取回结果（R11.5）。
//
// 输入与种子稳定具体，断言确定可重放的结果值（assert_eq + inspect 快照）。
//
// _Requirements: 11.3, 11.4, 11.5_

///|
/// 构造一个稳定的 6 任务批次（id 0..5，payload 递增），供两个场景共用。
fn demo_sample_tasks() -> Array[Task] {
  [
    { id: 0, payload: 10 },
    { id: 1, payload: 20 },
    { id: 2, payload: 30 },
    { id: 3, payload: 40 },
    { id: 4, payload: 50 },
    { id: 5, payload: 60 },
  ]
}

///|
/// 无失败场景见证（R11.4 / R11.5）：
///
///   * 6 个任务经 RoundRobin 分发到 3 个 worker（各 2 个），全部完成；
///   * 无注入失败 → 累计重启次数为 0；
///   * coordinator 监视全部 worker，停止阶段恰收到 3 条 `Terminated`（R11.4）；
///   * ask 取回各 worker 的完成计数：每个 worker 各完成 2 个任务（R11.5）。
test "worker pool with no fault completes all tasks with zero restarts (witness)" {
  let tasks = demo_sample_tasks()
  let report = worker_pool_demo(3, tasks, None, 42)
  // 所有任务完成、零重启。
  assert_eq(report.completed, 6)
  assert_eq(report.restarts, 0)
  // coordinator 收到全部 3 个 worker 的 Terminated（停止后，R11.4）。
  assert_eq(report.terminated_seen.length(), 3)
  inspect(
    report.terminated_seen,
    content="[{value: 2}, {value: 3}, {value: 4}]",
  )
  // ask 取回各 worker 完成计数（R11.5）：6 任务轮询到 3 worker，各 2。
  inspect(report.ask_results, content="[Replied(2), Replied(2), Replied(2)]")
}

///|
/// 单点失败场景见证（R11.3 / R11.4 / R11.5）：
///
///   * `fault_at = Some(1)`：第 2 个任务（轮询命中 worker#1）被注入失败 →
///     OneForOne 下仅重启 worker#1，其余 worker 不受影响（restarts == 1，R11.3）；
///   * 未失败结果不丢失：可完成任务数 = 6 − 1 = 5（completed == 5）；
///   * coordinator 仍收到全部 3 个 worker 的 `Terminated`（停止阶段，R11.4）；
///   * ask 取回结果（R11.5）：被重启的 worker#1 重启后仅完成其后续任务（1 个），
///     其余两个 worker 各完成 2 个。
test "worker pool with single fault restarts only that worker without losing results (witness)" {
  let tasks = demo_sample_tasks()
  let report = worker_pool_demo(3, tasks, Some(1), 7)
  // OneForOne 仅重启该 worker：恰发生一次重启（R11.3）。
  assert_true(report.restarts >= 1)
  assert_eq(report.restarts, 1)
  // 未失败结果不丢失：可完成任务数 = 总数 − 注入失败数。
  assert_eq(report.completed, 5)
  // coordinator 收到 Terminated（R11.4）。
  assert_eq(report.terminated_seen.length(), 3)
  inspect(
    report.terminated_seen,
    content="[{value: 2}, {value: 3}, {value: 4}]",
  )
  // ask 取回结果（R11.5）：worker#1 重启后仅完成 1 个，其余各 2 个。
  inspect(report.ask_results, content="[Replied(2), Replied(1), Replied(2)]")
}

///|
/// 确定性可重放见证：同一输入与种子两次运行产生逐字段一致的报告（R10 支撑 R11）。
test "worker pool demo is deterministic for the same seed (witness)" {
  let r1 = worker_pool_demo(3, demo_sample_tasks(), Some(1), 7)
  let r2 = worker_pool_demo(3, demo_sample_tasks(), Some(1), 7)
  assert_eq(r1, r2)
}
