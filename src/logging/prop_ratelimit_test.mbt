// prop_ratelimit_test.mbt —— 限流配额上界属性测试（任务 5.7）。
//
//   Feature: logging, Property 8: 限流配额上界（rate-limit quota bound）
//   --------------------------------------------------------------------
//   *对任意* 窗口大小、配额 limit 与（key, 逻辑时间戳）事件序列，限流器在任一
//   逻辑时间窗内对同一 key 放行的事件条数不超过 limit，超额事件被丢弃。
//
// 验证手法（非循环）：把同一 key 的若干次申请全部落在单一窗口内（时间戳取自
// `[0, window)`，相邻间隔 < window ⇒ 必同窗），则放行数恰为 `min(m, limit)`
// 且不超过 `limit`。复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 单次场景：window/limit/m 随机，同 key 在单一窗口内申请 m 次，断言放行数
/// == min(m, max(limit,0)) 且 <= limit。
fn rl_quota(rng : @infra_pbt.Rng) -> Bool {
  let window = rng.next_range(1, 50).to_int64()
  let limit = rng.next_range(0, 8)
  let m = rng.next_range(0, 20)
  let limiter = RateLimiter::new(window, limit)
  let mut allowed = 0
  for _i in 0..<m {
    // 时间戳落在 [0, window) ⇒ 全部归属同一窗口。
    let ts = rng.next_range(0, (window - 1L).to_int()).to_int64()
    if limiter.allow("k", ts) {
      allowed = allowed + 1
    }
  }
  let cap = if limit < 0 { 0 } else { limit }
  let expected = if m < cap { m } else { cap }
  allowed == expected && allowed <= cap
}

///|
/// Feature: logging, Property 8: 限流配额上界（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.5**
test "Feature: logging, Property 8: rate-limit quota bound (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { rl_quota(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// 具体见证：window=10 limit=2，同窗内放行 2 条后丢弃；窗口到期后重置再放行。
test "rate limiter quota and window reset (witness)" {
  let limiter = RateLimiter::new(10L, 2)
  assert_true(limiter.allow("a", 0L)) // 1
  assert_true(limiter.allow("a", 5L)) // 2
  assert_false(limiter.allow("a", 9L)) // 超额丢弃
  // ts=10 超出窗口 [0,10) ⇒ 新窗口，重置计数。
  assert_true(limiter.allow("a", 10L)) // 新窗 1
  assert_true(limiter.allow("a", 11L)) // 新窗 2
  assert_false(limiter.allow("a", 12L)) // 超额
  // 不同 key 独立计数。
  assert_true(limiter.allow("b", 11L))
}
