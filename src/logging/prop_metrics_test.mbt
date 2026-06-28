// prop_metrics_test.mbt —— 指标派生确定性属性测试（任务 11.4）。
//
//   Feature: logging, Property 14: 指标派生确定性（metrics-determinism）
//   --------------------------------------------------------------------
//   *对任意* 事件流与边界集，对同一输入两次派生所得按级别计数与直方图逐桶相等；
//   且直方图仅计入该字段为数值取值（VInt/VFloat）的事件，跳过缺字段或字段非数值
//   的事件（被跳过事件不计入任何桶）。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 随机字段 "v"：可能为数值（VInt/VFloat，计入桶）、非数值（VStr/VBool/嵌套，跳过）
/// 或缺失（跳过）。返回 (event, 是否数值)。
fn mt_event(rng : @infra_pbt.Rng, i : Int) -> (Event, Bool) {
  match rng.next_below(5) {
    0 =>
      (
        Event::new(i.to_int64(), sh_level(rng), {
          "v": VInt(rng.next_range(-50, 50).to_int64()),
        }),
        true,
      )
    1 =>
      (
        Event::new(i.to_int64(), sh_level(rng), { "v": VFloat(sh_float(rng)) }),
        true,
      )
    2 => (Event::new(i.to_int64(), sh_level(rng), { "v": VStr("x") }), false) // 非数值
    3 => (Event::new(i.to_int64(), sh_level(rng), { "other": VInt(1L) }), false) // 缺字段
    _ =>
      (
        Event::new(i.to_int64(), sh_level(rng), { "v": VList([VInt(1L)]) }),
        false,
      ) // 嵌套非数值
  }
}

///|
/// 单次场景：随机事件流 + 升序边界，断言派生确定性与直方图跳过逻辑。
fn mt_determinism(rng : @infra_pbt.Rng) -> Bool {
  let n = rng.next_range(0, 25)
  let events : Array[Event] = []
  let mut numeric = 0
  for i in 0..<n {
    let (e, is_num) = mt_event(rng, i)
    events.push(e)
    if is_num {
      numeric = numeric + 1
    }
  }
  // 升序边界（累加正增量）。
  let nb = rng.next_range(0, 4)
  let boundaries : Array[Double] = []
  let mut acc = rng.next_range(-20, 0).to_double()
  for _i in 0..<nb {
    acc = acc + (1 + rng.next_below(10)).to_double()
    boundaries.push(acc)
  }
  // 两次派生逐项相等。
  let c1 = count_by_level(events)
  let c2 = count_by_level(events)
  if !(c1 == c2) {
    return false
  }
  let h1 = histogram(events, "v", boundaries)
  let h2 = histogram(events, "v", boundaries)
  if !(h1 == h2) {
    return false
  }
  // 直方图仅计入数值字段事件：桶计数之和 == 数值事件数。
  let mut bsum = 0
  for b in h1.buckets {
    bsum = bsum + b
  }
  if bsum != numeric {
    return false
  }
  // 桶数 = 边界数 + 1。
  if h1.buckets.length() != boundaries.length() + 1 {
    return false
  }
  true
}

///|
/// Feature: logging, Property 14: 指标派生确定性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 8.2, 8.3, 8.5**
test "Feature: logging, Property 14: metrics-determinism (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { mt_determinism(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
