// resilience_test.mbt —— 韧性原语测试：确定性时钟逐毫秒重放 + PBT。

///|
test "backoff delay grows exponentially and caps" {
  let p : @infra_resilience.BackoffPolicy = {
    base_ms: 100,
    cap_ms: 3000,
    max_retries: 5,
  }
  assert_eq(@infra_resilience.backoff_delay(p, 0), 100)
  assert_eq(@infra_resilience.backoff_delay(p, 1), 200)
  assert_eq(@infra_resilience.backoff_delay(p, 2), 400)
  assert_eq(@infra_resilience.backoff_delay(p, 4), 1600)
  // 封顶。
  assert_eq(@infra_resilience.backoff_delay(p, 5), 3000)
  assert_eq(@infra_resilience.backoff_delay(p, 30), 3000)
  // 大 attempt 不溢出。
  assert_eq(@infra_resilience.backoff_delay(p, 62), 3000)
  // full-jitter 边界。
  assert_eq(@infra_resilience.backoff_delay_jittered(p, 2, 0), 0)
  assert_eq(@infra_resilience.backoff_delay_jittered(p, 2, 1000), 400)
  assert_eq(@infra_resilience.backoff_delay_jittered(p, 2, 500), 200)
}

///|
test "retry run counts attempts" {
  let p : @infra_resilience.BackoffPolicy = {
    base_ms: 1,
    cap_ms: 10,
    max_retries: 3,
  }
  // 第 2 次尝试成功（attempt=2）。
  let (ok, attempts) = @infra_resilience.retry_run(p, fn(a) { a == 2 })
  assert_true(ok)
  assert_eq(attempts, 3)
  // 永远失败：max_retries=3 → 共 4 次尝试后放弃。
  let (ok2, attempts2) = @infra_resilience.retry_run(p, fn(_a) { false })
  assert_true(!ok2)
  assert_eq(attempts2, 4)
  // 立即成功。
  let (ok3, attempts3) = @infra_resilience.retry_run(p, fn(a) { a == 0 })
  assert_true(ok3)
  assert_eq(attempts3, 1)
}

///|
test "circuit breaker three-state machine" {
  let cb = @infra_resilience.CircuitBreaker::create(3, 1000)
  // Closed：放行。
  assert_true(cb.allow(0L))
  assert_true(cb.state_of() == @infra_resilience.CircuitState::Closed)
  // 连续 3 次失败跳闸。
  cb.record_failure(10L)
  cb.record_failure(20L)
  assert_true(cb.state_of() == @infra_resilience.CircuitState::Closed)
  cb.record_failure(30L)
  assert_true(cb.state_of() == @infra_resilience.CircuitState::Open)
  // Open 冷却期内拒绝。
  assert_true(!cb.allow(500L))
  assert_true(!cb.allow(1029L))
  // 冷却到期 → HalfOpen 放行试探。
  assert_true(cb.allow(1030L))
  assert_true(cb.state_of() == @infra_resilience.CircuitState::HalfOpen)
  // 试探失败 → 立即回 Open。
  cb.record_failure(1040L)
  assert_true(cb.state_of() == @infra_resilience.CircuitState::Open)
  assert_true(!cb.allow(1500L))
  // 再次冷却 + 试探成功 → Closed。
  assert_true(cb.allow(2040L))
  cb.record_success()
  assert_true(cb.state_of() == @infra_resilience.CircuitState::Closed)
  // 成功清零失败计数：2 次失败 + 成功 + 2 次失败不跳闸。
  cb.record_failure(3000L)
  cb.record_failure(3001L)
  cb.record_success()
  cb.record_failure(3002L)
  cb.record_failure(3003L)
  assert_true(cb.state_of() == @infra_resilience.CircuitState::Closed)
}

///|
test "token bucket burst then steady refill" {
  // 容量 5、每秒 2 个。
  let tb = @infra_resilience.TokenBucket::create(5, 2)
  // 初始满桶：突发取 5 个。
  for _ in 0..<5 {
    assert_true(tb.try_acquire(0L))
  }
  assert_true(!tb.try_acquire(0L))
  // 500ms 后补充 1 个。
  assert_true(tb.try_acquire(500L))
  assert_true(!tb.try_acquire(500L))
  // 再过 250ms 只有半个令牌 → 拒绝。
  assert_true(!tb.try_acquire(750L))
  // 到 1000ms 又满 1 个。
  assert_true(tb.try_acquire(1000L))
  // 长时间闲置封顶容量。
  assert_eq(tb.available(1000000L), 5)
}

///|
test "sliding window limiter precise counting" {
  // 1000ms 窗口最多 3 个。
  let sw = @infra_resilience.SlidingWindowLimiter::create(1000, 3)
  assert_true(sw.try_acquire(0L))
  assert_true(sw.try_acquire(100L))
  assert_true(sw.try_acquire(200L))
  assert_true(!sw.try_acquire(999L))
  assert_eq(sw.in_flight(999L), 3)
  // t=1000 时 t=0 的事件滑出。
  assert_true(sw.try_acquire(1000L))
  assert_true(!sw.try_acquire(1050L))
  // t=1100 时 t=100 滑出。
  assert_true(sw.try_acquire(1100L))
  assert_eq(sw.in_flight(1100L), 3)
}

///|
test "token bucket never exceeds rate (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<50 {
    let cap = 1 + rng.next_below(10)
    let rate = 1 + rng.next_below(100)
    let tb = @infra_resilience.TokenBucket::create(cap, rate)
    let mut now = 0L
    let mut granted = 0
    let horizon_ms = 10000L
    while now < horizon_ms {
      if tb.try_acquire(now) {
        granted = granted + 1
      }
      now = now + (1 + rng.next_below(50)).to_int64()
    }
    // 上界：初始突发 cap + 10 秒 × rate（+1 边界裕量）。
    assert_true(granted <= cap + rate * 10 + 1)
  }
}

///|
test "sliding window never exceeds max per window (pbt)" {
  let rng = @infra_pbt.rng_new(42UL)
  for _ in 0..<50 {
    let window = 100 + rng.next_below(900)
    let max_ev = 1 + rng.next_below(5)
    let sw = @infra_resilience.SlidingWindowLimiter::create(window, max_ev)
    let granted : Array[Int64] = []
    let mut now = 0L
    while now < 5000L {
      if sw.try_acquire(now) {
        granted.push(now)
      }
      now = now + (1 + rng.next_below(30)).to_int64()
    }
    // 验证任意窗口内放行数 ≤ max_ev。
    for i in 0..<granted.length() {
      let mut cnt = 0
      for j in i..<granted.length() {
        if granted[j] - granted[i] < window.to_int64() {
          cnt = cnt + 1
        }
      }
      assert_true(cnt <= max_ev)
    }
  }
}
