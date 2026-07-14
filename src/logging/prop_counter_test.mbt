// prop_counter_test.mbt —— 计数守恒属性测试（任务 11.2）。
//
//   Feature: logging, Property 13: 计数守恒（counter-conservation）
//   --------------------------------------------------------------------
//   *对任意* 事件流，按级别派生的各级别计数均为非负，且各级别计数之和等于输入
//   事件总数：sum(count_by_level(events)) == len(events)。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 随机级别事件流生成器（长度 0~30）。
fn ct_events() -> @infra_pbt.Gen[Array[Event]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 30)
    let out : Array[Event] = []
    for i in 0..<n {
      out.push(Event::new(i.to_int64(), sh_level(rng), Map([])))
    }
    out
  })
}

///|
/// Feature: logging, Property 13: 计数守恒（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 8.1, 8.4**
test "Feature: logging, Property 13: counter-conservation (holds_for_all)" {
  let ok = @infra_pbt.holds_for_all(ct_events(), fn(events) {
    let counts = count_by_level(events)
    // 长度恒为 5。
    if counts.length() != 5 {
      return false
    }
    let mut sum = 0
    for c in counts {
      if c < 0 {
        return false
      }
      sum = sum + c
    }
    sum == events.length()
  })
  assert_true(ok)
}

///|
/// 具体见证：按级别计数与 level_count 取值。
test "count_by_level conserves total (witness)" {
  let events = [
    Event::new(0L, Level::Info, Map([])),
    Event::new(1L, Level::Info, Map([])),
    Event::new(2L, Level::Error, Map([])),
    Event::new(3L, Level::Trace, Map([])),
  ]
  let counts = count_by_level(events)
  @test.assert_eq(level_count(counts, Level::Info), 2)
  @test.assert_eq(level_count(counts, Level::Error), 1)
  @test.assert_eq(level_count(counts, Level::Trace), 1)
  @test.assert_eq(level_count(counts, Level::Debug), 0)
  @test.assert_eq(level_count(counts, Level::Warn), 0)
}
