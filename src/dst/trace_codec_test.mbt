// trace_codec_test.mbt —— 轨迹持久化单元测试（任务 15.2）。
//
// 覆盖格式非法 / 损坏文本返回携带原因与偏移的 Malformed（且不产生部分构造 DesResult）、
// 多余尾部记号被拒、合法结果往返一致的见证（R8.5）。

///|
/// 损坏输入（非数字记号）返回 Malformed 且偏移合法。
test "deserialize_result reports Malformed on corrupt input" {
  match deserialize_result("not a valid encoding") {
    Err(e) => assert_true(e.pos() >= 0)
    Ok(_) => fail("expected Malformed on corrupt input")
  }
}

///|
/// 多余尾部记号被拒（不产生部分构造结果）。
test "deserialize_result rejects trailing garbage" {
  let r : DesResult = { seed: 1, trace: [], status: Completed, finals: [] }
  let s = serialize_result(r) + " 999"
  match deserialize_result(s) {
    Err(_) => ()
    Ok(_) => fail("expected error on trailing garbage")
  }
}

///|
/// 合法结果（含各类事件 / 失败原因 / 节点终态）往返逐字段一致。
test "serialize/deserialize round-trips a rich result" {
  let r : DesResult = {
    seed: 42,
    trace: [
      EvScheduled(time=1UL, task_id=0),
      EvFaulted(time=2UL, task_id=1, kind=NetFaultKind::ClockSkew(offset=-3L)),
      EvSend(time=3UL, from=0, to=1, msg={ id: 0, payload: 7 }),
      EvDeliver(time=4UL, from=0, to=1, msg={ id: 0, payload: 7 }),
    ],
    status: Failed(reason="副本不一致"),
    finals: [(0, { log: [1, 2], kv: [("k", 3)] }), (1, NodeApp::empty())],
  }
  match deserialize_result(serialize_result(r)) {
    Ok(r2) => @test.assert_eq(r2, r)
    Err(_) => fail("round-trip should succeed")
  }
}

///|
/// Byzantine 与 DiskFault 故障种类编解码往返 + 截断记号流拒绝。
test "serialize/deserialize covers Byzantine/DiskFault and truncation" {
  let r : DesResult = {
    seed: 7,
    trace: [
      EvFaulted(time=1UL, task_id=0, kind=NetFaultKind::Byzantine),
      EvFaulted(time=2UL, task_id=1, kind=NetFaultKind::DiskFault(lose=3)),
    ],
    status: Completed,
    finals: [],
  }
  let s = serialize_result(r)
  match deserialize_result(s) {
    Err(_) => fail("Byzantine/DiskFault 往返失败")
    Ok(r2) => {
      assert_eq(r2.seed, 7UL)
      assert_true(r2.trace[0] is EvFaulted(kind=NetFaultKind::Byzantine, ..))
      assert_true(
        r2.trace[1] is EvFaulted(kind=NetFaultKind::DiskFault(lose=3), ..),
      )
    }
  }
  // 截断记号流：任意前缀（按空白切分后去尾）不得成功。
  let toks = s.split(" ").collect()
  if toks.length() > 2 {
    let sb = StringBuilder::new()
    for k in 0..<(toks.length() - 1) {
      if k > 0 {
        sb.write_char(' ')
      }
      sb.write_string(toks[k].to_owned())
    }
    assert_true(deserialize_result(sb.to_string()) is Err(_))
  }
}
