// des_types_test.mbt —— DES 数据模型构造 / Eq / Show 见证（任务 2.2）。
//
// 确认 `Message` / `SimEvent` / `NodeApp` / `Action` / `DesResult` 的构造、相等与
// 可显示，且新增 `SimEvent` 与既有 `Event`、`SimStatus` 形态隔离（R2.1 / R12.4）。

///|
/// Message 构造与相等。
test "Message constructs and compares by fields" {
  let a : Message = { id: 1, payload: 7 }
  let b : Message = { id: 1, payload: 7 }
  let c : Message = { id: 2, payload: 7 }
  @test.assert_eq(a, b)
  @test.assert_not_eq(a, c)
}

///|
/// SimEvent 变体的时间戳 / 主任务投影与相等。
test "SimEvent variants expose time and actor" {
  let s : SimEvent = EvScheduled(time=3UL, task_id=5)
  let c : SimEvent = EvCompleted(time=3UL, task_id=5)
  @test.assert_not_eq(s, c)
  @test.assert_eq(s.time_of(), 3UL)
  @test.assert_eq(s.actor_of(), 5)
  let snd : SimEvent = EvSend(time=4UL, from=1, to=2, msg={ id: 0, payload: 9 })
  @test.assert_eq(snd.actor_of(), 1)
  let dlv : SimEvent = EvDeliver(time=5UL, from=1, to=2, msg={
    id: 0,
    payload: 9,
  })
  @test.assert_eq(dlv.actor_of(), 2)
}

///|
/// NodeApp / Action 构造与相等。
test "NodeApp and Action construct and compare" {
  let app : NodeApp = { log: [1, 2], kv: [("k", 3)] }
  let app2 = NodeApp::empty()
  @test.assert_not_eq(app, app2)
  let a1 : Action = ActSend(to=1, payload=2, after=3UL)
  let a2 : Action = ActAppend(value=9)
  @test.assert_not_eq(a1, a2)
}

///|
/// DesResult 逐字段相等（复用既有 SimStatus 作为终态）。
test "DesResult compares by fields and reuses SimStatus" {
  let r1 : DesResult = { seed: 1, trace: [], status: Completed, finals: [] }
  let r2 : DesResult = { seed: 1, trace: [], status: Completed, finals: [] }
  @test.assert_eq(r1, r2)
  let r3 : DesResult = {
    seed: 1,
    trace: [],
    status: Failed(reason="x"),
    finals: [],
  }
  @test.assert_not_eq(r1, r3)
}
