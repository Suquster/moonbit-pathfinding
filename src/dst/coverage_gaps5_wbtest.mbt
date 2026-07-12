// 白盒测试：覆盖率审计收口（INFRA 第七十八批）——
// 未知/已崩溃节点的消息发送与投递余臂；序列化结果任意前缀截断拒绝。

///|
fn gaps5_world() -> World {
  let protocol = Protocol::new(
    fn(_id) { NodeApp::empty() },
    fn(app, msg) {
      app.log.push(msg.payload)
      (app, [])
    },
    fn(_id) { [] },
  )
  let scenario = DesScenario::new(
    [Task::new(1, "n1"), Task::new(2, "n2")],
    [],
    [],
    protocol,
    8,
  )
  World::new(3UL, scenario)
}

///|
test "schedule_send：未知来源节点按零偏移无故障处理" {
  let w = gaps5_world()
  let before = w.msg_seq
  let _ = w.schedule_send(99, 1, 7, 1UL)
  assert_eq(w.msg_seq, before + 1)
}

///|
test "deliver：未知目标与已崩溃目标均静默丢弃" {
  let w = gaps5_world()
  let msg : Message = { id: 0, payload: 5 }
  let _ = w.deliver(1, 99, msg)
  guard w.find_node(2) is Some(n2)
  n2.alive = false
  let _ = w.deliver(1, 2, msg)
  assert_eq(n2.app.log.length(), 0)
}

///|
test "result_of_bytes：任意真前缀截断均拒绝" {
  let r : DesResult = {
    seed: 5UL,
    trace: [],
    status: Failed(reason="x"),
    finals: [(1, { log: [3, 4], kv: [("k", 9)] })],
  }
  let bytes = result_to_bytes(r)
  let n = bytes.length()
  for len in 0..<n {
    let prefix : Array[Byte] = []
    for i in 0..<len {
      prefix.push(bytes[i])
    }
    assert_true(result_of_bytes(Bytes::from_array(prefix)) is None)
  }
}
