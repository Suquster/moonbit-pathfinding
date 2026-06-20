// prop_p12_ask_match_test.mbt —— Property 12：ask 响应-请求匹配唯一性（任务 5.3）。
//
//   Feature: actor, Property 12: ask 响应-请求匹配唯一性
//   ------------------------------------------------------------------
//   *对任意* 并发 ask 请求集合，每个响应恰匹配其原始请求的关联 id，至多被消费
//   一次，且不会被匹配到其它关联 id。
//
// **Validates: Requirements 4.3, 4.5, 4.6**

///|
/// 单次场景：分配若干 id，为每个 id 回填一个**与 id 绑定的可辨识响应**（resp = id*7+1），
/// 然后 poll：断言每个 id 的响应恰为其绑定值（不串号）、且重复 poll 不再命中（至多消费一次）。
fn p12_ask_match(rng : @infra_pbt.Rng) -> Bool {
  let broker : AskBroker[Int] = AskBroker::new()
  let n = rng.next_range(1, 30)
  let ids : Array[CorrelationId] = []
  for _i in 0..<n {
    ids.push(broker.allocate())
  }
  // 以随机顺序回填，响应值与 id 唯一绑定。
  let order : Array[Int] = []
  for i in 0..<n {
    order.push(i)
  }
  // 简单打乱。
  for i in 0..<n {
    let j = rng.next_range(0, n - 1)
    let tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  for k in order {
    broker.fulfill(ids[k], ids[k].value * 7 + 1)
  }
  // poll：每个 id 恰得其绑定响应（不串号）。
  for i in 0..<n {
    match broker.poll(ids[i]) {
      Replied(v) => if v != ids[i].value * 7 + 1 { return false }
      Timeout => return false
    }
  }
  // 重复 poll：至多消费一次 —— 再 poll 得 Timeout。
  for i in 0..<n {
    match broker.poll(ids[i]) {
      Timeout => ()
      Replied(_) => return false
    }
  }
  true
}

///|
/// Feature: actor, Property 12: ask 响应-请求匹配唯一性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 4.3, 4.5, 4.6**
test "Feature: actor, Property 12: each response matches its correlation id and is consumed at most once (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p12_ask_match(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
