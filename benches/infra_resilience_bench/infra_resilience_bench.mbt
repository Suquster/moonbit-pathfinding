// infra_resilience_bench.mbt —— 韧性方向基准：熔断器 / 限流器 / AIMD /
// 退避计算在确定性调用序列上的吞吐对比。

///|
test "smoke: breaker opens on failures, bucket refills, aimd converges" {
  let cb = @res.CircuitBreaker::create(3, 10)
  for _ in 0..<3 {
    cb.record_failure(0L)
  }
  assert_true(cb.allow(1L) == false)
  let tb = @res.TokenBucket::create(10, 5)
  for _ in 0..<10 {
    assert_true(tb.try_acquire(0L))
  }
  assert_true(tb.try_acquire(0L) == false)
  assert_true(tb.try_acquire(2000L))
  let aimd = @res.AimdLimiter::create(10, 1, 100)
  for _ in 0..<5 {
    aimd.on_success()
  }
  assert_eq(aimd.current_limit(), 15)
  aimd.on_overload()
  assert_eq(aimd.current_limit(), 7)
}

///|
test "bench: breaker / limiter / aimd / backoff throughput" (b : @bench.T) {
  b.bench(name="circuit_breaker_4096_ops", fn() {
    let cb = @res.CircuitBreaker::create(5, 10)
    let mut allowed = 0
    for i in 0..<4096 {
      let now = i.to_int64()
      if cb.allow(now) {
        allowed = allowed + 1
        if i % 7 == 0 {
          cb.record_failure(now)
        } else {
          cb.record_success()
        }
      }
    }
    b.keep(allowed)
  })
  b.bench(name="token_bucket_4096_ops", fn() {
    let tb = @res.TokenBucket::create(100, 50)
    let mut ok = 0
    for i in 0..<4096 {
      if tb.try_acquire(i.to_int64() * 3L) {
        ok = ok + 1
      }
    }
    b.keep(ok)
  })
  b.bench(name="sliding_window_4096_ops", fn() {
    let sw = @res.SlidingWindowLimiter::create(64, 1000)
    let mut ok = 0
    for i in 0..<4096 {
      if sw.try_acquire(i.to_int64() * 17L) {
        ok = ok + 1
      }
    }
    b.keep(ok)
  })
  b.bench(name="aimd_4096_ops", fn() {
    let aimd = @res.AimdLimiter::create(10, 1, 100)
    for i in 0..<4096 {
      if i % 50 == 49 {
        aimd.on_overload()
      } else {
        aimd.on_success()
      }
    }
    b.keep(aimd.current_limit())
  })
  let policy : @res.BackoffPolicy = {
    base_ms: 100,
    cap_ms: 30_000,
    max_retries: 8,
  }
  b.bench(name="backoff_jittered_4096", fn() {
    let mut acc = 0
    for i in 0..<4096 {
      acc = acc + @res.backoff_delay_jittered(policy, i % 8, i)
    }
    b.keep(acc)
  })
}
