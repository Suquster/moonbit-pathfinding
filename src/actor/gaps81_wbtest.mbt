// gaps81_wbtest.mbt —— Future 未就绪链路与 Router 可观测余臂收口（第八十一批）。

///|
/// 构造一个永不就绪的 future（直接给出 resolve 闭包）。
fn pending_future() -> Future[Int] {
  { resolve: () => Timeout, cached: None }
}

///|
/// and_then：首段未就绪时整体未就绪。
test "future：and_then 首段未就绪整体 Timeout" {
  let f = pending_future().and_then(v => Future::ready(v + 1))
  assert_true(f.poll_result() is Timeout)
}

///|
/// await_within：预算耗尽（budget=0）且未就绪 → Timeout。
test "future：await_within 预算耗尽返回 Timeout" {
  let sys : ActorSystem[Int, Int] = ActorSystem::with_seed(3UL)
  let _a = sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) }))
  assert_true(pending_future().await_within(sys, 0) is Timeout)
}

///|
/// worker_for_key：空 worker 集返回哨兵 id -1。
test "router：空 worker 集 worker_for_key 哨兵" {
  let r : Router[Int] = Router::new(ConsistentHash, [])
  assert_eq(r.worker_for_key("k").value, -1)
}

///|
/// index_for_key：空环回退下标 0。
test "router：空环 index_for_key 回退 0" {
  let r : Router[Int] = Router::new(ConsistentHash, [])
  assert_eq(r.index_for_key("k"), 0)
}

///|
/// worker_for_key：非一致性哈希策略以当前游标对应 worker 为可观测目标。
test "router：RoundRobin worker_for_key 取游标 worker" {
  let sys : ActorSystem[Int, Int] = ActorSystem::with_seed(5UL)
  let a = sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) }))
  let b = sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) }))
  let r = Router::new(RoundRobin, [a, b])
  assert_eq(r.worker_for_key("any").value, a.id.value)
}
