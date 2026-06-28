// messaging_test.mbt —— 消息传递单元测试（任务 6.2）。
//
// 覆盖单次发送产生确定投递、`EvDeliver.time > EvSend.time`、消息 id 单调分配的
// 见证（R2.2 / R2.3 / R2.4）。

///|
/// 提取首个 EvSend 与首个 EvDeliver 的 (time, msg.id)。
fn first_send_deliver(
  trace : Array[SimEvent],
) -> ((UInt64, Int)?, (UInt64, Int)?) {
  let mut snd : (UInt64, Int)? = None
  let mut dlv : (UInt64, Int)? = None
  for e in trace {
    match e {
      EvSend(time~, msg~, ..) =>
        match snd {
          None => snd = Some((time, msg.id))
          Some(_) => ()
        }
      EvDeliver(time~, msg~, ..) =>
        match dlv {
          None => dlv = Some((time, msg.id))
          Some(_) => ()
        }
      _ => ()
    }
  }
  (snd, dlv)
}

///|
/// 单次发送恰对应一次投递，且投递时间严格晚于发送、消息 id 一致。
test "send pairs with one deliver, deliver later than send" {
  let sc = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [],
    [],
    one_send_protocol(),
    30,
  )
  let r = run_des(11, sc)
  @test.assert_eq(count_deliveries(r.trace), 1)
  let (snd, dlv) = first_send_deliver(r.trace)
  match (snd, dlv) {
    (Some((st, sid)), Some((dt, did))) => {
      assert_true(dt > st)
      @test.assert_eq(sid, did)
    }
    _ => fail("expected one send and one deliver")
  }
}

///|
/// 消息 id 单调分配：两条发送的 id 互异且递增。
test "message ids are assigned monotonically" {
  let sc = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [],
    [],
    double_send_protocol(),
    30,
  )
  let r = run_des(11, sc)
  let ids : Array[Int] = []
  for e in r.trace {
    match e {
      EvSend(msg~, ..) => ids.push(msg.id)
      _ => ()
    }
  }
  @test.assert_eq(ids.length(), 2)
  assert_true(ids[0] < ids[1])
}
