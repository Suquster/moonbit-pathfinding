// prop_p30_worker_pool_test.mbt —— Property 30：工作池韧性（任务 14.2）。
//
//   Feature: actor, Property 30: 工作池韧性
//   ------------------------------------------------------------------
//   *对任意* 由生成器产生的任务批次与单点注入失败，受监督工作池在 `OneForOne`
//   重启后**最终完成所有可完成任务**，且**未失败 worker 的处理结果不丢失**。
//
//   语义对照（见 demo.mbt 的 `worker_pool_demo` / `WorkerPoolReport`）：
//     * 注入失败的任务（`FaultTask`）令该 worker `Errored` → OneForOne 仅重启该
//       worker，失败消息被丢弃且不重放（R3.4）；其它任务（`RunTask`）全部完成。
//     * `completed_ref` 跨重启持久，已完成计数不因某 worker 重启而回退（结果不丢失）。
//
//   因此「可完成任务数」= 任务总数 − 注入失败任务数（单点注入时恰为 1，无注入为 0），
//   且当且仅当发生单点注入失败时，累计重启次数 ≥ 1。
//
// **Validates: Requirements 11.7**

///|
/// 随机生成一个任务批次：长度 `n ∈ [1, 12]`，每个任务带确定性 `id` 与随机 `payload`。
fn p30_gen_tasks(rng : @infra_pbt.Rng, n : Int) -> Array[Task] {
  let tasks : Array[Task] = []
  for i in 0..<n {
    tasks.push({ id: i, payload: rng.next_range(-100, 100) })
  }
  tasks
}

///|
/// 单次场景：随机 worker 数、任务批次与「单点注入 / 无注入」二选一，运行工作池后校验：
///
///   ① 完成总数 == 可完成任务数（= 总数 − 注入失败数）——「最终完成所有可完成任务」
///      且「未失败 worker 结果不丢失」（否则计数会因重启回退而偏小）；
///   ② 注入失败 ⇔ 累计重启次数 ≥ 1（OneForOne 重启确实发生且仅由注入失败触发）。
fn p30_worker_pool_resilient(rng : @infra_pbt.Rng) -> Bool {
  let worker_count = rng.next_range(1, 5)
  let n = rng.next_range(1, 12)
  let tasks = p30_gen_tasks(rng, n)
  let seed = rng.next()

  // 二选一：约 2/3 概率注入单点失败（索引经 next_below 落在 [0, n) 内），其余无注入。
  let fault_at : Int? = if rng.next_range(0, 3) == 0 {
    None
  } else {
    Some(rng.next_below(n))
  }
  let injected = match fault_at {
    Some(_) => 1
    None => 0
  }
  let report = worker_pool_demo(worker_count, tasks, fault_at, seed)

  // ① 可完成任务全部完成，且结果不丢失。
  if report.completed != n - injected {
    return false
  }

  // ② 注入失败当且仅当触发重启（OneForOne 重启确实发生）。
  let restarted = report.restarts >= 1
  restarted == (injected == 1)
}

///|
/// Feature: actor, Property 30: 工作池韧性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 11.7**
test "Feature: actor, Property 30: supervised worker pool completes all completable tasks after OneForOne restart (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p30_worker_pool_resilient(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
