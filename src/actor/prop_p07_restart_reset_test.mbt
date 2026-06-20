// prop_p07_restart_reset_test.mbt —— Property 7：重启状态重置且按序调用钩子（任务 2.2）。
//
//   Feature: actor, Property 7: 重启状态重置且按序调用钩子
//   ------------------------------------------------------------------
//   *对任意* 初始状态与失败前消息历史，重启后的 actor 状态等于「以初始状态为
//   起点、不重放失败前消息」的状态，且重启过程严格按 `pre_restart → 重置 →
//   post_restart` 顺序进行。
//
// **Validates: Requirements 3.3, 3.5, 3.6**
//
// 建模方式：状态为 `Array[Int]`，失败前累积若干消息（append）。重启时 `restart_state`
// 以初始状态为基准、不重放历史；并以一个共享日志见证钩子调用顺序。

///|
/// 逐位比较两个 Int 数组。
fn p07_eq(xs : Array[Int], ys : Array[Int]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  for i in 0..<xs.length() {
    if xs[i] != ys[i] {
      return false
    }
  }
  true
}

///|
/// 单次场景：构造带钩子调用日志的 LifecycleHooks，累积失败前状态后重启，
/// 断言重启后状态等于「post_restart(初始状态)」且钩子按 pre_restart → post_restart 顺序。
fn p07_restart_reset(rng : @infra_pbt.Rng) -> Bool {
  // 钩子调用顺序日志（字符串标签）。
  let log : Array[String] = []
  // 初始状态：单元素数组（重启基准）。
  let seed = rng.next_range(-50, 50)
  let init : Array[Int] = [seed]
  let hooks : LifecycleHooks[Array[Int]] = LifecycleHooks::new(
    fn(s) {
      log.push("pre_start")
      s
    },
    fn(_s) { log.push("post_stop") },
    fn(_s, _reason) { log.push("pre_restart") },
    fn(s) {
      log.push("post_restart")
      // post_restart 以初始状态副本为基准，确保不沿用失败前状态。
      [s[0]]
    },
  )
  // 失败前累积消息历史（模拟处理若干消息后状态发生变化）。
  let current : Array[Int] = [seed]
  let hist = rng.next_range(0, 10)
  for _i in 0..<hist {
    current.push(rng.next_range(-100, 100))
  }
  // 触发重启。
  let restarted = restart_state(init, hooks, current, "boom")
  // (1) 重启后状态等于「以初始状态为起点、不重放历史」。
  if !p07_eq(restarted, [seed]) {
    return false
  }
  // (2) 钩子按序：pre_restart 在 post_restart 之前，且二者各恰一次。
  if log.length() != 2 {
    return false
  }
  log[0] == "pre_restart" && log[1] == "post_restart"
}

///|
/// Feature: actor, Property 7: 重启状态重置且按序调用钩子（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.3, 3.5, 3.6**
test "Feature: actor, Property 7: restart resets to initial state and calls hooks in order (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p07_restart_reset(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
