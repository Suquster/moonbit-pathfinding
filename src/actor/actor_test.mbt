// actor_test.mbt —— Actor_Framework 骨架（任务 16.1）的最小单元测试。
//
// 覆盖 16.1 的核心契约（确定性夹具，非属性测试——FIFO / 串行 / 隔离的
// 属性 Property 22/23 由任务 16.3 / 16.4 承载）：
//   1. spawn 返回引用句柄，含唯一 id 与空邮箱（Requirement 10.1）；
//   2. spawn 分配单调递增、互异的 actor id；
//   3. send 将消息按投递顺序追加到邮箱队列（FIFO 入队，Requirement 10.2）；
//   4. stop 关闭邮箱后，后续 send 被丢弃；
//   5. 邮箱原语：peek 不移除队首、dequeue 按 FIFO 取出、空邮箱语义。
//
// 触达全局运行时 id 分配源的用例先 `reset_runtime()` 以隔离用例间状态。

// ─────────────────────── spawn：引用句柄与 id（10.1） ──────────────────────

///|
/// spawn 返回引用句柄：分配 id、邮箱初始为空。
test "spawn returns a reference handle with a fresh id and empty mailbox" {
  reset_runtime()
  let a = spawn(0, fn(s, m) { s + m })
  assert_eq(a.id.value, 1)
  assert_true(a.mailbox.is_empty())
  assert_eq(a.pending(), 0)
}

///|
/// spawn 分配单调递增且互异的 actor id。
test "spawn allocates monotonically increasing unique ids" {
  reset_runtime()
  let a = spawn(0, fn(s, m) { s + m })
  let b = spawn(0, fn(s, m) { s + m })
  assert_eq(a.id.value, 1)
  assert_eq(b.id.value, 2)
  assert_false(a.id == b.id)
}

// ─────────────────────── send：邮箱 FIFO 入队（10.2） ──────────────────────

///|
/// send 将消息按投递顺序追加到邮箱队列，dequeue 以相同 FIFO 顺序取出。
test "send appends messages to the mailbox queue in fifo order" {
  reset_runtime()
  let a : ActorRef[Int] = spawn(0, fn(s, m) { s + m })
  a.send(10)
  a.send(20)
  a.send(30)
  assert_eq(a.pending(), 3)
  assert_eq(a.mailbox.dequeue(), Some(10))
  assert_eq(a.mailbox.dequeue(), Some(20))
  assert_eq(a.mailbox.dequeue(), Some(30))
  assert_eq(a.mailbox.dequeue(), None)
}

// ─────────────────────────── stop：关闭邮箱 ───────────────────────────────

///|
/// stop 关闭邮箱后，后续 send 被丢弃，已入队消息不受影响。
test "stop closes the mailbox and further sends are dropped" {
  reset_runtime()
  let a : ActorRef[Int] = spawn(0, fn(s, m) { s + m })
  a.send(1)
  a.stop()
  assert_true(a.mailbox.is_closed())
  a.send(2)
  assert_eq(a.pending(), 1)
}

// ───────────────────────────── 邮箱原语 ──────────────────────────────────

///|
/// 空邮箱：is_empty 为真、length 为 0、dequeue / peek 返回 None。
test "fresh mailbox is empty" {
  let mb : Mailbox[String] = Mailbox::new()
  assert_true(mb.is_empty())
  assert_eq(mb.length(), 0)
  assert_eq(mb.dequeue(), None)
  assert_eq(mb.peek(), None)
}

///|
/// peek 查看队首但不移除；dequeue 才移除。
test "mailbox peek does not remove the head" {
  let mb : Mailbox[String] = Mailbox::new()
  mb.enqueue("a")
  mb.enqueue("b")
  assert_eq(mb.peek(), Some("a"))
  assert_eq(mb.length(), 2)
  assert_eq(mb.dequeue(), Some("a"))
  assert_eq(mb.peek(), Some("b"))
  assert_eq(mb.length(), 1)
}
