// 白盒测试：覆盖率审计收口（INFRA 第四十六批）——
// DPOR 事件节点/消息 id 余支、EventuallyResult 渲染、demo 字符串工具边界。

///|
test "dpor / des_types：EvFaulted 节点提取与同消息 id 依赖判定" {
  let f = EvFaulted(time=1UL, task_id=3, kind=Crash)
  assert_eq(f.actor_of(), 3)
  // EvFaulted 与自身共享节点 → 相关。
  assert_true(depends(f, f))
  // 节点不相交但消息 id 相同 → 仍相关（同一消息的发送与投递）。
  let m : Message = { id: 7, payload: 0 }
  let s = EvSend(time=1UL, from=0, to=1, msg=m)
  let d = EvDeliver(time=2UL, from=2, to=3, msg=m)
  assert_true(depends(s, d))
}

///|
test "dpor：task_indep 未知任务 id 保守视为相关" {
  assert_false(task_indep([[false]], [1], 2, 3))
}

///|
test "eventually：EventuallyResult Show 渲染" {
  assert_eq(EventuallyResult::EHolds(step=2).to_string(), "EHolds(step=2)")
  assert_eq(EventuallyResult::ENeverHeld.to_string(), "ENeverHeld")
}

///|
test "demo：str_contains 空针与针长于草垛边界" {
  assert_true(str_contains("abc", ""))
  assert_false(str_contains("a", "ab"))
}
