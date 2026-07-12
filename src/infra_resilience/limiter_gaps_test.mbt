// 黑盒测试：覆盖率审计收口（INFRA 第七十二批）——
// 滑窗限流器 max_events 下钳与大规模驱逐后的压实路径。

///|
test "SlidingWindowLimiter：max_events < 1 钳制到 1" {
  let l = @infra_resilience.SlidingWindowLimiter::create(1000, 0)
  assert_true(l.try_acquire(0L))
  assert_false(l.try_acquire(1L))
}

///|
test "SlidingWindowLimiter：驱逐超 1024 事件后触发压实" {
  let l = @infra_resilience.SlidingWindowLimiter::create(10, 5000)
  for i in 0..<2000 {
    assert_true(l.try_acquire(i.to_int64()))
  }
  // 时间推进使全部 2000 条过期 → head 越过 1024 → 压实。
  assert_eq(l.in_flight(100000L), 0)
  assert_true(l.try_acquire(100001L))
}
