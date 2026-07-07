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

///|
/// RateBreaker：样本不足不熔断；达阈值即熔断；窗口滑动后恢复。
test "rate breaker sliding window semantics" {
  let br = RateBreaker::create(10, 5, 500) // 窗口10、最少5样本、错误率≥50%
  // 4 次失败仍不满最少样本 → 不熔断。
  for _ in 0..<4 {
    ignore(br.record(true))
  }
  assert_true(!br.is_open())
  // 第 5 个样本（成功）：5 样本中 4 失败 = 800‰ ≥ 500‰ → 熔断。
  assert_true(br.record(false))
  assert_true(br.failure_rate() == 800)
  // 连续成功把失败挤出窗口 → 恢复。
  for _ in 0..<10 {
    ignore(br.record(false))
  }
  assert_true(!br.is_open())
  assert_true(br.failure_rate() == 0)
}

///|
/// RateBreaker：环形覆盖正确维护失败计数（窗口=3）。
test "rate breaker ring overwrite" {
  let br = RateBreaker::create(3, 3, 500)
  ignore(br.record(true))
  ignore(br.record(true))
  assert_true(!br.is_open()) // 样本不足
  assert_true(br.record(false)) // 2/3 = 666‰ ≥ 500‰ → 熔断
  assert_true(br.record(false) == false) // 覆盖最旧 true → 1/3 = 333‰
  assert_true(br.failure_rate() == 333)
}

///|
/// TimeRateBreaker：错误率超阈值熔断、窗口滑动后过期桶退出统计恢复。
test "time rate breaker opens and recovers with sliding window" {
  // 10 秒窗、最少 4 样本、50% 阈值。
  let b = TimeRateBreaker::create(10, 4, 500)
  // t=0..3s：4 次失败 → 100% ≥ 50% → 熔断。
  assert_true(b.record(0L, true) == false) // 样本不足
  assert_true(b.record(1000L, true) == false)
  assert_true(b.record(2000L, true) == false)
  assert_true(b.record(3000L, true) == true) // 满 4 样本触发
  // t=5s：成功 1 次 → 4/5 = 80% 仍熔断。
  assert_true(b.record(5000L, false) == true)
  // t=15s：旧失败桶（0..3s）已滑出 10s 窗 → 仅剩 5s 的成功 + 新样本。
  assert_true(b.record(15000L, false) == false)
  assert_true(b.is_open(15000L) == false)
}

///|
/// TimeRateBreaker：同秒多样本聚合到同一桶。
test "time rate breaker aggregates within second" {
  let b = TimeRateBreaker::create(5, 10, 500)
  // 同一秒内 10 个样本、6 失败 = 60% ≥ 50%。
  let mut last = false
  for i in 0..<10 {
    last = b.record(500L, i < 6)
  }
  assert_true(last == true)
}

///|
/// RetryBudget：Finagle 语义——保底初始预算、比例存款、余额封顶。
test "retry budget deposit withdraw and cap" {
  // 20%、保底 10/s、ttl 10s → 初始 100 次重试预算、封顶 200。
  let rb = RetryBudget::create()
  assert_true(rb.balance(0L) == 100)
  // 消费 100 次全部成功，第 101 次拒绝。
  let mut ok = 0
  for _ in 0..<101 {
    if rb.try_withdraw(0L) {
      ok = ok + 1
    }
  }
  assert_true(ok == 100)
  // 1000 次正常请求 × 20% = 200 次重试存款，但封顶 200。
  for _ in 0..<2000 {
    rb.deposit(0L)
  }
  assert_true(rb.balance(0L) == 200)
}

///|
/// RetryBudget：时间推进补足保底存款（低流量仍可重试）。
test "retry budget min deposit over time" {
  let rb = RetryBudget::create(
    retry_percent_permille=0, // 无比例存款（纯保底）
    min_deposit_per_sec=2,
    ttl_seconds=5,
  )
  // 初始 = 2×5 = 10。
  assert_true(rb.balance(0L) == 10)
  for _ in 0..<10 {
    assert_true(rb.try_withdraw(0L))
  }
  assert_true(rb.try_withdraw(0L) == false) // 耗尽
  // 3 秒后补足 2×3 = 6 次。
  assert_true(rb.balance(3000L) == 6)
  assert_true(rb.try_withdraw(3000L))
}

///|
/// RetryBudget：重试占比不变式——长期看重试数 ≤ 正常请求数 × 20% + 保底。
test "retry budget bounds retry ratio invariant" {
  let rb = RetryBudget::create(min_deposit_per_sec=0, ttl_seconds=10)
  // 无保底：初始 0 预算。
  assert_true(rb.balance(0L) == 0)
  let mut retries = 0
  for i in 0..<5000 {
    rb.deposit(0L)
    // 每次请求后都尝试重试。
    if rb.try_withdraw(0L) {
      retries = retries + 1
    }
    ignore(i)
  }
  // 重试数 ≤ 5000 × 20% = 1000。
  assert_true(retries <= 1000)
  assert_true(retries >= 900) // 且确实接近预算上限（非饿死）
}
