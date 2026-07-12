// 白盒测试：覆盖率审计收口（INFRA 第六十七批）——
// 逻辑时钟读数、未知节点阻断判定、Failed 终态短路与分区分组非分区兜底。

///|
fn gaps4_world() -> World {
  let protocol = Protocol::new(
    fn(_id) { { log: [], kv: [] } },
    fn(app, _msg) { (app, []) },
    fn(_id) { [] },
  )
  let scenario = DesScenario::new([Task::new(1, "n1")], [], [], protocol, 8)
  World::new(11UL, scenario)
}

///|
test "des_sim：clock_now 读数与内部时钟一致" {
  let w = gaps4_world()
  assert_true(w.clock_now() == w.clock)
}

///|
test "des_sim：is_blocked 未知发送方节点即阻断" {
  let w = gaps4_world()
  assert_true(w.is_blocked(99, 1))
}

///|
test "des_sim：Failed 终态下 step_with 直接短路" {
  let w = gaps4_world()
  w.status = Failed(reason="boom")
  assert_false(w.step_with(fn(_w) { 0 }))
}

///|
test "des_sim：active_group 忽略非分区类故障策略" {
  let w = gaps4_world()
  w.partitions.push(FaultPolicyEx::new(0, 1, DiskFault(lose=1)))
  assert_true(w.active_group(1) is None)
}
