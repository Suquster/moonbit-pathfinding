// examples/resilience_gateway — runnable demonstration of the
// `src/infra_resilience` direction as an API-gateway workflow: retry a
// flaky upstream with capped exponential backoff, trip and recover a
// circuit breaker, rate-limit clients with token bucket and sliding
// window, isolate tenants with a bulkhead, adapt concurrency with AIMD,
// and cut tail latency with hedged requests.
//
// Run with:
//   moon run examples/resilience_gateway

///|
fn main {
  println("=== 1. capped exponential backoff + retry ===")
  let policy : @res.BackoffPolicy = {
    base_ms: 100,
    cap_ms: 2000,
    max_retries: 6,
  }
  let sched = []
  for attempt in 0..<6 {
    sched.push(@res.backoff_delay(policy, attempt).to_string())
  }
  println("delays (ms) : \{sched.join(", ")}")
  println(
    "jittered #3 : \{@res.backoff_delay_jittered(policy, 3, 42)} ms (deterministic seed)",
  )
  let (ok, attempts) = @res.retry_run(policy, fn(attempt) { attempt >= 2 })
  println("flaky upstream succeeds on 3rd try: ok=\{ok}, attempts=\{attempts}")
  println("")
  println("=== 2. circuit breaker state machine ===")
  let cb = @res.CircuitBreaker::create(3, 1000)
  println("initial     : \{cb.state_of()}")
  cb.record_failure(0)
  cb.record_failure(10)
  cb.record_failure(20)
  println("3 failures  : \{cb.state_of()} (allow now: \{cb.allow(30)})")
  println("after cooldown: allow=\{cb.allow(1500)} -> \{cb.state_of()}")
  cb.record_success()
  println("probe success: \{cb.state_of()}")
  println("")
  println("=== 3. rate limiting: token bucket vs sliding window ===")
  let bucket = @res.TokenBucket::create(3, 1)
  let bucket_hits = []
  for i in 0..<5 {
    bucket_hits.push(bucket.try_acquire(i.to_int64() * 10).to_string())
  }
  println("token bucket (cap 3): \{bucket_hits.join(", ")}")
  let win = @res.SlidingWindowLimiter::create(1000, 3)
  let win_hits = []
  for i in 0..<5 {
    win_hits.push(win.try_acquire(i.to_int64() * 100).to_string())
  }
  println("sliding window (3/s) : \{win_hits.join(", ")}")
  println("after window slides  : \{win.try_acquire(1500)}")
  println("")
  println("=== 4. bulkhead isolation per tenant ===")
  let bh = @res.Bulkhead::create(2, 1)
  let admissions = []
  for _i in 0..<4 {
    let verdict = match bh.try_acquire() {
      Admitted => "admitted"
      Enqueued => "enqueued"
      Rejected => "rejected"
    }
    admissions.push(verdict)
  }
  println("4 concurrent calls (2 slots + 1 queue): \{admissions.join(", ")}")
  let _ = bh.release()
  println(
    "after release: in-flight=\{bh.in_flight_count()}, queued=\{bh.queued_count()}, rejected=\{bh.rejected_count()}",
  )
  println("")
  println("=== 5. AIMD adaptive concurrency ===")
  let aimd = @res.AimdLimiter::create(10, 1, 100)
  for _i in 0..<5 {
    aimd.on_success()
  }
  println("after 5 successes : limit = \{aimd.current_limit()}")
  aimd.on_overload()
  println(
    "after overload    : limit = \{aimd.current_limit()} (multiplicative decrease)",
  )
  println("")
  println("=== 6. hedged requests cut tail latency ===")
  let hedge : @res.HedgePolicy = { hedge_after_ms: 50, max_hedges: 2 }
  println(
    "hedge fire times : \{@res.hedge_schedule(hedge).map(fn(t) { t.to_string() }).join(", ")} ms",
  )
  let latencies = [300, 80, 120]
  let (winner, latency, wasted) = @res.hedge_outcome(hedge, latencies)
  println(
    "upstream latencies \{latencies.map(fn(t) { t.to_string() }).join("/")}ms -> winner #\{winner} at \{latency}ms (wasted \{wasted})",
  )
}
