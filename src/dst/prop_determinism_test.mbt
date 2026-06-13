// prop_determinism_test.mbt —— Property 1：同种子确定性（任务 8.3）。
//
// Feature: dst, Property 1: 同种子确定性（同 seed 与 scenario 两次 run_des 产出
// DesResult 逐字段一致；对「无消息、仅遗留故障」场景，of_legacy 提升后的 EvScheduled
// 任务投影与既有 run 同种子下 Scheduled 任务序列一致）。
//
// **Validates: Requirements 1.1, 1.4, 1.5, 12.3**
//
// 差分对照：以既有 `run` 作为 of_legacy 提升场景的调度 oracle。

///|
/// 采样一个既有故障类型（覆盖 Crash / Delay / Drop）。
fn p1_fault_kind(rng : @infra_pbt.Rng) -> FaultKind {
  match rng.next_below(3) {
    0 => FaultKind::Crash
    1 => FaultKind::Delay
    _ => FaultKind::Drop
  }
}

///|
/// 生成器：「随机种子 + 随机既有 Scenario」（无消息、仅遗留故障）。
fn p1_gen() -> @infra_pbt.Gen[(UInt64, Scenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let seed = rng.next()
    let tc = rng.next_range(1, 5)
    let tasks : Array[Task] = []
    for i in 0..<tc {
      tasks.push(Task::new(i, "t\{i}"))
    }
    let fc = rng.next_range(0, 3)
    let faults : Array[FaultPolicy] = []
    for _ in 0..<fc {
      faults.push(
        FaultPolicy::new(rng.next_range(0, tc), rng.next_below(tc), p1_fault_kind(rng)),
      )
    }
    let ms = rng.next_range(tc, tc + 8)
    (seed, Scenario::new(tasks, faults, ms))
  })
}

///|
/// **Validates: Requirements 1.1, 1.4, 1.5, 12.3**
test "Feature: dst, Property 1: deterministic run_des and of_legacy schedule parity" {
  let ok = @infra_pbt.holds_for_all(p1_gen(), fn(pair) {
    let (seed, scenario) = pair
    let des = DesScenario::of_legacy(scenario, protocol=null_protocol())
    // (1) 同种子两次 run_des 逐字段一致。
    let r1 = run_des(seed, des)
    let r2 = run_des(seed, des)
    if r1 != r2 {
      return false
    }
    // (2) of_legacy 提升后 EvScheduled 投影 == 既有 run 同种子下 Scheduled 投影。
    let leg = run(seed, scenario)
    des_scheduled_ids(r1.trace) == legacy_scheduled_ids(leg.trace)
  })
  assert_true(ok)
}
