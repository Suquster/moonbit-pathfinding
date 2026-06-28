// bounded_mailbox_test.mbt —— 有界邮箱单元测试（任务 9.4）。
//
// 覆盖：满时 DropNewest / DropOldest / Reject 三策略见证。
// _Requirements: 9.3, 9.4, 9.5_

///|
/// DropNewest 见证：容量 2，投递 [1,2,3] → 队列 [1,2]，新消息 3 被丢弃。
test "DropNewest drops the newest message when full (witness)" {
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(2, DropNewest)
  @test.assert_eq(mb.offer(1), Enqueued)
  @test.assert_eq(mb.offer(2), Enqueued)
  @test.assert_eq(mb.offer(3), Dropped)
  @test.assert_eq(mb.length(), 2)
  @test.assert_eq(mb.dequeue(), Some(1))
  @test.assert_eq(mb.dequeue(), Some(2))
  @test.assert_eq(mb.dequeue(), None)
  @test.assert_eq(mb.counts(), (2, 1, 0))
}

///|
/// DropOldest 见证：容量 2，投递 [1,2,3] → 移除最旧 1，队列 [2,3]。
test "DropOldest evicts the oldest message when full (witness)" {
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(2, DropOldest)
  @test.assert_eq(mb.offer(1), Enqueued)
  @test.assert_eq(mb.offer(2), Enqueued)
  @test.assert_eq(mb.offer(3), Dropped)
  @test.assert_eq(mb.length(), 2)
  @test.assert_eq(mb.dequeue(), Some(2))
  @test.assert_eq(mb.dequeue(), Some(3))
  @test.assert_eq(mb.counts(), (2, 1, 0))
}

///|
/// Reject 见证：容量 2，投递 [1,2,3] → 3 被拒绝，队列保持 [1,2]。
test "Reject refuses the new message when full (witness)" {
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(2, Reject)
  @test.assert_eq(mb.offer(1), Enqueued)
  @test.assert_eq(mb.offer(2), Enqueued)
  @test.assert_eq(mb.offer(3), Rejected)
  @test.assert_eq(mb.length(), 2)
  @test.assert_eq(mb.dequeue(), Some(1))
  @test.assert_eq(mb.dequeue(), Some(2))
  @test.assert_eq(mb.counts(), (2, 0, 1))
}

///|
/// 容量为 0：任何投递都不入队（按策略丢弃或拒绝）。
test "zero-capacity mailbox never enqueues" {
  let mb : BoundedMailbox[Int] = BoundedMailbox::new(0, DropOldest)
  @test.assert_eq(mb.offer(1), Dropped)
  @test.assert_eq(mb.length(), 0)
}
