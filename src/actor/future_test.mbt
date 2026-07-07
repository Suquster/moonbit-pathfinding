// future_test.mbt —— async/await 风格 ask（`Future[R]`）单元测试（C2）。
//
// 覆盖：ask_future + await_within 端到端、并发在飞多请求、Timeout 见证、
// ready / map / and_then 组合子、幂等重复 await。

///|
/// 端到端：ask_future 立即返回句柄，await_within 驱动系统直至 Replied。
test "ask_future then await_within returns Replied (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  let target = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      broker.fulfill({ value: m }, m * 10)
      Updated(s + 1)
    }),
  )
  let fut = ask_future(sys, broker, target, fn(id) { id.value })
  // 发起后未驱动系统：尚未就绪。
  assert_true(!fut.is_ready())
  match fut.await_within(sys, 5) {
    Replied(v) => @test.assert_eq(v, 10)
    Timeout => fail("expected Replied")
  }
  // 幂等：重复 await 返回缓存结果，不二次消费。
  match fut.await_within(sys, 5) {
    Replied(v) => @test.assert_eq(v, 10)
    Timeout => fail("expected cached Replied")
  }
}

///|
/// 并发在飞：先发起两个请求再分别 await，互不串号。
test "two in-flight futures resolve independently (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  let target = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      broker.fulfill({ value: m }, m * 100)
      Updated(s + 1)
    }),
  )
  let f1 = ask_future(sys, broker, target, fn(id) { id.value })
  let f2 = ask_future(sys, broker, target, fn(id) { id.value })
  match (f2.await_within(sys, 10), f1.await_within(sys, 10)) {
    (Replied(b), Replied(a)) => {
      @test.assert_eq(a, 100) // id 1
      @test.assert_eq(b, 200) // id 2
    }
    _ => fail("expected two Replied results")
  }
}

///|
/// Timeout 见证：沉默 actor 不回填，await 预算耗尽得 Timeout；之后仍可再等。
test "await_within returns Timeout for a silent target (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  let target = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let fut = ask_future(sys, broker, target, fn(id) { id.value })
  match fut.await_within(sys, 5) {
    Timeout => ()
    Replied(_) => fail("expected Timeout")
  }
}

///|
/// 组合子：ready 立即就绪；map 变换结果；and_then 链式续体。
test "Future ready / map / and_then combinators" {
  let base : Future[Int] = Future::ready(7)
  assert_true(base.is_ready())
  let mapped = base.map(fn(v) { v + 1 })
  match mapped.poll_result() {
    Replied(v) => @test.assert_eq(v, 8)
    Timeout => fail("expected mapped Replied")
  }
  let chained = base.and_then(fn(v) { Future::ready(v * 2) })
  match chained.poll_result() {
    Replied(v) => @test.assert_eq(v, 14)
    Timeout => fail("expected chained Replied")
  }
}

///|
/// 组合子接真实 ask：map 在 await 后生效，链路端到端一致。
test "map over a real ask future (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  let target = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      broker.fulfill({ value: m }, m + 5)
      Updated(s + 1)
    }),
  )
  let fut = ask_future(sys, broker, target, fn(id) { id.value }).map(fn(v) {
    v * 3
  })
  match fut.await_within(sys, 5) {
    Replied(v) => @test.assert_eq(v, 18) // (1 + 5) * 3
    Timeout => fail("expected Replied")
  }
}
