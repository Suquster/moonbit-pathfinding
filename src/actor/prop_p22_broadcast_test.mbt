// prop_p22_broadcast_test.mbt —— Property 22：Broadcast 全达（任务 8.2）。
//
//   Feature: actor, Property 22: Broadcast 全达
//   ------------------------------------------------------------------
//   *对任意* 消息序列与 worker 数量，`Broadcast` 路由后每个 worker 收到的消息
//   条数等于输入消息条数。
//
// **Validates: Requirements 8.3, 8.6**

///|
/// 单次场景：构造 w 个 worker 的 Broadcast 路由器，分发 n 条消息，
/// 断言每个 worker 邮箱恰有 n 条。
fn p22_broadcast_all(rng : @infra_pbt.Rng) -> Bool {
  reset_runtime()
  let w = rng.next_range(1, 8)
  let workers : Array[ActorRef[Int]] = []
  for _i in 0..<w {
    workers.push(spawn(0, fn(s, _m) { s }))
  }
  let router = Router::new(Broadcast, workers)
  let n = rng.next_range(0, 15)
  for i in 0..<n {
    router.route(i)
  }
  for worker in workers {
    if worker.pending() != n {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 22: Broadcast 全达（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 8.3, 8.6**
test "Feature: actor, Property 22: broadcast delivers to every worker (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p22_broadcast_all(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
