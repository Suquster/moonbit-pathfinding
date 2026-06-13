// logging_test.mbt —— Logging_Library（任务 10.2）的单元测试。
//
// 覆盖 10.2 的核心契约（确定性夹具，非属性测试——属性 Property 16/17/18 由
// 任务 10.3 / 10.4 承载）：
//   1. Level 严重程度序与阈值判定（is_enabled）；标签双射（label / from_label）；
//   2. Event 构造保真；
//   3. 级别阈值过滤（7.2）：低于阈值的事件被 log 丢弃；
//   4. 事件上下文标注（7.4）：激活 span 内事件携带 span / trace 标识；
//   5. span 树（7.3）：嵌套 enter_span 关联父 span；根 span 无父；
//   6. span 时长（7.5）：exit_span 后 span_duration 为正且等于 end - start；
//   7. 跨任务 trace 传播（7.6）：子任务保留父任务 trace 标识，span 正确挂接；
//   8. 结构化输出与往返（7.1 / 7.7）：format_json 产出结构化文本，
//      parse_json_log 可解析回等价事件。
//
// 每个触达全局运行时状态的用例均先 `reset_logger()` 以隔离用例间状态。

// ───────────────────────────── 级别 ──────────────────────────────────────

///|
/// 级别严重程度自低到高单调：Trace < Debug < Info < Warn < Error。
test "level rank is monotonic from trace to error" {
  assert_eq(Level::Trace.rank(), 0)
  assert_eq(Level::Debug.rank(), 1)
  assert_eq(Level::Info.rank(), 2)
  assert_eq(Level::Warn.rank(), 3)
  assert_eq(Level::Error.rank(), 4)
}

///|
/// is_enabled：严重程度不低于阈值即记录，低于阈值则丢弃（10.2 过滤原语）。
test "level is_enabled respects threshold" {
  assert_true(Level::Info.is_enabled(Level::Info))
  assert_true(Level::Warn.is_enabled(Level::Info))
  assert_true(Level::Error.is_enabled(Level::Info))
  assert_false(Level::Debug.is_enabled(Level::Info))
  assert_false(Level::Trace.is_enabled(Level::Info))
  assert_true(Level::Trace.is_enabled(Level::Trace))
}

///|
/// 级别标签 label / from_label 构成双射（支撑结构化输出往返）。
test "level label and from_label are inverse" {
  let levels = [
    Level::Trace,
    Level::Debug,
    Level::Info,
    Level::Warn,
    Level::Error,
  ]
  for i = 0; i < levels.length(); i = i + 1 {
    assert_eq(Level::from_label(levels[i].label()), Some(levels[i]))
  }
  assert_true(Level::from_label("NOPE") is None)
}

// ───────────────────────────── 事件 ──────────────────────────────────────

///|
/// Event 构造保真：时间戳、级别与字段集合原样保留。
test "event new preserves timestamp level and fields" {
  let fields : Map[String, Value] = { "msg": VStr("hi"), "n": VInt(7L) }
  let e = Event::new(42L, Level::Warn, fields)
  assert_eq(e.ts, 42L)
  assert_true(e.level == Level::Warn)
  assert_true(e.fields.get("msg") == Some(VStr("hi")))
  assert_true(e.fields.get("n") == Some(VInt(7L)))
}

// ─────────────────────────── 级别过滤（7.2） ──────────────────────────────

///|
/// 配置阈值 Info：低于阈值的 Trace / Debug 事件被丢弃，Info 及以上被记录。
test "log discards events below configured threshold" {
  reset_logger()
  set_threshold(Level::Info)
  log(Level::Trace, { "m": VStr("trace") })
  log(Level::Debug, { "m": VStr("debug") })
  log(Level::Info, { "m": VStr("info") })
  log(Level::Error, { "m": VStr("error") })
  let events = captured_events()
  // 仅 Info 与 Error 两条被保留。
  assert_eq(events.length(), 2)
  assert_true(events[0].level == Level::Info)
  assert_true(events[1].level == Level::Error)
}

///|
/// 默认阈值 Trace（reset 后）：所有级别均被记录，并带单调递增时间戳。
test "log records all levels at default threshold with monotonic timestamps" {
  reset_logger()
  log(Level::Trace, {})
  log(Level::Error, {})
  let events = captured_events()
  assert_eq(events.length(), 2)
  assert_true(events[0].ts < events[1].ts)
}

// ─────────────────────── 事件上下文标注（7.4） ────────────────────────────

///|
/// 在激活 span 内记录的事件携带该 span 的 span 标识与当前 trace 标识。
test "log annotates events with active span and trace context" {
  reset_logger()
  let trace = begin_trace()
  let s = enter_span("request")
  log(Level::Info, { "msg": VStr("inside") })
  exit_span(s)
  let events = captured_events()
  assert_eq(events.length(), 1)
  let e = events[0]
  assert_true(e.fields.get("span") == Some(VInt(s.id.value)))
  assert_true(e.fields.get("trace") == Some(VInt(trace.value)))
  // 调用方自身字段保留。
  assert_true(e.fields.get("msg") == Some(VStr("inside")))
}

///|
/// 无激活 span 时事件不带 span 字段（仍带 trace 字段）。
test "log without active span omits span field" {
  reset_logger()
  log(Level::Info, { "msg": VStr("top") })
  let e = captured_events()[0]
  assert_true(e.fields.get("span") is None)
  assert_true(e.fields.get("trace") is Some(_))
}

// ───────────────────────────── span 树（7.3） ─────────────────────────────

