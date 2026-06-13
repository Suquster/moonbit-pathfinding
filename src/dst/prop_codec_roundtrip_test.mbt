// prop_codec_roundtrip_test.mbt —— Property 14：序列化往返（任务 15.3）。
//
// Feature: dst, Property 14: 序列化往返（对任意 DesResult r，deserialize_result(
// serialize_result(r)) 返回 Ok(r') 且 r' 与 r 逐字段一致；等价地经 result_to_bytes /
// result_of_bytes 适配的 @infra_pbt.round_trip 成立）。
//
// **Validates: Requirements 8.3, 8.6**

///|
/// 生成一个随机富事件。
fn p14_event(rng : @infra_pbt.Rng) -> SimEvent {
  let time = rng.next_range(0, 100000).to_uint64()
  let tid = rng.next_range(0, 5)
  match rng.next_below(5) {
    0 => EvScheduled(time~, task_id=tid)
    1 => EvCompleted(time~, task_id=tid)
    2 => EvFaulted(time~, task_id=tid, kind=sample_netfault(rng, 5))
    3 =>
      EvSend(
        time~,
        from=tid,
        to=rng.next_range(0, 5),
        msg={ id: rng.next_range(0, 100), payload: rng.next_range(-50, 50) },
      )
    _ =>
      EvDeliver(
        time~,
        from=tid,
        to=rng.next_range(0, 5),
        msg={ id: rng.next_range(0, 100), payload: rng.next_range(-50, 50) },
      )
  }
}

///|
/// 生成器：随机 DesResult（随机种子 / 轨迹 / 终态 / 节点终态）。
fn p14_gen() -> @infra_pbt.Gen[DesResult] {
  @infra_pbt.Gen::new(fn(rng) {
    let seed = rng.next()
    let len = rng.next_range(0, 6)
    let trace : Array[SimEvent] = []
    for _ in 0..<len {
      trace.push(p14_event(rng))
    }
    let status : SimStatus = if rng.next_bool() {
      Completed
    } else {
      Failed(reason="boom-\{rng.next_below(1000)}")
    }
    let fl = rng.next_range(0, 3)
    let finals : Array[(Int, NodeApp)] = []
    for i in 0..<fl {
      let loglen = rng.next_range(0, 4)
      let log : Array[Int] = []
      for _ in 0..<loglen {
        log.push(rng.next_range(-20, 20))
      }
      let kvlen = rng.next_range(0, 2)
      let kv : Array[(String, Int)] = []
      for j in 0..<kvlen {
        kv.push(("k\{j}", rng.next_range(-5, 5)))
      }
      finals.push((i, { log, kv }))
    }
    { seed, trace, status, finals }
  })
}

///|
/// **Validates: Requirements 8.3, 8.6**
test "Feature: dst, Property 14: DesResult serialization round-trip" {
  let ok = @infra_pbt.round_trip(p14_gen(), result_to_bytes, result_of_bytes)
  assert_true(ok)
}
