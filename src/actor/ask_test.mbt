// ask_test.mbt —— ask 注册表单元测试（任务 5.4）。
//
// 覆盖：未回填即 poll 得 Timeout、重复 poll 不二次消费见证。
// _Requirements: 4.4_

///|
/// 未回填即 poll：得 Timeout。
test "poll without fulfill yields Timeout" {
  let broker : AskBroker[Int] = AskBroker::new()
  let id = broker.allocate()
  match broker.poll(id) {
    Timeout => ()
    Replied(_) => fail("expected Timeout")
  }
}

///|
/// 回填后 poll 得 Replied；重复 poll 不二次消费（得 Timeout）。
test "poll consumes a reply at most once" {
  let broker : AskBroker[String] = AskBroker::new()
  let id = broker.allocate()
  broker.fulfill(id, "ok")
  assert_true(broker.has_reply(id))
  match broker.poll(id) {
    Replied(v) => @test.assert_eq(v, "ok")
    Timeout => fail("expected Replied")
  }
  // 已消费：不再持有响应，再 poll 得 Timeout。
  assert_false(broker.has_reply(id))
  match broker.poll(id) {
    Timeout => ()
    Replied(_) => fail("expected Timeout after consumption")
  }
}

///|
/// 已消费的 id 不再接受回填（保持至多消费一次的语义边界）。
test "fulfill after consumption is ignored" {
  let broker : AskBroker[Int] = AskBroker::new()
  let id = broker.allocate()
  broker.fulfill(id, 1)
  let _ = broker.poll(id)
  broker.fulfill(id, 2)
  match broker.poll(id) {
    Timeout => ()
    Replied(_) => fail("expected Timeout; consumed id must not accept refill")
  }
}

///|
/// CorrelationId / AskResult 派生 Eq / Show 见证。
test "CorrelationId and AskResult derive Eq and Show" {
  let a : CorrelationId = { value: 3 }
  @test.assert_eq(a, { value: 3 })
  let r : AskResult[Int] = Replied(5)
  @test.assert_eq(r, Replied(5))
  let t : AskResult[Int] = Timeout
  assert_true(r != t)
}
