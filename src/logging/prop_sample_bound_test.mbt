// prop_sample_bound_test.mbt —— 采样比例有界属性测试（任务 5.4）。
//
//   Feature: logging, Property 6: 采样比例有界（sampling-ratio bound）
//   --------------------------------------------------------------------
//   *对任意* 采样率 rate ∈ [0,1] 与事件流 events，系统采样后被保留事件占比
//   不超过采样率所允许的上界：
//     len(sample_stream(rate, events, rng)) <= retained_count(rate, n)
//     且 retained_count(rate, n) <= ceil(rate * n)；
//   边界 rate=0 保留 0、rate=1 保留全部。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 构造 n 条占位事件（内容与采样判定无关）。
fn sb_events(n : Int) -> Array[Event] {
  let out : Array[Event] = []
  for i in 0..<n {
    out.push(Event::new(i.to_int64(), Level::Info, { "i": VInt(i.to_int64()) }))
  }
  out
}

///|
/// ceil(rate * n)（rate >= 0, n >= 0）。
fn sb_ceil(rate : Double, n : Int) -> Int {
  (rate * n.to_double()).ceil().to_int()
}

///|
/// 单次场景：随机 rate / n，断言保留条数 <= retained_count <= ceil(rate*n)，
/// 且 rate=0 全弃、rate=1 全采。
fn sb_bound(rng : @infra_pbt.Rng) -> Bool {
  let rate = rng.next_range(0, 100).to_double() / 100.0
  let n = rng.next_range(0, 30)
  let events = sb_events(n)
  let kept = sample_stream(rate, events, @infra_pbt.rng_new(rng.next()))
  let rc = retained_count(rate, n)
  // 保留条数恰为 retained_count，且 retained_count <= ceil(rate*n)。
  if kept.length() > rc {
    return false
  }
  if rc > sb_ceil(rate, n) {
    return false
  }
  // 边界。
  if sample_stream(0.0, events, @infra_pbt.rng_new(1UL)).length() != 0 {
    return false
  }
  if sample_stream(1.0, events, @infra_pbt.rng_new(1UL)).length() != n {
    return false
  }
  true
}

///|
/// Feature: logging, Property 6: 采样比例有界（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.1, 3.2, 3.7**
test "Feature: logging, Property 6: sampling-ratio bound (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { sb_bound(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// 具体见证：rate=0.5 over 10 事件保留 5 条；rate=0/1 边界。
test "sample_stream retained count witnesses" {
  let events = sb_events(10)
  @test.assert_eq(retained_count(0.5, 10), 5)
  @test.assert_eq(
    sample_stream(0.5, events, @infra_pbt.rng_new(7UL)).length(),
    5,
  )
  @test.assert_eq(
    sample_stream(0.0, events, @infra_pbt.rng_new(7UL)).length(),
    0,
  )
  @test.assert_eq(
    sample_stream(1.0, events, @infra_pbt.rng_new(7UL)).length(),
    10,
  )
}
