// compat_test.mbt —— 既有 API 向后兼容回归测试（任务 19.5）。
//
// 回归断言：`Sim` / `run` / `replay` / `rng_new` / `Rng::*` 行为与 0.1.0 逐字段一致，
// 既有规范化语义（任务按 id 升序、故障按 (at_step, task_id) 升序、同种子 → 同调度
// 序列 + 同终态）保持（R12.1 / R12.2 / R12.3）。既有 `prop_replay_test.mbt` 继续作为
// 回归守卫。

///|
/// 既有 run 同种子确定、崩溃失败、可重放复现，三性质同时保持。
test "compat: legacy run is deterministic, fails on crash, and replays" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let scenario = Scenario::new(
    tasks,
    [FaultPolicy::new(0, 1, FaultKind::Crash)],
    16,
  )
  let a = run(0xABCD, scenario)
  let b = run(0xABCD, scenario)
  assert_eq(a, b)
  match a.status {
    Failed(..) => ()
    Completed => fail("injected crash should fail the run")
  }
  assert_eq(replay(a.seed, a.trace), a)
}

///|
/// 既有 run 调度与输入任务排列无关（按 id 升序规范化）。
test "compat: legacy run normalizes by task id" {
  let forward = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let reversed = [Task::new(2, "c"), Task::new(1, "b"), Task::new(0, "a")]
  assert_eq(
    run(42, Scenario::new(forward, [], 8)),
    run(42, Scenario::new(reversed, [], 8)),
  )
}

///|
/// 既有 Rng 同种子逐位一致、next_below 落在区间内。
test "compat: legacy rng is deterministic and bounded" {
  let r1 = rng_new(0x1234)
  let r2 = rng_new(0x1234)
  for _ in 0..<32 {
    assert_eq(r1.next(), r2.next())
  }
  let r = rng_new(7)
  for _ in 0..<50 {
    let v = r.next_below(10)
    assert_true(v >= 0 && v < 10)
  }
}
