// prop_replay_test.mbt —— DST_Framework 确定性可重放不变量属性测试（任务 13.3）。
//
// Property 19：DST 确定性可重放不变量
//   *对任意* 给定的随机种子，两次仿真运行应产生逐事件一致的调度序列与最终
//   状态；并且使用某次失败运行所输出的种子与轨迹重放，应复现完全相同的失败。
//
// **Validates: Requirements 8.2, 8.6**
//
// 实现要点：
//   * 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板，每条
//     属性 ≥100 次迭代（由 `holds_for_all` 默认 `iters=100` 保证）。
//   * 生成器产出「随机种子 + 随机 Scenario」二元组：随机任务集、随机故障策略
//     （覆盖 Crash / Delay / Drop 三类）与随机 `max_steps`，覆盖正常完成与崩溃
//     失败两类终态。
//   * 注意：@infra_pbt 的 `Rng` 仅为属性测试的输入采样驱动；被测的确定性随机
//     源是 dst 运行时自有的 `Rng`（由 `run` / `replay` 内部使用），二者解耦。

///|
/// 由 @infra_pbt 随机源采样一个 DST 故障类型（覆盖 Crash / Delay / Drop）。
fn sample_fault_kind(rng : @infra_pbt.Rng) -> FaultKind {
  match rng.next_below(3) {
    0 => FaultKind::Crash
    1 => FaultKind::Delay
    _ => FaultKind::Drop
  }
}

///|
/// 生成器：「随机种子 + 随机 Scenario」二元组。
///
/// 采样空间（智能约束到有意义的输入域）：
///   * `seed`      —— 直接取随机源的下一个 64 位字，覆盖整个种子空间；
///   * 任务数      —— `[1, 6]`，保证至少一个任务，避免退化为空调度；
///   * 任务集      —— id 取 `0 ..< n`、名称为 `t{i}`；
///   * 故障数      —— `[0, 3]`，覆盖「无故障」与「多故障」场景；
///   * 单条故障    —— `at_step ∈ [0, n]`、`task_id ∈ [0, n)`、`kind` 三类随机；
///   * `max_steps` —— `[n, n + 8]`，足以让全部任务在无故障时完成。
fn gen_seed_and_scenario() -> @infra_pbt.Gen[(UInt64, Scenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let seed = rng.next()
    let task_count = rng.next_range(1, 6)
    let tasks : Array[Task] = []
    for i in 0..<task_count {
      tasks.push(Task::new(i, "t\{i}"))
    }
    let fault_count = rng.next_range(0, 3)
    let faults : Array[FaultPolicy] = []
    for _ in 0..<fault_count {
      let at_step = rng.next_range(0, task_count)
      let task_id = rng.next_below(task_count)
      faults.push(FaultPolicy::new(at_step, task_id, sample_fault_kind(rng)))
    }
    let max_steps = rng.next_range(task_count, task_count + 8)
    (seed, Scenario::new(tasks, faults, max_steps))
  })
}

///|
/// Feature: moonbit-infra-suite, Property 19: DST 确定性可重放不变量
///
/// *对任意* 随机种子与场景：
///   (1) 同种子两次运行结果完全一致（逐事件调度序列 + 终态，由 `SimResult`
///       的 `derive(Eq)` 整体逐项比对）—— Requirement 8.2；
///   (2) 以该运行输出的种子与事件轨迹重放，复现完全相同的结果（含失败）——
///       Requirement 8.6。
///
/// **Validates: Requirements 8.2, 8.6**
test "Feature: moonbit-infra-suite, Property 19: deterministic replay invariant" {
  let ok = @infra_pbt.holds_for_all(gen_seed_and_scenario(), fn(pair) {
    let (seed, scenario) = pair
    // (1) 同种子 → 同执行：两次运行逐事件 + 终态一致（Requirement 8.2）。
    let first = run(seed, scenario)
    let second = run(seed, scenario)
    if first != second {
      return false
    }
    // (2) 重放复现：以输出的种子 + 轨迹重放，结果与原运行完全一致（Requirement 8.6）。
    let replayed = replay(first.seed, first.trace)
    replayed == first
  })
  assert_true(ok)
}
