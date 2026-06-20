// lifecycle_test.mbt —— lifecycle.mbt 单元测试（任务 2.3）。
//
// 覆盖：钩子调用顺序见证、identity() 默认行为见证。
// _Requirements: 3.1, 3.3_

///|
/// identity() 默认行为见证：pre_start / post_restart 为恒等，post_stop / pre_restart 空操作。
test "LifecycleHooks identity is the identity on state and no-op on side effects" {
  let hooks : LifecycleHooks[Int] = LifecycleHooks::identity()
  // pre_start 恒等。
  assert_eq(start_state(42, hooks), 42)
  // restart_state 以初始状态重置（恒等 post_restart）。
  assert_eq(restart_state(42, hooks, 999, "boom"), 42)
  // post_stop / pre_restart 为空操作，不影响状态语义（此处仅确认可调用）。
  (hooks.post_stop)(42)
  (hooks.pre_restart)(42, "boom")
}

///|
/// 钩子调用顺序见证：restart_state 严格按 pre_restart → post_restart 调用。
test "restart_state calls pre_restart then post_restart in order" {
  let log : Array[String] = []
  let hooks : LifecycleHooks[Int] = LifecycleHooks::new(
    fn(s) {
      log.push("pre_start")
      s
    },
    fn(_s) { log.push("post_stop") },
    fn(_s, _r) { log.push("pre_restart") },
    fn(s) {
      log.push("post_restart")
      s
    },
  )
  let out = restart_state(7, hooks, 100, "err")
  // 以初始状态 7 重置。
  assert_eq(out, 7)
  assert_eq(log, ["pre_restart", "post_restart"])
}

///|
/// TerminationReason 派生 Eq / Show 见证。
test "TerminationReason derives Eq and Show" {
  let normal : TerminationReason = StoppedNormally
  let failed_x : TerminationReason = FailedWith("x")
  let failed_a : TerminationReason = FailedWith("a")
  let failed_b : TerminationReason = FailedWith("b")
  assert_eq(normal, StoppedNormally)
  assert_eq(failed_x, FailedWith("x"))
  assert_true(failed_a != failed_b)
  assert_eq("\{normal}", "StoppedNormally")
}
