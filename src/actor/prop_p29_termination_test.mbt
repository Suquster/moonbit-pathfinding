// prop_p29_termination_test.mbt —— Property 29：调度终止性（任务 11.5）。
//
//   Feature: actor, Property 29: 调度终止性
//   ------------------------------------------------------------------
//   *对任意* 种子与 actor 系统，`run_until_idle` 在有限步内停机，得有限长度 trace。
//
// **Validates: Requirements 10.5**

///|
/// 单次场景：多 actor、随机消息，run_until_idle 后 trace 长度有限且等于投递总条数
/// （每条消息恰被处理一次），且系统空闲（再 step 无进展）。
fn p29_termination(rng : @infra_pbt.Rng) -> Bool {
  let seed = rng.next()
  let sys : ActorSystem[Int, Int] = ActorSystem::with_seed(seed)
  let na = rng.next_range(1, 5)
  let actors : Array[ActorRef[Int]] = []
  for _i in 0..<na {
    actors.push(sys.spawn(0, Behavior::new(fn(_ctx, s, m) { Updated(s + m) })))
  }
  let mut total = 0
  for a in actors {
    let cnt = rng.next_range(0, 8)
    for _j in 0..<cnt {
      a.send(rng.next_range(0, 10))
      total = total + 1
    }
  }
  sys.run_until_idle()
  // trace 长度 == 投递总条数（每条恰处理一次，有限）。
  if sys.trace_of().length() != total {
    return false
  }
  // 空闲：再 step 无进展。
  not(sys.step())
}

///|
/// Feature: actor, Property 29: 调度终止性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 10.5**
test "Feature: actor, Property 29: run_until_idle halts with a finite trace (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p29_termination(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
