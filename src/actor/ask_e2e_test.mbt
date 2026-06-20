// ask_e2e_test.mbt —— ask 端到端单元测试（任务 12.3）。
//
// 覆盖：Replied 命中与 Timeout 见证。
// _Requirements: 4.3, 4.4_

///|
/// Replied 见证：被请求 actor 在处理请求时回填响应，ask 取回匹配响应。
test "ask returns Replied when the target fulfills the correlation id (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  // 被请求 actor：消息即关联 id 值，处理时回填 resp = id * 10。
  let target = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      broker.fulfill({ value: m }, m * 10)
      Updated(s + 1)
    }),
  )
  let result = ask(sys, broker, target, fn(id) { id.value }, 5)
  match result {
    Replied(v) => assert_eq(v, 10) // 第一个关联 id 为 1 → resp = 10。
    Timeout => fail("expected Replied")
  }
}

///|
/// Timeout 见证：沉默 actor 不回填，ask 在预算内得 Timeout。
test "ask returns Timeout when the target never replies (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  let target = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let result = ask(sys, broker, target, fn(id) { id.value }, 5)
  match result {
    Timeout => ()
    Replied(_) => fail("expected Timeout")
  }
}

///|
/// 多次 ask 关联 id 递增且互不串号。
test "consecutive asks use distinct correlation ids (witness)" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  let target = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      broker.fulfill({ value: m }, m * 100)
      Updated(s + 1)
    }),
  )
  let r1 = ask(sys, broker, target, fn(id) { id.value }, 5)
  let r2 = ask(sys, broker, target, fn(id) { id.value }, 5)
  match (r1, r2) {
    (Replied(a), Replied(b)) => {
      assert_eq(a, 100) // id 1
      assert_eq(b, 200) // id 2
    }
    _ => fail("expected two Replied results")
  }
}
