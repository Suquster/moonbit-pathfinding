// dpor_test.mbt —— DPOR 依赖关系与约简单元测试（任务 12.2）。
//
// 覆盖同任务事件 / 同消息 send-deliver / 共享节点判为依赖，不同任务无因果关联判为
// 独立的见证（R6.2），以及独立任务交错的实际约简效果。

///|
/// depends 分类：同节点 / 同消息 / 共享节点为依赖；不同节点无因果为独立。
test "depends classifies dependent vs independent events" {
  let a : SimEvent = EvScheduled(time=1UL, task_id=0)
  let b : SimEvent = EvCompleted(time=2UL, task_id=0)
  assert_true(depends(a, b)) // 同任务节点 0
  let s : SimEvent = EvSend(time=1UL, from=0, to=1, msg={ id: 5, payload: 1 })
  let d : SimEvent = EvDeliver(time=2UL, from=0, to=1, msg={ id: 5, payload: 1 })
  assert_true(depends(s, d)) // 共享节点 / 同消息 id
  let x : SimEvent = EvScheduled(time=1UL, task_id=0)
  let y : SimEvent = EvScheduled(time=1UL, task_id=1)
  assert_false(depends(x, y)) // 不同节点、无消息因果
}

///|
/// 独立任务：DPOR 仅探索一个代表交错，而有界穷尽探索枚举全部 3! = 6 个。
test "explore_dpor reduces independent interleavings" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let sc = DesScenario::new(tasks, [], [], null_protocol(), 8)
  let b = explore_bounded(1, sc, 3)
  let d = explore_dpor(1, sc, 3)
  assert_eq(b.explored, 6)
  assert_eq(d.explored, 1)
  assert_true(d.explored <= b.explored)
}
