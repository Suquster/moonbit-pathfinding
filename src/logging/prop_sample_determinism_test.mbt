// prop_sample_determinism_test.mbt —— 采样确定性与可重放属性测试（任务 5.5）。
//
//   Feature: logging, Property 7: 采样确定性与可重放（sampling determinism）
//   --------------------------------------------------------------------
//   *对任意* 采样率、种子与事件流，以相同采样配置与相同 Rng 种子两次重放同一
//   序列，产出逐条相同的采样判定结果（保留 / 丢弃序列逐元素相等）。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 构造 n 条带唯一序号的占位事件。
fn sd_events(n : Int) -> Array[Event] {
  let out : Array[Event] = []
  for i in 0..<n {
    out.push(Event::new(i.to_int64(), Level::Info, { "i": VInt(i.to_int64()) }))
  }
  out
}

///|
/// 单次场景：相同 rate + 相同种子两次运行 sample_stream，结果逐条相等。
fn sd_replay(rng : @infra_pbt.Rng) -> Bool {
  let rate = rng.next_range(0, 100).to_double() / 100.0
  let n = rng.next_range(0, 30)
  let events = sd_events(n)
  let seed = rng.next()
  let run1 = sample_stream(rate, events, @infra_pbt.rng_new(seed))
  let run2 = sample_stream(rate, events, @infra_pbt.rng_new(seed))
  if run1.length() != run2.length() {
    return false
  }
  for i in 0..<run1.length() {
    if !(run1[i] == run2[i]) {
      return false
    }
  }
  true
}

///|
/// Feature: logging, Property 7: 采样确定性与可重放（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.1, 3.4**
test "Feature: logging, Property 7: sampling determinism (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { sd_replay(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// 具体见证：同种子两次重放得到逐条相同的保留序列。
test "sample_stream replays identically under same seed (witness)" {
  let events = sd_events(13)
  let r1 = sample_stream(0.4, events, @infra_pbt.rng_new(99UL))
  let r2 = sample_stream(0.4, events, @infra_pbt.rng_new(99UL))
  assert_eq(r1.length(), r2.length())
  for i in 0..<r1.length() {
    assert_true(r1[i] == r2[i])
  }
}
