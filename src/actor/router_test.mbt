// router_test.mbt —— 路由器单元测试（任务 8.5）。
//
// 覆盖：三策略分发见证、worker_for_key 稳定性见证。
// _Requirements: 8.1_

///|
/// RoundRobin 见证：3 worker、5 条消息 → 命中数 [2,2,1]。
test "round-robin distributes in cycle (witness)" {
  reset_runtime()
  let workers : Array[ActorRef[Int]] = [
    spawn(0, fn(s, _m) { s }),
    spawn(0, fn(s, _m) { s }),
    spawn(0, fn(s, _m) { s }),
  ]
  let router = Router::new(RoundRobin, workers)
  for i in 0..<5 {
    router.route(i)
  }
  assert_eq(workers[0].pending(), 2)
  assert_eq(workers[1].pending(), 2)
  assert_eq(workers[2].pending(), 1)
}

///|
/// Broadcast 见证：每个 worker 收到全部消息。
test "broadcast delivers to all workers (witness)" {
  reset_runtime()
  let workers : Array[ActorRef[Int]] = [
    spawn(0, fn(s, _m) { s }),
    spawn(0, fn(s, _m) { s }),
  ]
  let router = Router::new(Broadcast, workers)
  router.route(1)
  router.route(2)
  router.route(3)
  assert_eq(workers[0].pending(), 3)
  assert_eq(workers[1].pending(), 3)
}

///|
/// ConsistentHash 见证：同键稳定命中同一 worker，且 worker_count 正确。
test "consistent hash is stable for the same key (witness)" {
  reset_runtime()
  let workers : Array[ActorRef[Int]] = [
    spawn(0, fn(s, _m) { s }),
    spawn(0, fn(s, _m) { s }),
    spawn(0, fn(s, _m) { s }),
  ]
  let router = Router::new(ConsistentHash, workers)
  assert_eq(router.worker_count(), 3)
  let a = router.worker_for_key("alpha")
  let b = router.worker_for_key("alpha")
  assert_eq(a, b)
  // 路由实际分发到同一 worker。
  router.route_keyed("alpha", 1)
  router.route_keyed("alpha", 2)
  // 命中 worker 的 pending 为 2，其余之和为 0。
  let mut total = 0
  let mut hit = 0
  for w in workers {
    total = total + w.pending()
    if w.id == a {
      hit = w.pending()
    }
  }
  assert_eq(total, 2)
  assert_eq(hit, 2)
}
