// explore_test.mbt —— 有界穷尽探索单元测试（任务 11.2）。
//
// 覆盖 explored 计数与已知小场景期望值一致、failing 携带的 seed+trace 经 replay_des
// 复现失败的见证（R5.3 / R5.4）。

///|
/// 三个独立任务的全部交错恰为 3! = 6，且无故障 → 无失败交错。
test "explore_bounded counts all interleavings of independent tasks" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let sc = DesScenario::new(tasks, [], [], null_protocol(), 8)
  let rep = explore_bounded(1, sc, 3)
  assert_eq(rep.explored, 6)
  match rep.failing {
    None => ()
    Some(_) => fail("no failing interleaving expected")
  }
}

///|
/// 崩溃故障使存在失败交错；其 seed+trace 经 replay_des 复现失败。
test "explore_bounded surfaces a replayable failing interleaving" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b")]
  let sc = DesScenario::new(
    tasks,
    [FaultPolicyEx::new(0, 0, NetFaultKind::Crash)],
    [],
    null_protocol(),
    8,
  )
  let rep = explore_bounded(3, sc, 2)
  match rep.failing {
    Some((s, tr)) => {
      let r = replay_des(s, tr)
      match r.status {
        Failed(..) => ()
        Completed => fail("replay of failing interleaving should fail")
      }
    }
    None => fail("expected a failing interleaving")
  }
}
