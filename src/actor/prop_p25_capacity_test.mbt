// prop_p25_capacity_test.mbt —— Property 25：有界邮箱容量上界与未满 FIFO（任务 9.2）。
//
//   Feature: actor, Property 25: 有界邮箱容量上界与未满 FIFO
//   ------------------------------------------------------------------
//   *对任意* 容量、背压策略与投递序列，有界邮箱在任意时刻排队消息条数不超过容量；
//   未满时与无界 FIFO 一致。
//
// **Validates: Requirements 9.2, 9.7**

///|
/// 随机背压策略。
fn p25_gen_policy(rng : @infra_pbt.Rng) -> BackpressurePolicy {
  match rng.next_range(0, 2) {
    0 => DropNewest
    1 => DropOldest
    _ => Reject
  }
}

///|
/// 单次场景：随机容量与策略，逐条投递并在每步断言 length <= capacity；
/// 另以未满前缀验证 FIFO 出队顺序与投递顺序一致。
fn p25_capacity_bound(rng : @infra_pbt.Rng) -> Bool {
  let capacity = rng.next_range(0, 8)
  let policy = p25_gen_policy(rng)
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(capacity, policy)
  let n = rng.next_range(0, 30)
  for i in 0..<n {
    let _ = mb.offer(i)
    // 容量上界：任意时刻 length <= capacity。
    if mb.length() > capacity {
      return false
    }
  }
  // 未满 FIFO 一致性：在一个全新邮箱上投递 <= capacity 条，出队应逐位等于投递顺序。
  let m = if capacity < 5 { capacity } else { 5 }
  let mb2 : BoundedMailbox[Int] = BoundedMailbox::new(capacity, policy)
  let sent : Array[Int] = []
  for i in 0..<m {
    let r = mb2.offer(i * 10)
    if r != Enqueued {
      return false
    }
    sent.push(i * 10)
  }
  for i in 0..<m {
    match mb2.dequeue() {
      Some(v) => if v != sent[i] { return false }
      None => return false
    }
  }
  true
}

///|
/// Feature: actor, Property 25: 有界邮箱容量上界与未满 FIFO（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 9.2, 9.7**
test "Feature: actor, Property 25: bounded mailbox never exceeds capacity and is FIFO while unfull (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p25_capacity_bound(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
