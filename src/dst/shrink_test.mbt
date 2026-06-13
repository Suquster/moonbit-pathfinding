// shrink_test.mbt —— 失败收缩单元测试（任务 10.2）。
//
// 覆盖非失败场景返回 NotFailing、移除任务 / 移除故障 / 缩减 max_steps 三算子缩小
// 反例的见证（R4.4 / R4.5）。

///|
/// 非失败场景：返回 NotFailing，不返回任意场景。
test "shrink reports NotFailing for a completing scenario" {
  let oc = shrink(1, demo_replication_scenario(3))
  assert_false(oc.is_minimal())
  match oc.scenario() {
    None => ()
    Some(_) => fail("expected NotFailing for a completing scenario")
  }
}

///|
/// 失败场景：三算子协同缩小反例至更小规模，且仍失败。
test "shrink minimizes tasks/faults/max_steps while preserving failure" {
  let inv = Invariant::new("强制失败", fn(_w) { false })
  let sc = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")],
    [
      FaultPolicyEx::new(1, 0, NetFaultKind::Drop),
      FaultPolicyEx::new(2, 1, NetFaultKind::Delay(by=1UL)),
    ],
    [inv],
    null_protocol(),
    10,
  )
  let oc = shrink(7, sc)
  match oc.scenario() {
    Some(s2) => {
      assert_true(s2.size() < sc.size())
      assert_true(default_fails(run_des(7, s2)))
    }
    None => fail("expected Minimal counterexample")
  }
}
