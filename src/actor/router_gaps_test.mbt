// router_gaps_test.mbt —— 路由器空 worker/策略交叉回退分支收口
// （INFRA 第三十九批）。

///|
test "Router：空 worker 集 RoundRobin/ConsistentHash 安全早退" {
  reset_runtime()
  let none : Array[ActorRef[Int]] = []
  let rr = Router::new(RoundRobin, none)
  rr.route(1)
  assert_eq(rr.worker_count(), 0)
  let ch = Router::new(ConsistentHash, none)
  ch.route_keyed("k", 2)
  assert_eq(ch.worker_count(), 0)
}

///|
test "Router：ConsistentHash 经 route 空键退化与非哈希策略 route_keyed 回退" {
  reset_runtime()
  let workers : Array[ActorRef[Int]] = []
  for _i in 0..<3 {
    workers.push(spawn(0, fn(s, _m : Int) { s }))
  }
  // ConsistentHash 走 route → 等价 route_keyed("")。
  let ch = Router::new(ConsistentHash, workers)
  ch.route(7)
  let mut total = 0
  for w in workers {
    total = total + w.pending()
  }
  assert_eq(total, 1)
  // RoundRobin 走 route_keyed → 回退 route。
  let rr = Router::new(RoundRobin, workers)
  rr.route_keyed("ignored", 8)
  let mut total2 = 0
  for w in workers {
    total2 = total2 + w.pending()
  }
  assert_eq(total2, 2)
}
