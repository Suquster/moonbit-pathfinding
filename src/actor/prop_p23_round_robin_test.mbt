// prop_p23_round_robin_test.mbt —— Property 23：RoundRobin 均衡（任务 8.3）。
//
//   Feature: actor, Property 23: RoundRobin 均衡
//   ------------------------------------------------------------------
//   *对任意* 长度为 worker 数整数倍的消息序列，`RoundRobin` 路由后各 worker 收到
//   的消息条数相等（按固定循环命中）。
//
// **Validates: Requirements 8.2, 8.7**

///|
/// 单次场景：w 个 worker，发送 w*k 条消息，断言每个 worker 恰收到 k 条。
fn p23_round_robin_balance(rng : @infra_pbt.Rng) -> Bool {
  reset_runtime()
  let w = rng.next_range(1, 8)
  let k = rng.next_range(0, 6)
  let workers : Array[ActorRef[Int]] = []
  for _i in 0..<w {
    workers.push(spawn(0, fn(s, _m) { s }))
  }
  let router = Router::new(RoundRobin, workers)
  let total = w * k
  for i in 0..<total {
    router.route(i)
  }
  // 各 worker 恰收到 k 条（均衡）。
  for worker in workers {
    if worker.pending() != k {
      return false
    }
  }
  true
}

///|
/// 单次场景（固定循环命中）：连续分发时第 i 条命中 worker i % w。
fn p23_round_robin_cycle(rng : @infra_pbt.Rng) -> Bool {
  reset_runtime()
  let w = rng.next_range(1, 6)
  let workers : Array[ActorRef[Int]] = []
  for _i in 0..<w {
    workers.push(spawn(0, fn(s, _m) { s }))
  }
  let router = Router::new(RoundRobin, workers)
  let n = rng.next_range(0, 20)
  // 逐条分发，分发后第 (i % w) 个 worker 的 pending 应为 i/w 向上取整后的命中数。
  let expected : Array[Int] = []
  for _i in 0..<w {
    expected.push(0)
  }
  for i in 0..<n {
    router.route(i)
    expected[i % w] = expected[i % w] + 1
    for j in 0..<w {
      if workers[j].pending() != expected[j] {
        return false
      }
    }
  }
  true
}

///|
/// Feature: actor, Property 23: RoundRobin 均衡（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 8.2, 8.7**
test "Feature: actor, Property 23: round-robin distributes evenly over a full cycle (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p23_round_robin_balance(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: actor, Property 23: RoundRobin 固定循环命中（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 8.2**
test "Feature: actor, Property 23: round-robin hits workers in a fixed cycle (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p23_round_robin_cycle(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
