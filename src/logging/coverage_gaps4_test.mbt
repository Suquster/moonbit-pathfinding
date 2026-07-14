// 黑盒测试：覆盖率审计收口（INFRA 第七十七批）——
// logfmt 值解析失败/整数溢出/值后粘连；JSON 日志的值缺失、
// 键未闭合与 \u 转义截断。

///|
test "parse_logfmt：坏值 token/整数溢出/值后粘连字符均拒绝" {
  assert_true(@logging.parse_logfmt("ts=1 level=info k=}") is None)
  assert_true(
    @logging.parse_logfmt("ts=1 level=info k=99999999999999999999999") is None,
  )
  assert_true(@logging.parse_logfmt("ts=1 level=info k=1x") is None)
}

///|
test "SinkHandle::console：级别过滤、直写与无缓冲 flush" {
  let sink = @logging.SinkHandle::console(
    @logging.Formatter::Logfmt,
    level=@logging.Level::Warn,
  )
  // 低于阈值：不写出。
  sink.emit(@logging.Event::new(0L, @logging.Level::Debug, Map([])))
  // 达到阈值：渲染并写标准输出（控制台 sink 的直写路径）。
  sink.emit(@logging.Event::new(1L, @logging.Level::Error, Map([])))
  // 控制台无缓冲，flush 为空操作。
  sink.flush()
}

///|
test "parse_json_log：值缺失/键未闭合/\\u 截断均拒绝" {
  assert_true(@logging.parse_json_log("{\"a\":") is None)
  assert_true(@logging.parse_json_log("{\"a") is None)
  assert_true(@logging.parse_json_log("{\"a\":\"\\u1") is None)
}
