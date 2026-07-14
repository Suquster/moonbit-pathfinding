// formatter_test.mbt —— logfmt 转义与多 sink 交付单元测试（任务 4.5）。
//
// 覆盖 Requirement 2.3（logfmt 引号/转义边界）与 2.5（多 sink 多格式交付、
// 路由匹配/不匹配）。

///|
/// logfmt 对含空格 / 等号 / 引号 / 控制字符的字符串取值施加引号与转义，并往返。
test "logfmt quotes and escapes special-character values" {
  let e = Event::new(1L, Level::Info, {
    "spaced": VStr("a b"),
    "eq": VStr("x=y"),
    "quote": VStr("a\"b"),
    "ctrl": VStr("a\nb"),
  })
  let line = format_logfmt(e)
  // 含空格 / 等号 / 引号的取值被双引号包裹（值 token 以 '"' 起始）。
  assert_true(line.contains("spaced=\"a b\""))
  assert_true(line.contains("eq=\"x=y\""))
  // 引号被转义。
  assert_true(line.contains("quote=\"a\\\"b\""))
  // 控制字符换行被转义为 \n。
  assert_true(line.contains("ctrl=\"a\\nb\""))
  // 往返还原。
  assert_true(parse_logfmt(line) == Some(e))
}

///|
/// 多 sink 多格式交付：同一事件经 dispatch 落地到 JSON 与 logfmt 两个 sink。
test "dispatch delivers one event to multiple sinks in multiple formats" {
  let json_sink = Sink::new("json", Formatter::Json)
  let logfmt_sink = Sink::new("logfmt", Formatter::Logfmt)
  let sinks = [json_sink, logfmt_sink]
  let e = Event::new(2L, Level::Warn, { "k": VStr("v") })
  dispatch(sinks, e)
  @test.assert_eq(json_sink.buffer.length(), 1)
  @test.assert_eq(logfmt_sink.buffer.length(), 1)
  @test.assert_eq(json_sink.buffer[0], format_json(e))
  @test.assert_eq(logfmt_sink.buffer[0], format_logfmt(e))
}

///|
/// 路由谓词匹配 / 不匹配：仅级别 >= Warn 的事件交付给告警 sink。
test "dispatch respects per-sink route predicate" {
  let warn_only = Sink::new("warn", Formatter::Json, route=fn(e) {
    e.level.rank() >= Level::Warn.rank()
  })
  let all_sink = Sink::new("all", Formatter::Json)
  let sinks = [warn_only, all_sink]
  dispatch(sinks, Event::new(1L, Level::Info, Map([]))) // Info: 仅 all 接收
  dispatch(sinks, Event::new(2L, Level::Error, Map([]))) // Error: 两者均接收
  @test.assert_eq(warn_only.buffer.length(), 1) // 仅 Error
  @test.assert_eq(all_sink.buffer.length(), 2) // Info + Error
}

///|
/// route 返回路由匹配的全部 sink 名称；无匹配返回空数组（Requirement 4.5）。
test "route returns matching sink names and empty on no match" {
  let a = Sink::new("a", Formatter::Json, route=fn(e) {
    e.level.rank() >= Level::Error.rank()
  })
  let b = Sink::new("b", Formatter::Logfmt) // 恒真
  let sinks = [a, b]
  // Error 事件匹配 a 与 b。
  let matched = route(sinks, Event::new(1L, Level::Error, Map([])))
  @test.assert_eq(matched.length(), 2)
  @test.assert_eq(matched[0], "a")
  @test.assert_eq(matched[1], "b")
  // Info 事件仅匹配 b（恒真）。
  let matched2 = route(sinks, Event::new(2L, Level::Info, Map([])))
  @test.assert_eq(matched2.length(), 1)
  @test.assert_eq(matched2[0], "b")
}
