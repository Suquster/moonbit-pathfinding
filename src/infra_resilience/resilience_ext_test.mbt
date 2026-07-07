// resilience_ext_test.mbt —— Bulkhead / Hedging / AIMD 测试。

///|
/// Bulkhead：准入 → 排队 → 拒绝三段语义与释放顶替。
test "bulkhead admission queueing and rejection" {
  let b = Bulkhead::create(2, 1)
  assert_true(b.try_acquire() == Admitted)
  assert_true(b.try_acquire() == Admitted)
  assert_true(b.try_acquire() == Enqueued) // 舱满 → 排队
  assert_true(b.try_acquire() == Rejected) // 队也满 → 快速失败
  assert_true(b.in_flight_count() == 2 && b.queued_count() == 1)
  assert_true(b.rejected_count() == 1)
  // 释放后排队者顶替。
  assert_true(b.release() == true)
  assert_true(b.in_flight_count() == 2 && b.queued_count() == 0)
  // 再释放无排队者。
  assert_true(b.release() == false)
  assert_true(b.in_flight_count() == 1)
  // 空舱再释放不下穿零。
  assert_true(b.release() == false)
  assert_true(b.release() == false)
  assert_true(b.in_flight_count() == 0)
}

///|
/// Hedging：发射时刻表与胜者判定（The Tail at Scale 语义）。
test "hedge schedule and outcome" {
  let policy : HedgePolicy = { hedge_after_ms: 100, max_hedges: 2 }
  assert_true(hedge_schedule(policy) == [0, 100, 200])
  // 首请求 350ms（慢尾），副本 1 于 100ms 发射、耗时 80ms → 180ms 完成胜出。
  let (winner, finish, launched) = hedge_outcome(policy, [350, 80, 999])
  assert_true(winner == 1 && finish == 180)
  assert_true(launched == 2) // 副本 2 发射前（200ms）胜者已完成 → 不发射
  // 快路径：首请求 50ms 完成，任何副本都不发射。
  let (w2, f2, l2) = hedge_outcome(policy, [50, 1, 1])
  assert_true(w2 == 0 && f2 == 50 && l2 == 1)
  // 全部慢：三副本都发射，最后一个胜出。
  let (w3, f3, l3) = hedge_outcome(policy, [900, 800, 100])
  assert_true(w3 == 2 && f3 == 300 && l3 == 3)
}

///|
/// 对冲不变式：端到端完成时刻 ≤ 首请求单独完成时刻（对冲只会更快）。
test "prop hedging never slower than solo request" {
  let policy : HedgePolicy = { hedge_after_ms: 50, max_hedges: 3 }
  let mut seed = 0xB7E15162U
  for _ in 0..<200 {
    let durations : Array[Int] = []
    for _ in 0..<4 {
      seed = seed * 1664525U + 1013904223U
      durations.push(1 + ((seed >> 8) % 500U).reinterpret_as_int())
    }
    let (_, finish, launched) = hedge_outcome(policy, durations)
    assert_true(finish <= durations[0])
    assert_true(launched >= 1 && launched <= 4)
  }
}

///|
/// AIMD：加性增封顶、乘性减保底、锯齿收敛轨迹。
test "aimd additive increase multiplicative decrease" {
  let l = AimdLimiter::create(10, 1, 16)
  for _ in 0..<10 {
    l.on_success()
  }
  assert_true(l.current_limit() == 16) // 封顶
  l.on_overload()
  assert_true(l.current_limit() == 8) // 减半
  l.on_overload()
  l.on_overload()
  l.on_overload()
  assert_true(l.current_limit() == 1) // 保底
  l.on_success()
  assert_true(l.current_limit() == 2)
  // 自定义参数：加 3、失败保留 250‰。
  let l2 = AimdLimiter::create(100, 10, 1000, additive=3, decrease_permille=250)
  l2.on_success()
  assert_true(l2.current_limit() == 103)
  l2.on_overload()
  assert_true(l2.current_limit() == 25)
}
