// event_queue_test.mbt —— 全序事件队列单元测试（任务 3.2）。
//
// 覆盖同时间戳按任务 id、再按次序键出队的全序见证（R1.3 / R2.1），以及空队列
// `pop_min` 返回 `None`。

///|
/// 构造一个 PWake 待处理事件（便于测试）。
fn mk_qe(time : UInt64, task_id : Int, order_key : UInt64) -> QueuedEvent {
  { time, task_id, order_key, pending: PWake(task_id~) }
}

///|
/// pop_min 严格遵循 (time, task_id, order_key) 全序。
test "pop_min returns events in total order" {
  let q0 = EventQueue::new()
  let q1 = q0.push(mk_qe(2UL, 0, 0UL))
  let q2 = q1.push(mk_qe(1UL, 5, 0UL))
  let q3 = q2.push(mk_qe(1UL, 1, 9UL))
  let q4 = q3.push(mk_qe(1UL, 1, 3UL))
  // 期望出队顺序：(1,1,3) → (1,1,9) → (1,5,0) → (2,0,0)
  let expected = [(1UL, 1, 3UL), (1UL, 1, 9UL), (1UL, 5, 0UL), (2UL, 0, 0UL)]
  let mut cur = q4
  for exp in expected {
    let (et, eid, ek) = exp
    match cur.pop_min() {
      Some((qe, rest)) => {
        @test.assert_eq(qe.time, et)
        @test.assert_eq(qe.task_id, eid)
        @test.assert_eq(qe.order_key, ek)
        cur = rest
      }
      None => fail("queue exhausted early")
    }
  }
  assert_true(cur.is_empty())
}

///|
/// 空队列 pop_min 返回 None。
test "pop_min on empty queue returns None" {
  match EventQueue::new().pop_min() {
    None => ()
    Some(_) => fail("expected None on empty queue")
  }
}

///|
/// push 为不可变 API：返回新队列，不修改原队列。
test "push is immutable and size grows" {
  let q0 = EventQueue::new()
  let q1 = q0.push(mk_qe(1UL, 0, 0UL))
  assert_true(q0.is_empty())
  @test.assert_eq(q1.size(), 1)
}
