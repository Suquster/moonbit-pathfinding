// prop_sample_trace_test.mbt —— trace 内采样一致性属性测试（任务 5.2）。
//
//   Feature: logging, Property 5: trace 内采样一致性（trace-coherent sampling）
//   --------------------------------------------------------------------
//   *对任意* 采样率、种子与归属同一 trace 的事件集合，该 trace 的全部事件采样
//   判定相同（全采或全弃）：对同一 trace，`sample_trace(rate, trace, seed)` 为常量。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 单次场景：随机 rate / seed / trace，断言对同一 trace 多次判定恒一致，且
/// rate=0 恒弃、rate=1 恒采。
fn st_coherent(rng : @infra_pbt.Rng) -> Bool {
  let rate = rng.next_range(0, 100).to_double() / 100.0
  let seed = rng.next()
  let trace : TraceId = { value: rng.next().reinterpret_as_int64() }
  // 同一 trace 的多次判定必须一致（代表该 trace 的多条事件）。
  let d0 = sample_trace(rate, trace, seed)
  for _i in 0..<8 {
    if sample_trace(rate, trace, seed) != d0 {
      return false
    }
  }
  // 边界：rate=0 恒弃、rate=1 恒采。
  if sample_trace(0.0, trace, seed) {
    return false
  }
  if !sample_trace(1.0, trace, seed) {
    return false
  }
  true
}

///|
/// Feature: logging, Property 5: trace 内采样一致性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.3, 3.6**
test "Feature: logging, Property 5: trace-coherent sampling (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { st_coherent(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// 具体见证：同一 trace 的两条事件得到相同采样判定；边界 rate=0/1。
test "sample_trace is constant per trace (witness)" {
  let trace : TraceId = { value: 123456789L }
  let seed = 42UL
  let d = sample_trace(0.5, trace, seed)
  @test.assert_eq(sample_trace(0.5, trace, seed), d) // 同一 trace 恒定
  assert_false(sample_trace(0.0, trace, seed)) // 全弃
  assert_true(sample_trace(1.0, trace, seed)) // 全采
}
