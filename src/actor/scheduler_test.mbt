// scheduler_test.mbt —— Actor_Framework 调度器（任务 16.2）的单元测试。
//
// 覆盖 16.2 的核心契约（确定性夹具，非属性测试——FIFO / 串行 / 隔离的
// 属性 Property 22/23 由任务 16.3 / 16.4 承载）：
//   1. 单 actor 的消息按 FIFO 顺序处理（Requirement 10.2 / 10.4）；
//   2. 每次 step 至多处理一条消息（单 actor 串行不变量，Requirement 10.3）；
//   3. 空邮箱 actor 挂起、step 返回空闲（Requirement 10.5）；
//   4. 未捕获错误终止该 actor 并通知 supervisor、隔离其他 actor（Requirement 10.6）；
//   5. stop 在处理完当前消息后停止消息循环，残留消息不再处理（Requirement 10.7）。

// ─────────────────────── FIFO 顺序（10.2 / 10.4） ───────────────────────

///|
/// 单 actor 的消息按投递（FIFO）顺序处理：依次追加得到有序结果。
test "scheduler processes a single actor's messages in fifo order" {
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let a = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  a.send(1)
  a.send(2)
  a.send(3)
  sched.run_until_idle()
  @test.assert_eq(sched.state_of(a), Some([1, 2, 3]))
  @test.assert_eq(sched.pending(a), 0)
  assert_true(sched.is_running(a))
}

// ─────────────────────── 串行处理（10.3） ───────────────────────────────

///|
/// 每次 step 至多处理一条消息：邮箱逐条递减，状态逐步累加。
test "scheduler step processes exactly one message per call" {
  let sched : Scheduler[Int, Int] = Scheduler::new()
  let a = sched.spawn(0, fn(s, m) { Updated(s + m) })
  a.send(10)
  a.send(20)
  @test.assert_eq(sched.pending(a), 2)
  let did1 = sched.step()
  assert_true(did1)
  @test.assert_eq(sched.pending(a), 1)
  @test.assert_eq(sched.state_of(a), Some(10))
  let did2 = sched.step()
  assert_true(did2)
  @test.assert_eq(sched.pending(a), 0)
  @test.assert_eq(sched.state_of(a), Some(30))
  // 邮箱已空：再 step 为空闲。
  assert_false(sched.step())
}

// ─────────────────────── 空邮箱挂起（10.5） ─────────────────────────────

///|
/// 所有 actor 邮箱为空时，step 返回 false（挂起，不占处理步）。
test "scheduler step on empty mailboxes is idle" {
  let sched : Scheduler[Int, Int] = Scheduler::new()
  let _ = sched.spawn(0, fn(s, m) { Updated(s + m) })
  assert_false(sched.step())
}

// ─────────────────────── 错误隔离（10.6） ───────────────────────────────

///|
/// 处理期未捕获错误：终止该 actor（Failed）、通知 supervisor、丢弃其残留消息，
/// 且不影响其他 actor 继续处理。
test "uncaught error terminates the actor, notifies supervisor, isolates others" {
  // 以可变数组承载 supervisor 收到的通知（闭包按引用捕获）。
  let notices : Array[(Int, String)] = []
  let sched : Scheduler[Int, Int] = Scheduler::new()
  let bad = sched.spawn(
    0,
    fn(s, m) {
      if m < 0 {
        Errored("negative:" + m.to_string())
      } else {
        Updated(s + m)
      }
    },
    supervisor=fn(id, reason) { notices.push((id.value, reason)) },
  )
  let good = sched.spawn(0, fn(s, m) { Updated(s + m) })
  // bad：处理 5 → 遇 -1 崩溃 → 100 应被丢弃。
  bad.send(5)
  bad.send(-1)
  bad.send(100)
  // good：不受 bad 崩溃影响。
  good.send(7)
  good.send(8)
  sched.run_until_idle()
  // 失败 actor 被隔离终止。
  @test.assert_eq(sched.status_of(bad), Some(Failed("negative:-1")))
  @test.assert_eq(sched.state_of(bad), Some(5))
  @test.assert_eq(sched.pending(bad), 0)
  assert_false(sched.is_running(bad))
  // supervisor 恰好收到一次通知，且携带正确的 actor id 与错误描述。
  @test.assert_eq(notices.length(), 1)
  @test.assert_eq(notices[0], (bad.id.value, "negative:-1"))
  // 其他 actor 不受影响，完整处理其全部消息。
  assert_true(sched.is_running(good))
  @test.assert_eq(sched.state_of(good), Some(15))
}

// ─────────────────────── stop 语义（10.7） ──────────────────────────────

///|
/// stop 在处理完当前消息后停止消息循环：已处理的消息生效，残留消息被丢弃。
test "stop halts the message loop after the current message" {
  let sched : Scheduler[Int, Int] = Scheduler::new()
  let a = sched.spawn(0, fn(s, m) { Updated(s + m) })
  a.send(1)
  a.send(2)
  a.send(3)
  // 处理完「当前消息」1。
  let _ = sched.step()
  @test.assert_eq(sched.state_of(a), Some(1))
  // 请求停止：2、3 不应再被处理。
  a.stop()
  sched.run_until_idle()
  @test.assert_eq(sched.status_of(a), Some(Stopped))
  @test.assert_eq(sched.state_of(a), Some(1))
  @test.assert_eq(sched.pending(a), 0)
}

///|
/// 多 actor 公平推进：各自的消息均按 FIFO 顺序串行处理，互不串扰。
test "scheduler advances multiple actors preserving per-actor fifo" {
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let a = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  let b = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  a.send(1)
  b.send(10)
  a.send(2)
  b.send(20)
  sched.run_until_idle()
  @test.assert_eq(sched.state_of(a), Some([1, 2]))
  @test.assert_eq(sched.state_of(b), Some([10, 20]))
}
