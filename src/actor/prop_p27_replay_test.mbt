// prop_p27_replay_test.mbt —— Property 27：重放确定性（任务 11.19）。
//
//   Feature: actor, Property 27: 重放确定性
//   ------------------------------------------------------------------
//   *对任意* 种子与 actor 系统，以同一种子的两次运行产生逐事件一致的处理序列。
//
// **Validates: Requirements 10.1, 10.2, 10.6**

///|
/// 单次场景：固定一个消息计划（每个 actor 的消息条数），用 replay_consistent 以同一
/// 种子构造并运行两次，断言两次 trace 逐事件一致。
fn p27_replay(rng : @infra_pbt.Rng) -> Bool {
  let seed = rng.next()
  // 固定拓扑参数（同一迭代内不变），供 build 闭包复用。
  let na = rng.next_range(2, 5)
  let counts : Array[Int] = []
  for _i in 0..<na {
    counts.push(rng.next_range(0, 6))
  }
  // 构造函数：以传入种子驱动调度，派生 na 个 actor 并按计划投递。
  let build = fn(s : UInt64) -> ActorSystem[Int, Int] {
    let sys : ActorSystem[Int, Int] = ActorSystem::with_seed(s)
    let actors : Array[ActorRef[Int]] = []
    for _i in 0..<na {
      actors.push(
        sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) })),
      )
    }
    for i in 0..<na {
      for j in 0..<counts[i] {
        actors[i].send(j + 1)
      }
    }
    sys
  }
  replay_consistent(seed, build)
}

///|
/// Feature: actor, Property 27: 重放确定性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 10.1, 10.2, 10.6**
test "Feature: actor, Property 27: same seed yields an identical processing trace (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p27_replay(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
