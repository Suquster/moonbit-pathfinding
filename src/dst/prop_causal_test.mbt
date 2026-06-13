// prop_causal_test.mbt —— Property 3：因果序保持（任务 6.3）。
//
// Feature: dst, Property 3: 因果序保持（不含 Drop/Partition 的收发场景中，每条
// EvSend 恰与一条 EvDeliver 按 id 一一对应，且每对 EvDeliver 逻辑时间戳严格大于
// EvSend）。
//
// **Validates: Requirements 2.2, 2.4, 2.6**

///|
/// 生成器：无故障的多副本广播场景（仅 on_start 广播、on_deliver 追加，无丢弃 / 分区）。
fn p3_gen() -> @infra_pbt.Gen[(UInt64, DesScenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 5)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "r\{i}"))
    }
    let sc = DesScenario::new(tasks, [], [], replication_protocol(n), 4 * n + 16)
    (rng.next(), sc)
  })
}

///|
/// **Validates: Requirements 2.2, 2.4, 2.6**
test "Feature: dst, Property 3: causal order preserved (one-to-one, deliver after send)" {
  let ok = @infra_pbt.holds_for_all(p3_gen(), fn(pair) {
    let (seed, sc) = pair
    let r = run_des(seed, sc)
    let sends : Array[(Int, UInt64)] = []
    let delivers : Array[(Int, UInt64)] = []
    for e in r.trace {
      match e {
        EvSend(msg~, time~, ..) => sends.push((msg.id, time))
        EvDeliver(msg~, time~, ..) => delivers.push((msg.id, time))
        _ => ()
      }
    }
    // 一一对应：发送数 == 投递数。
    if sends.length() != delivers.length() {
      return false
    }
    // 每条发送存在同 id 投递且投递时间严格更大。
    for s in sends {
      let (sid, st) = s
      let mut matched = false
      for d in delivers {
        let (did, dt) = d
        if did == sid {
          if dt > st {
            matched = true
          }
          break
        }
      }
      if !matched {
        return false
      }
    }
    true
  })
  assert_true(ok)
}
