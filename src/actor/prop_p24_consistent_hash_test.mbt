// prop_p24_consistent_hash_test.mbt —— Property 24：ConsistentHash 分发稳定（任务 8.4）。
//
//   Feature: actor, Property 24: ConsistentHash 分发稳定
//   ------------------------------------------------------------------
//   *对任意* 路由键序列，`ConsistentHash` 在 worker 集合不变时对相同键的分发目标
//   保持稳定（同键 → 同 worker）。
//
// **Validates: Requirements 8.4, 8.5, 8.8**

///|
/// 单次场景：构造 ConsistentHash 路由器，对随机键集合多轮查询 worker_for_key，
/// 断言同一键每轮命中同一 worker（稳定性）。
fn p24_consistent_hash_stable(rng : @infra_pbt.Rng) -> Bool {
  reset_runtime()
  let w = rng.next_range(1, 8)
  let workers : Array[ActorRef[Int]] = []
  for _i in 0..<w {
    workers.push(spawn(0, fn(s, _m) { s }))
  }
  let router = Router::new(ConsistentHash, workers)
  // 随机键集合。
  let keys : Array[String] = []
  let nk = rng.next_range(1, 12)
  for _i in 0..<nk {
    keys.push("key-\{rng.next_range(0, 100)}")
  }
  // 第一轮记录每个键命中的 worker。
  let first : Array[Int] = []
  for key in keys {
    first.push(router.worker_for_key(key).value)
  }
  // 多轮复查：同键稳定命中同一 worker。
  for _round in 0..<3 {
    for i in 0..<keys.length() {
      if router.worker_for_key(keys[i]).value != first[i] {
        return false
      }
    }
  }
  // 命中的 worker 必为集合内的合法 id。
  for v in first {
    let mut found = false
    for worker in workers {
      if worker.id.value == v {
        found = true
      }
    }
    if !(found) {
      return false
    }
  }
  true
}

///|
/// Feature: actor, Property 24: ConsistentHash 分发稳定（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 8.4, 8.5, 8.8**
test "Feature: actor, Property 24: consistent hashing maps the same key to the same worker (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p24_consistent_hash_stable(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
