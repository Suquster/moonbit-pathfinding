// metrics_test.mbt —— 直方图分桶与跳过逻辑单元测试（任务 11.5）。
//
// 覆盖 Requirement 8.3（缺字段 / 非数值事件不计入任何桶）与分桶具体见证。

///|
/// 直方图按升序边界分桶：boundaries=[10,20] ⇒ 3 桶 [<10, [10,20), >=20]。
test "histogram buckets values by ascending boundaries" {
  let events = [
    Event::new(0L, Level::Info, { "lat": VInt(5L) }), // 桶0 (<10)
    Event::new(1L, Level::Info, { "lat": VInt(10L) }), // 桶1 ([10,20))
    Event::new(2L, Level::Info, { "lat": VFloat(15.5) }), // 桶1
    Event::new(3L, Level::Info, { "lat": VInt(20L) }), // 桶2 (>=20)
    Event::new(4L, Level::Info, { "lat": VInt(99L) }), // 桶2
  ]
  let h = histogram(events, "lat", [10.0, 20.0])
  assert_eq(h.buckets.length(), 3)
  assert_eq(h.buckets[0], 1) // <10
  assert_eq(h.buckets[1], 2) // [10,20)
  assert_eq(h.buckets[2], 2) // >=20
}

///|
/// 缺目标字段或字段非数值（VStr/VBool/VMap/VList）的事件不计入任何桶。
test "histogram skips missing and non-numeric fields" {
  let events = [
    Event::new(0L, Level::Info, { "lat": VInt(5L) }), // 计入
    Event::new(1L, Level::Info, { "other": VInt(5L) }), // 缺 lat → 跳过
    Event::new(2L, Level::Info, { "lat": VStr("x") }), // 非数值 → 跳过
    Event::new(3L, Level::Info, { "lat": VBool(true) }), // 非数值 → 跳过
    Event::new(4L, Level::Info, { "lat": VMap({ "a": VInt(1L) }) }), // 嵌套 → 跳过
    Event::new(5L, Level::Info, { "lat": VFloat(50.0) }), // 计入
  ]
  let h = histogram(events, "lat", [10.0])
  // 仅 2 条数值事件计入：5.0 → 桶0，50.0 → 桶1。
  let mut sum = 0
  for b in h.buckets {
    sum = sum + b
  }
  assert_eq(sum, 2)
  assert_eq(h.buckets[0], 1) // <10
  assert_eq(h.buckets[1], 1) // >=10
}

///|
/// 空边界 ⇒ 单桶，计入全部数值事件。
test "histogram with no boundaries is a single bucket" {
  let events = [
    Event::new(0L, Level::Info, { "v": VInt(1L) }),
    Event::new(1L, Level::Info, { "v": VFloat(2.0) }),
    Event::new(2L, Level::Info, { "v": VStr("skip") }),
  ]
  let h = histogram(events, "v", [])
  assert_eq(h.buckets.length(), 1)
  assert_eq(h.buckets[0], 2)
}
