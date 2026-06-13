// prop_explore_complete_test.mbt —— Property 9：有界穷尽探索完整性（任务 11.3）。
//
// Feature: dst, Property 9: 有界穷尽探索完整性（explore_bounded 枚举的交错集合恰等于
// 参考枚举器在该深度内的全部可达交错，explored 等于集合大小；失败交错经 replay_des
// 复现）。
//
// **Validates: Requirements 5.1, 5.3, 5.5**
//
// 参考 oracle：n 个独立任务的全部可达交错数恰为 n!（参考枚举器即排列计数）。

///|
/// 生成器：随机种子 + 小规模任务数（1..4）。
fn p9_gen() -> @infra_pbt.Gen[(UInt64, Int)] {
  @infra_pbt.Gen::new(fn(rng) { (rng.next(), rng.next_range(1, 4)) })
}

///|
/// 探索枚举到该深度内每一个可达交错：explored 恰为 n!（与参考枚举器一致）。
///
/// **Validates: Requirements 5.1, 5.5**
test "Feature: dst, Property 9: bounded exploration enumerates exactly n! interleavings" {
  let ok = @infra_pbt.holds_for_all(p9_gen(), fn(t) {
    let (seed, n) = t
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "t\{i}"))
    }
    let sc = DesScenario::new(tasks, [], [], null_protocol(), n + 4)
    let rep = explore_bounded(seed, sc, n)
    rep.explored == factorial(n)
  })
  assert_true(ok)
}

///|
/// 失败交错经 replay_des 复现（以崩溃故障构造轨迹内可复现的失败）。
///
/// **Validates: Requirements 5.3**
test "Feature: dst, Property 9: failing interleaving is replayable" {
  let ok = @infra_pbt.holds_for_all(@infra_pbt.gen_int_range(1, 100000), fn(k) {
    let tasks = [Task::new(0, "a"), Task::new(1, "b")]
    let sc = DesScenario::new(
      tasks,
      [FaultPolicyEx::new(0, 0, NetFaultKind::Crash)],
      [],
      null_protocol(),
      8,
    )
    let rep = explore_bounded(k.to_uint64(), sc, 2)
    match rep.failing {
      Some((s, tr)) => {
        let r = replay_des(s, tr)
        match r.status {
          Failed(..) => true
          Completed => false
        }
      }
      None => false
    }
  })
  assert_true(ok)
}
