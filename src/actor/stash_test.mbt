// stash_test.mbt —— 暂存单元测试（任务 6.3）。
//
// 覆盖：drain_to_front 与原邮箱消息拼接顺序见证。
// _Requirements: 6.2_

///|
/// drain_to_front 见证：暂存 [1,2,3]，邮箱含 [10,20]，回流后出队为 [1,2,3,10,20]。
test "drain_to_front places stashed messages ahead of mailbox messages (witness)" {
  let stash : StashBuffer[Int] = StashBuffer::new()
  let mailbox : Mailbox[Int] = Mailbox::new()
  stash.push(1)
  stash.push(2)
  stash.push(3)
  mailbox.enqueue(10)
  mailbox.enqueue(20)
  assert_eq(stash.length(), 3)
  stash.drain_to_front(mailbox)
  assert_true(stash.is_empty())
  assert_eq(mailbox.dequeue(), Some(1))
  assert_eq(mailbox.dequeue(), Some(2))
  assert_eq(mailbox.dequeue(), Some(3))
  assert_eq(mailbox.dequeue(), Some(10))
  assert_eq(mailbox.dequeue(), Some(20))
  assert_eq(mailbox.dequeue(), None)
}

///|
/// 空暂存缓冲 drain_to_front 不改变邮箱。
test "drain_to_front on empty stash leaves mailbox unchanged" {
  let stash : StashBuffer[Int] = StashBuffer::new()
  let mailbox : Mailbox[Int] = Mailbox::new()
  mailbox.enqueue(7)
  stash.drain_to_front(mailbox)
  assert_eq(mailbox.dequeue(), Some(7))
  assert_eq(mailbox.dequeue(), None)
}

///|
/// clear 清空暂存缓冲（重启 / 停止语义）。
test "clear empties the stash buffer" {
  let stash : StashBuffer[Int] = StashBuffer::new()
  stash.push(1)
  stash.push(2)
  stash.clear()
  assert_true(stash.is_empty())
  assert_eq(stash.length(), 0)
}
