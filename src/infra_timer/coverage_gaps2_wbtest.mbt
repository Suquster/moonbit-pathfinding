// 白盒测试：优先级队列空弹出、时间轮取消越界、工作窃取规模查询。

///|
test "timer：空 PrioQueue 弹出 None" {
  let q : PrioQueue[Int] = PrioQueue::new()
  assert_true(q.pop() is None)
}

///|
test "timer：时间轮取消越界 id 拒绝" {
  let w = TimerWheel::new()
  assert_eq(w.cancel(-1), false)
  assert_eq(w.cancel(999), false)
}

///|
test "timer：工作窃取调度器 worker 数" {
  let s : WorkStealingScheduler = WorkStealingScheduler::new(3)
  assert_eq(s.workers(), 3)
}
