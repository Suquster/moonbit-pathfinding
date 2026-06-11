// sim_test.mbt —— DST_Framework 调度 / 故障注入 / 重放（任务 13.2）的单元测试。
//
// 覆盖任务 13.2 三项核心契约（完整的确定性可重放属性测试属任务 13.3）：
//   * 同种子 → 同调度序列 + 同终态（且不依赖输入任务排列）；
//   * 故障注入在命中注入点时产生 `Faulted` 事件，崩溃故障令终态为 `Failed`；
//   * `replay(seed, trace)` 复现与原 `run` 完全一致的结果。

///|
/// 统计事件轨迹中 `Completed` 事件数（用于校验任务是否全部完成）。
fn count_completed(trace : Array[Event]) -> Int {
  let mut n = 0
  for e in trace {
    match e {
      Completed(..) => n += 1
      _ => ()
    }
  }
  n
}

///|
/// 判定事件轨迹中是否存在指定类型的故障事件。
fn has_fault(trace : Array[Event], want : FaultKind) -> Bool {
  for e in trace {
    match e {
      Faulted(kind~, ..) => if kind == want { return true }
      _ => ()
    }
  }
  false
}

///|
/// 同种子 → 同执行：两次以相同种子运行同一场景，结果逐事件一致且终态相同。
test "run is deterministic for the same seed" {
  let tasks = [
    Task::new(0, "build"),
    Task::new(1, "test"),
    Task::new(2, "lint"),
    Task::new(3, "package"),
  ]
  let scenario = Scenario::new(tasks, [], 16)
  let a = run(0xDEAD_BEEF, scenario)
  let b = run(0xDEAD_BEEF, scenario)
  // SimResult derive(Eq)：种子 + 轨迹 + 终态整体逐项一致。
  assert_eq(a, b)
}

///|
/// 不同种子通常产生不同的调度序列（随机源具备区分度，调度非退化为常量）。
test "run diverges for different seeds" {
  let tasks = [
    Task::new(0, "a"),
    Task::new(1, "b"),
    Task::new(2, "c"),
    Task::new(3, "d"),
    Task::new(4, "e"),
  ]
  let scenario = Scenario::new(tasks, [], 16)
  let a = run(1, scenario)
  let b = run(999, scenario)
  assert_not_eq(a.trace, b.trace)
}

///|
/// 调度序列不依赖输入任务排列：升序与逆序的同一任务集在同种子下产生一致结果
/// （得益于 run 以任务 id 升序规范化待调度集合）。
test "run schedule is independent of input task ordering" {
  let forward = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let reversed = [Task::new(2, "c"), Task::new(1, "b"), Task::new(0, "a")]
  let r1 = run(42, Scenario::new(forward, [], 8))
  let r2 = run(42, Scenario::new(reversed, [], 8))
  assert_eq(r1, r2)
}

///|
/// 无故障场景：所有任务最终完成，终态为 `Completed`。
test "run completes all tasks when no faults are injected" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let result = run(7, Scenario::new(tasks, [], 16))
  assert_eq(count_completed(result.trace), 3)
  match result.status {
    Completed => ()
    Failed(reason~) => fail("expected Completed, got Failed: \{reason}")
  }
}

///|
/// 崩溃故障：在命中注入点触发 `Faulted(Crash)`，目标任务不再完成，终态为
/// `Failed`，且其余任务仍正常完成（崩溃隔离）。
test "inject_fault triggers a Faulted event and fails the run on crash" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let faults = [FaultPolicy::new(0, 1, FaultKind::Crash)]
  let result = run(123, Scenario::new(tasks, faults, 16))
  // 产生崩溃故障事件。
  assert_true(has_fault(result.trace, FaultKind::Crash))
  // 崩溃任务被移出调度集合：仅其余 2 个任务完成。
  assert_eq(count_completed(result.trace), 2)
  // 终态为 Failed。
  match result.status {
    Failed(..) => ()
    Completed => fail("expected Failed due to injected crash")
  }
}

///|
/// 丢弃故障：被丢弃的任务永不调度，其余任务正常完成，终态仍为 `Completed`
/// （丢弃为非致命故障）。
test "inject_fault drops a task without failing the run" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let faults = [FaultPolicy::new(0, 2, FaultKind::Drop)]
  let result = run(55, Scenario::new(tasks, faults, 16))
  assert_true(has_fault(result.trace, FaultKind::Drop))
  assert_eq(count_completed(result.trace), 2)
  match result.status {
    Completed => ()
    Failed(reason~) => fail("expected Completed, got Failed: \{reason}")
  }
}

///|
/// 重放复现：以失败运行输出的种子与轨迹重放，复现完全相同的结果。
test "replay reproduces the identical failing result" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let faults = [FaultPolicy::new(1, 0, FaultKind::Crash)]
  let original = run(0x1234, Scenario::new(tasks, faults, 16))
  let replayed = replay(original.seed, original.trace)
  // 种子、逐事件轨迹与终态完全一致。
  assert_eq(replayed, original)
}

///|
/// 重放复现（正常完成）：成功运行同样可被精确重放。
test "replay reproduces a successful run" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b")]
  let original = run(2024, Scenario::new(tasks, [], 8))
  let replayed = replay(original.seed, original.trace)
  assert_eq(replayed, original)
}