///|
/// 根 span 无父；其内的嵌套 span 关联父 span，形成 span 树；id 唯一。
test "enter_span builds a span tree with parent links" {
  reset_logger()
  let root = enter_span("root")
  let child = enter_span("child")
  // 根无父；子的父为根。
  assert_true(root.parent is None)
  assert_true(child.parent == Some(root.id))
  // id 唯一。
  assert_false(root.id == child.id)
  // 退出顺序 LIFO。
  exit_span(child)
  exit_span(root)
}

///|
/// 退出内层 span 后，再进入的兄弟 span 重新挂接到外层 span 之下。
test "sibling spans reattach to the enclosing parent" {
  reset_logger()
  let root = enter_span("root")
  let a = enter_span("a")
  exit_span(a)
  let b = enter_span("b")
  assert_true(a.parent == Some(root.id))
  assert_true(b.parent == Some(root.id))
  exit_span(b)
  exit_span(root)
}

// ─────────────────────────── span 时长（7.5） ─────────────────────────────

///|
/// exit_span 后该 span 被记入已结束集合，且时长为 end - start（> 0）。
test "exit_span records positive duration" {
  reset_logger()
  let s = enter_span("work")
  log(Level::Info, { "m": VStr("step") })
  exit_span(s)
  let finished = finished_spans()
  assert_eq(finished.length(), 1)
  let fs = finished[0]
  assert_true(fs.id == s.id)
  match span_duration(fs) {
    Some(d) => assert_true(d > 0L)
    None => fail("expected a recorded duration")
  }
}

// ─────────────────────── 跨任务 trace 传播（7.6） ──────────────────────────

///|
/// 子任务上下文保留父任务 trace 标识；with_context 内事件归属父 trace，
/// 子任务 span 挂接父任务激活 span；退出后父任务状态原样还原。
test "with_context propagates parent trace id across task boundary" {
  reset_logger()
  let parent_trace = begin_trace()
  let parent_span = enter_span("parent")
  let ctx = child_context(capture_context())
  // 子上下文保留父 trace 标识（Requirement 7.6 核心不变量）。
  assert_true(ctx.trace == parent_trace)
  with_context(ctx, fn() {
    // 子任务内事件应归属父 trace，并以父 span 为逻辑父。
    log(Level::Info, { "m": VStr("child-work") })
    let child_span = enter_span("child-task")
    exit_span(child_span)
  })
  // 子任务 span 应挂接到父任务激活 span 之下。
  let child = finished_spans()[0]
  assert_true(child.parent == Some(parent_span.id))
  // 还原后父任务仍在 parent_span 内，trace 不变。
  assert_true(current_trace() == parent_trace)
  assert_true(current_span() == Some(parent_span.id))
  exit_span(parent_span)
  // 校验子任务事件确实带父 trace 标识。
  let events = captured_events()
  assert_eq(events.length(), 1)
  assert_true(events[0].fields.get("trace") == Some(VInt(parent_trace.value)))
}

// ─────────────────── 结构化输出与往返（7.1 / 7.7） ─────────────────────────

///|
/// format_json 产出含时间戳、级别标签与字段（含 span / trace）的结构化文本。
test "format_json emits level and fields" {
  let e = Event::new(1L, Level::Info, { "msg": VStr("hello") })
  let json = format_json(e)
  assert_true(json.contains("\"level\":\"INFO\""))
  assert_true(json.contains("\"ts\":1"))
  assert_true(json.contains("\"msg\":\"hello\""))
}

///|
/// format_json 对双引号等字符做转义。
test "format_json escapes quotes in string values" {
  let e = Event::new(0L, Level::Debug, { "q": VStr("a\"b") })
  let json = format_json(e)
  assert_true(json.contains("\"q\":\"a\\\"b\""))
}

///|
/// 序列化再解析往返：解析结果与原事件逐字段一致（含多种字段取值类型）。
test "parse_json_log round-trips format_json output" {
  let fields : Map[String, Value] = {
    "msg": VStr("hello world"),
    "count": VInt(42L),
    "ok": VBool(true),
    "ratio": VFloat(0.5),
  }
  let e = Event::new(123L, Level::Warn, fields)
  let json = format_json(e)
  match parse_json_log(json) {
    Some(parsed) => {
      assert_eq(parsed.ts, e.ts)
      assert_true(parsed.level == e.level)
      assert_true(parsed.fields.get("msg") == Some(VStr("hello world")))
      assert_true(parsed.fields.get("count") == Some(VInt(42L)))
      assert_true(parsed.fields.get("ok") == Some(VBool(true)))
      assert_true(parsed.fields.get("ratio") == Some(VFloat(0.5)))
    }
    None => fail("expected parse_json_log to succeed on format_json output")
  }
}

///|
/// 往返保留转义字符（双引号、换行、制表符）。
test "parse_json_log round-trips escaped characters" {
  let e = Event::new(7L, Level::Error, { "raw": VStr("a\"b\\c\nd\te") })
  match parse_json_log(format_json(e)) {
    Some(parsed) =>
      assert_true(parsed.fields.get("raw") == Some(VStr("a\"b\\c\nd\te")))
    None => fail("expected round-trip on escaped characters")
  }
}

///|
/// 非法 JSON 返回 None，不构造部分事件。
test "parse_json_log returns none on malformed input" {
  assert_true(parse_json_log("{") is None)
  assert_true(parse_json_log("not json") is None)
  assert_true(parse_json_log("{\"ts\":1}") is None) // 缺 level / fields
  assert_true(
    parse_json_log("{\"ts\":\"x\",\"level\":\"INFO\",\"fields\":{}}") is None,
  ) // ts 类型错误
  assert_true(
    parse_json_log("{\"ts\":1,\"level\":\"NOPE\",\"fields\":{}}") is None,
  ) // 未知级别
}
