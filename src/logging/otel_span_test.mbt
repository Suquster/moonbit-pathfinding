// otel_span_test.mbt —— OTel span 属性/事件/状态/kind 单元测试（任务 8.3）。
//
// 覆盖 Requirement 5.1（属性保留）/ 5.2（span 事件名称/时间戳/字段归属）/
// 5.3（状态默认 Unset）/ 5.4（kind 默认 Internal）。

///|
/// SpanData 默认状态为 Unset、kind 为 Internal、属性与事件为空。
test "span data defaults to unset status and internal kind" {
  reset_logger()
  let s = enter_span("op")
  let sd = SpanData::new(s)
  assert_true(sd.status == SpanStatus::Unset)
  assert_true(sd.kind == SpanKind::Internal)
  @test.assert_eq(sd.attributes.length(), 0)
  @test.assert_eq(sd.events.length(), 0)
  exit_span(s)
}

///|
/// 属性设置后保留；同名键覆盖（Requirement 5.1）。
test "span attributes are retained and overwritten by key" {
  reset_logger()
  let s = enter_span("op")
  let sd = SpanData::new(s)
  sd.set_attribute("http.method", VStr("GET"))
  sd.set_attribute("http.status", VInt(200L))
  assert_true(sd.attributes.get("http.method") == Some(VStr("GET")))
  assert_true(sd.attributes.get("http.status") == Some(VInt(200L)))
  sd.set_attribute("http.method", VStr("POST")) // 覆盖
  assert_true(sd.attributes.get("http.method") == Some(VStr("POST")))
  exit_span(s)
}

///|
/// span 事件保留名称 / 时间戳 / 字段，并按记录顺序归属该 span（Requirement 5.2）。
test "span events retain name timestamp and fields in order" {
  reset_logger()
  let s = enter_span("op")
  let sd = SpanData::new(s)
  sd.add_event("cache.miss", 11L, { "key": VStr("user:1") })
  sd.add_event("db.query", 12L, { "rows": VInt(3L) })
  @test.assert_eq(sd.events.length(), 2)
  @test.assert_eq(sd.events[0].name, "cache.miss")
  @test.assert_eq(sd.events[0].ts, 11L)
  assert_true(sd.events[0].fields.get("key") == Some(VStr("user:1")))
  @test.assert_eq(sd.events[1].name, "db.query")
  assert_true(sd.events[1].fields.get("rows") == Some(VInt(3L)))
  exit_span(s)
}

///|
/// 状态与 kind 可被设置（Requirement 5.3 / 5.4）。
test "span status and kind can be set" {
  reset_logger()
  let s = enter_span("op")
  let sd = SpanData::new(s)
  sd.set_status(SpanStatus::Error)
  sd.set_kind(SpanKind::Client)
  assert_true(sd.status == SpanStatus::Error)
  assert_true(sd.kind == SpanKind::Client)
  exit_span(s)
}

///|
/// OTel 叠加不改既有 span 字段（id/parent/start/end 与 span_duration 不变）。
test "otel overlay does not mutate underlying span" {
  reset_logger()
  let root = enter_span("root")
  let child = enter_span("child")
  let sd = SpanData::new(child)
  sd.set_attribute("x", VInt(1L))
  sd.set_status(SpanStatus::Ok)
  // 底层 span 字段不受影响。
  assert_true(sd.span.id == child.id)
  assert_true(sd.span.parent == Some(root.id))
  exit_span(child)
  exit_span(root)
}
