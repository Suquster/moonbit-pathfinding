// 白盒测试：覆盖率审计收口（INFRA 第六十二批）——
// des_sim 磁盘故障前缀保留、未知节点余支、空队列无操作与 PWake 投递臂。

///|
fn gaps3_world(log_init : Array[Int]) -> World {
  let protocol = Protocol::new(
    fn(_id) { { log: log_init.copy(), kv: [] } },
    fn(app, _msg) { (app, []) },
    fn(_id) { [] },
  )
  let scenario = DesScenario::new([Task::new(1, "n1")], [], [], protocol, 8)
  World::new(7UL, scenario)
}

///|
test "des_sim：DiskFault 丢失末尾条目保留日志前缀" {
  let w = gaps3_world([10, 20, 30])
  w.apply_fault(FaultPolicyEx::new(0, 1, DiskFault(lose=1)))
  guard w.find_node(1) is Some(n)
  assert_true(n.app.log == [10, 20])
}

///|
test "des_sim：apply_actions 未知节点 ActAppend 安全忽略" {
  let w = gaps3_world([])
  w.apply_actions(99, [ActAppend(value=5)])
  guard w.find_node(1) is Some(n)
  assert_true(n.app.log == [])
}

///|
test "des_sim：do_wake 待调度含未知任务 id 仍记录调度/完成轨迹" {
  let w = gaps3_world([])
  w.pending = [99]
  w.do_wake(0)
  assert_eq(w.pending.length(), 0)
  assert_eq(w.trace_view().length(), 2)
}

///|
test "des_sim：do_deliver_step 空队列为无操作" {
  let w = gaps3_world([])
  w.do_deliver_step()
  assert_eq(w.trace_view().length(), 0)
}

///|
test "des_sim：do_deliver_step 处理 PWake 记录调度/完成事件" {
  let w = gaps3_world([])
  w.queue = w.queue.push({
    time: 1UL,
    task_id: 1,
    order_key: 0UL,
    pending: PWake(task_id=1),
  })
  w.do_deliver_step()
  assert_true(w.trace_view()[0] is EvScheduled(..))
  assert_true(w.trace_view()[1] is EvCompleted(..))
}
