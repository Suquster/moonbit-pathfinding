// resilience_diff_proof_test.mbt —— 韧性/diff 家族证明谓词的真实实现接地测试。
//
// 以 @infra_resilience / @infra_diff 的真实包实现驱动
// resilience_diff_proof.mbt 中的谓词（跨包驱动只发生在测试期）：
//   * 退避延迟有界 + 未达 cap 前单调（`all_within` / `non_decreasing`）；
//   * AIMD 限额恒在 [min, max]（随机成功/过载序列 PBT）；
//   * 舱壁并发/队列计数不越硬上界（随机 acquire/release 序列 PBT）；
//   * 熔断器观测状态序列迁移合法（`transitions_legal` + 三态迁移关系）；
//   * diff/patch 正反向往返恒等（三引擎 × 随机行数组 PBT）。

///|
/// CircuitState → Int 编码（Closed=0、Open=1、HalfOpen=2），与
/// `breaker_transition_allowed` 的编码约定一致。
fn rd_state_code(s : @infra_resilience.CircuitState) -> Int {
  match s {
    Closed => 0
    Open => 1
    HalfOpen => 2
  }
}

// --- 退避：有界 + 单调 ---

///|
test "backoff delays are capped and non-decreasing before cap" {
  let policy : @infra_resilience.BackoffPolicy = {
    base_ms: 10,
    cap_ms: 2000,
    max_retries: 12,
  }
  let delays : Array[Int] = []
  for attempt in 0..<12 {
    delays.push(@infra_resilience.backoff_delay(policy, attempt))
  }
  assert_true(all_within(delays, 0, 2000))
  assert_true(non_decreasing(delays))
}

///|
test "all_within rejects out-of-budget element" {
  assert_false(all_within([10, 3000], 0, 2000))
}

///|
test "non_decreasing rejects a decreasing pair" {
  assert_false(non_decreasing([10, 20, 15]))
}

// --- AIMD 限额有界（随机序列 PBT） ---

///|
/// 随机成功/过载事件序列（true = success，false = overload）。
fn rd_events_gen() -> @infra_pbt.Gen[Array[Bool]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 64)
    let out : Array[Bool] = []
    for _i in 0..<n {
      out.push(rng.next_range(0, 3) > 0)
    }
    out
  })
}

///|
fn rd_prop_aimd_bounded(events : Array[Bool]) -> Bool {
  let limiter = @infra_resilience.AimdLimiter::create(1, 100, 4)
  let observed : Array[Int] = [limiter.current_limit()]
  for e in events {
    if e {
      limiter.on_success()
    } else {
      limiter.on_overload()
    }
    observed.push(limiter.current_limit())
  }
  all_within(observed, 1, 100)
}

///|
test "AIMD limit stays within [min, max] under random event sequences" {
  let ok = @infra_pbt.holds_for_all(
    rd_events_gen(),
    rd_prop_aimd_bounded,
    iters=128,
  )
  assert_true(ok)
}

// --- 舱壁计数硬上界（随机 acquire/release 序列 PBT） ---

///|
fn rd_prop_bulkhead_bounded(events : Array[Bool]) -> Bool {
  let bh = @infra_resilience.Bulkhead::create(4, 3)
  let inflight : Array[Int] = []
  let queued : Array[Int] = []
  for e in events {
    if e {
      ignore(bh.try_acquire())
    } else {
      ignore(bh.release())
    }
    inflight.push(bh.in_flight_count())
    queued.push(bh.queued_count())
  }
  all_within(inflight, 0, 4) && all_within(queued, 0, 3)
}

///|
test "bulkhead counters never exceed hard budgets" {
  let ok = @infra_pbt.holds_for_all(
    rd_events_gen(),
    rd_prop_bulkhead_bounded,
    iters=128,
  )
  assert_true(ok)
}

// --- 熔断器状态机迁移合法 ---

///|
test "circuit breaker observed transitions are legal" {
  let cb = @infra_resilience.CircuitBreaker::create(2, 100)
  let states : Array[Int] = [rd_state_code(cb.state_of())]
  let mut now : Int64 = 0
  // 两次失败跳闸 Closed→Open。
  cb.record_failure(now)
  states.push(rd_state_code(cb.state_of()))
  cb.record_failure(now)
  states.push(rd_state_code(cb.state_of()))
  // 冷却期满放行探针 Open→HalfOpen。
  now = 200
  ignore(cb.allow(now))
  states.push(rd_state_code(cb.state_of()))
  // 探针失败再跳闸 HalfOpen→Open。
  cb.record_failure(now)
  states.push(rd_state_code(cb.state_of()))
  // 再次冷却 + 探针成功恢复 HalfOpen→Closed。
  now = 400
  ignore(cb.allow(now))
  states.push(rd_state_code(cb.state_of()))
  cb.record_success()
  states.push(rd_state_code(cb.state_of()))
  assert_true(transitions_legal(states, breaker_transition_allowed))
}

///|
test "transitions_legal rejects an illegal Open->Closed jump" {
  assert_false(transitions_legal([1, 0], breaker_transition_allowed))
}

// --- diff/patch 往返恒等（三引擎 PBT） ---

///|
/// 随机行数组对生成器：字母表 {a, b, c}、长度 ∈ [0, 8]，保证高碰撞率以
/// 覆盖 Keep/Delete/Insert 混合场景。
fn rd_lines_pair_gen() -> @infra_pbt.Gen[(Array[String], Array[String])] {
  @infra_pbt.Gen::new(fn(rng) {
    let alphabet = ["a", "b", "c"]
    let gen_lines = fn() -> Array[String] {
      let n = rng.next_range(0, 8)
      let out : Array[String] = []
      for _i in 0..<n {
        out.push(alphabet[rng.next_range(0, 2)])
      }
      out
    }
    (gen_lines(), gen_lines())
  })
}

///|
fn rd_prop_patch_round_trips(pair : (Array[String], Array[String])) -> Bool {
  let (before, after) = pair
  // 三引擎正向：apply(before, diff(before, after)) == after。
  let fwd_lines = fn(a : Array[String], b : Array[String]) -> Array[String]? {
    @infra_diff.patch_apply(a, @infra_diff.diff_lines(a, b))
  }
  let fwd_hist = fn(a : Array[String], b : Array[String]) -> Array[String]? {
    @infra_diff.patch_apply(a, @infra_diff.diff_histogram(a, b))
  }
  let fwd_pat = fn(a : Array[String], b : Array[String]) -> Array[String]? {
    @infra_diff.patch_apply(a, @infra_diff.diff_patience(a, b))
  }
  // 反向：revert(after, diff(before, after)) == before。
  let rev = fn(a : Array[String], b : Array[String]) -> Array[String]? {
    @infra_diff.patch_revert(a, @infra_diff.diff_lines(b, a))
  }
  patch_round_trip_eq(before, after, fwd_lines) &&
  patch_round_trip_eq(before, after, fwd_hist) &&
  patch_round_trip_eq(before, after, fwd_pat) &&
  patch_round_trip_eq(after, before, rev)
}

///|
test "diff/patch round-trips hold across all three engines" {
  let ok = @infra_pbt.holds_for_all(
    rd_lines_pair_gen(),
    rd_prop_patch_round_trips,
    iters=128,
  )
  assert_true(ok)
}
