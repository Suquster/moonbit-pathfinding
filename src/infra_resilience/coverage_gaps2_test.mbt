// 黑盒测试：退避钳制 / 熔断状态 Show / 对冲与速率熔断边界。

///|
test "backoff：负 attempt 与抖动千分比钳制" {
  let p : BackoffPolicy = { base_ms: 100, cap_ms: 800, max_retries: 3 }
  assert_eq(backoff_delay(p, -1), 100)
  assert_eq(backoff_delay_jittered(p, 1, -5), 0)
  assert_eq(backoff_delay_jittered(p, 1, 2000), 200)
}

///|
test "circuit：CircuitState Show 三态渲染" {
  let c = CircuitState::Closed
  let o = CircuitState::Open
  let h = CircuitState::HalfOpen
  assert_eq("\{c}", "Closed")
  assert_eq("\{o}", "Open")
  assert_eq("\{h}", "HalfOpen")
}

///|
test "hedge：耗时数组短于计划时按耗时长度截断" {
  let policy : HedgePolicy = { hedge_after_ms: 10, max_hedges: 2 }
  let (idx, finish, launched) = hedge_outcome(policy, [5])
  assert_eq(idx, 0)
  assert_eq(finish, 5)
  assert_eq(launched, 1)
}

///|
test "rate_breaker：零样本失败率为 0" {
  let rb = RateBreaker::create(500, 10, 1000)
  assert_eq(rb.failure_rate(), 0)
}
