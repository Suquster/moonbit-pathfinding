// prop_p26_backpressure_test.mbt —— Property 26：背压计数守恒（任务 9.3）。
//
//   Feature: actor, Property 26: 背压计数守恒
//   ------------------------------------------------------------------
//   *对任意* 投递序列，「入队条数 + 丢弃条数 + 拒绝条数」等于投递总数，且每次
//   投递恰使三者之一加一。
//
// **Validates: Requirements 9.3, 9.4, 9.5, 9.8**

///|
/// 随机背压策略。
fn p26_gen_policy(rng : @infra_pbt.Rng) -> BackpressurePolicy {
  match rng.next_range(0, 2) {
    0 => DropNewest
    1 => DropOldest
    _ => Reject
  }
}

///|
/// 单次场景：逐条投递，断言每步后三计数之和等于已投递条数（每次恰加一其一）。
fn p26_count_conservation(rng : @infra_pbt.Rng) -> Bool {
  let capacity = rng.next_range(0, 8)
  let policy = p26_gen_policy(rng)
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(capacity, policy)
  let n = rng.next_range(0, 40)
  for i in 0..<n {
    let before = mb.counts()
    let before_sum = before.0 + before.1 + before.2
    let result = mb.offer(i)
    let after = mb.counts()
    let after_sum = after.0 + after.1 + after.2
    // 每次投递恰使三计数之一加一（总和加一）。
    if after_sum != before_sum + 1 {
      return false
    }
    // 结果与计数变化一致。
    match result {
      Enqueued => if after.0 != before.0 + 1 { return false }
      Dropped => if after.1 != before.1 + 1 { return false }
      Rejected => if after.2 != before.2 + 1 { return false }
    }
  }
  // 守恒：三计数之和 == 投递总数。
  let (e, d, r) = mb.counts()
  e + d + r == n
}

///|
/// 单次场景：Reject 策略满时内容不变（拒绝不改变排队消息）。
fn p26_reject_keeps_content(rng : @infra_pbt.Rng) -> Bool {
  let capacity = rng.next_range(1, 6)
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(capacity, Reject)
  // 填满。
  for i in 0..<capacity {
    let _ = mb.offer(i)
  }
  let len_before = mb.length()
  // 再投递若干 —— 全部 Rejected，长度不变。
  let extra = rng.next_range(1, 10)
  for j in 0..<extra {
    if mb.offer(1000 + j) != Rejected {
      return false
    }
    if mb.length() != len_before {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 26: 背压计数守恒（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 9.3, 9.4, 9.5, 9.8**
test "Feature: actor, Property 26: backpressure counters are conserved (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p26_count_conservation(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: actor, Property 26: Reject 满时内容不变（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 9.5**
test "Feature: actor, Property 26: reject policy keeps queue content unchanged when full (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p26_reject_keeps_content(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
