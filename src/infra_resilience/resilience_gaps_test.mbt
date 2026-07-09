// resilience_gaps_test.mbt —— 弹性原语参数钳制与状态机边角收口
// （INFRA 第二十四批）。

///|
test "backoff_delay：base 超过 cap 时钳制为 cap" {
  let policy : BackoffPolicy = { base_ms: 500, cap_ms: 100, max_retries: 3 }
  assert_eq(backoff_delay(policy, 0), 100)
}

///|
test "CircuitBreaker：非法阈值钳制为 1，HalfOpen 放行，Open 中失败不变" {
  let cb = CircuitBreaker::create(0, 100)
  // 阈值钳制为 1：单次失败即跳闸。
  cb.record_failure(0L)
  assert_true(cb.state_of() is Open)
  // Open 中再次失败：保持 Open（无操作分支）。
  cb.record_failure(10L)
  assert_true(cb.state_of() is Open)
  assert_false(cb.allow(50L))
  // 冷却到期 → HalfOpen 放行，且 HalfOpen 状态下继续放行。
  assert_true(cb.allow(100L))
  assert_true(cb.state_of() is HalfOpen)
  assert_true(cb.allow(101L))
}

///|
test "TokenBucket / SlidingWindowLimiter：非法参数钳制" {
  let tb = TokenBucket::create(2, -5)
  // 补充率钳制为 0：耗尽后不再补充。
  assert_true(tb.try_acquire(0L))
  assert_true(tb.try_acquire(0L))
  assert_false(tb.try_acquire(100000L))
  let sw = SlidingWindowLimiter::create(0, 1)
  // 窗口钳制为 1ms：同刻只放行 1 个。
  assert_true(sw.try_acquire(0L))
  assert_false(sw.try_acquire(0L))
  assert_true(sw.try_acquire(5L))
}
