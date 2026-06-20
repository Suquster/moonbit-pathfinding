// logging_textbuilder_equiv_test.mbt —— TextBuilder 改造等价性测试（任务 12.5）。
//
// 设计依据：production-hardening/design.md §「Shared_Text_Builder 设计 / 替换策略」
// （Requirement 1.5 / 1.6）。本文件为「将 logging 方向中循环内 `out = out + ...`
// 字符串拼接改用 @infra_text.TextBuilder」的改造提供等价性守护：
//
//   * 黄金值断言：对代表性事件断言格式化器（format_json / format_logfmt /
//     format_pretty）的输出与改造前逐字符相等（以独立的字面量期望值固化）；
//   * 往返验证：parse_json_log(format_json(e)) == e 与 parse_logfmt(format_logfmt(e))
//     == e，覆盖被改造的解析器内部累加（parse_string / parse_num / logfmt 键读取
//     与裸 token 读取）；
//   * 旁路解析器（trace_context 的 hex16 / extract_traceparent / low16_chars、
//     filter 的 parse_env_filter / parse_level_ci / substr_chars）的等价往返。
//
// 这些断言不依赖被改造函数的内部实现，仅观测其公开行为，从而独立地保证
// 「改造后输出逐字符不变」（AC5）。既有测试文件不被修改（AC：禁止改既有测试）。

// ─────────────────────── 格式化器：黄金值等价 ───────────────────────

///|
/// format_json 对标量字段事件产出与改造前逐字符相等的黄金值。
test "format_json scalar golden equals pre-refactor output" {
  let e = Event::new(1L, Level::Info, { "a": VStr("x"), "b": VInt(42) })
  // 字段按键名升序：a, b。
  assert_eq(
    format_json(e),
    "{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"a\":\"x\",\"b\":42}}",
  )
}

///|
/// format_json 对含转义字符的字符串取值产出正确的转义黄金值（覆盖 json_escape
/// 循环改造）。
test "format_json escapes golden equals pre-refactor output" {
  let e = Event::new(2L, Level::Warn, { "msg": VStr("a\"b\nc\td\\e") })
  assert_eq(
    format_json(e),
    "{\"ts\":2,\"level\":\"WARN\",\"fields\":{\"msg\":\"a\\\"b\\nc\\td\\\\e\"}}",
  )
}

///|
/// format_json 对嵌套 VMap / VList 产出正确的黄金值（覆盖 value_to_json 的
/// VMap / VList 循环改造，成员升序、元素原序）。
test "format_json nested golden equals pre-refactor output" {
  let e = Event::new(3L, Level::Error, {
    "obj": VMap({ "y": VInt(1), "x": VInt(2) }),
    "arr": VList([VInt(1), VStr("a"), VBool(true)]),
  })
  // 顶层字段升序：arr, obj；obj 成员升序：x, y。
  assert_eq(
    format_json(e),
    "{\"ts\":3,\"level\":\"ERROR\",\"fields\":{\"arr\":[1,\"a\",true],\"obj\":{\"x\":2,\"y\":1}}}",
  )
}

///|
/// format_logfmt 对标量字段事件产出与改造前逐字符相等的黄金值。
test "format_logfmt scalar golden equals pre-refactor output" {
  let e = Event::new(7L, Level::Debug, { "k": VStr("v"), "n": VInt(5) })
  assert_eq(format_logfmt(e), "ts=7 level=DEBUG k=\"v\" n=5")
}

///|
/// format_pretty 对标量字段事件产出与改造前逐字符相等的黄金值（字符串取值
/// 不带引号、字段升序）。
test "format_pretty scalar golden equals pre-refactor output" {
  let e = Event::new(9L, Level::Trace, {
    "b": VBool(false),
    "a": VStr("hi"),
    "c": VFloat(0.5),
  })
  // 字段升序：a, b, c。
  assert_eq(format_pretty(e), "ts=9 [TRACE] a=hi b=false c=0.5")
}

// ─────────────────────── 格式化器 + 解析器：往返等价 ───────────────────────

///|
/// JSON 往返：format_json → parse_json_log 还原等价事件，覆盖被改造的
/// parse_string（含转义还原）与 parse_num（数值文本累加）。
test "format_json then parse_json_log roundtrips after refactor" {
  let events = [
    Event::new(0L, Level::Trace, {}),
    Event::new(123L, Level::Info, { "s": VStr("hello world"), "i": VInt(-7) }),
    Event::new(456L, Level::Warn, {
      "esc": VStr("tab\tnl\nquote\"back\\slash"),
      "f": VFloat(3.5),
      "ok": VBool(true),
    }),
    Event::new(789L, Level::Error, {
      "nested": VMap({ "inner": VList([VInt(1), VInt(2)]), "name": VStr("z") }),
    }),
  ]
  for e in events {
    let text = format_json(e)
    assert_true(parse_json_log(text) == Some(e))
  }
}

///|
/// logfmt 往返：format_logfmt → parse_logfmt 还原等价事件，覆盖被改造的
/// logfmt 键读取（key 累加）与裸 token 读取（logfmt_read_bare）。
test "format_logfmt then parse_logfmt roundtrips after refactor" {
  let events = [
    Event::new(1L, Level::Info, { "k": VStr("v") }),
    Event::new(2L, Level::Warn, {
      "spaced": VStr("a b"),
      "eq": VStr("x=y"),
      "n": VInt(99),
    }),
    Event::new(3L, Level::Debug, { "f": VFloat(1.25), "ok": VBool(false) }),
  ]
  for e in events {
    let line = format_logfmt(e)
    assert_true(parse_logfmt(line) == Some(e))
  }
}

// ─────────────────────── trace_context：成帧与往返等价 ───────────────────────

///|
/// inject_traceparent 黄金值（覆盖 hex16 的循环改造）：内部 64 位标识编码进
/// trace-id 低 64 位、高位补 0；flags 固定 01。
test "inject_traceparent golden equals pre-refactor output" {
  let ctx : TraceContext = {
    trace: ({ value: 0x0123456789abcdefL } : TraceId),
    span: Some({ value: 0x00000000000000ffL }),
  }
  assert_eq(
    inject_traceparent(ctx),
    "00-00000000000000000123456789abcdef-00000000000000ff-01",
  )
}

///|
/// traceparent 往返：inject → extract 还原十六进制分量（覆盖 extract_traceparent
/// 的 '-' 切分累加与 low16_chars）。
test "inject then extract traceparent roundtrips after refactor" {
  let ctx : TraceContext = {
    trace: ({ value: 0x00000000deadbeefL } : TraceId),
    span: Some({ value: 0x0000000000001234L }),
  }
  let tp = inject_traceparent(ctx)
  match extract_traceparent(tp) {
    Some(w) => {
      assert_eq(w.trace_id, "000000000000000000000000deadbeef")
      assert_eq(w.span_id, "0000000000001234")
      assert_eq(w.flags, 1)
      // 桥接回内部 TraceContext，低 64 位无损还原。
      let back = w.to_trace_context()
      assert_eq(back.trace.value, 0x00000000deadbeefL)
    }
    None => abort_unreachable()
  }
}

///|
/// 测试内辅助：标记不可达分支（不作为生产占位，仅用于断言失败定位）。
/// 声明 `raise` 以便在测试中传播断言错误。
fn abort_unreachable() -> Unit raise {
  assert_true(false)
}

// ─────────────────────── filter：解析等价 ───────────────────────

///|
/// parse_env_filter 解析含多段指令的 spec（覆盖逗号切分累加 cur、substr_chars
/// 与 parse_level_ci 的大小写归一循环）。
test "parse_env_filter parses directives after refactor" {
  match parse_env_filter("net=debug,db=warn,info") {
    Ok(f) => {
      // target 命中用其阈值。
      assert_true(f.threshold_for("net") == Level::Debug)
      assert_true(f.threshold_for("db") == Level::Warn)
      // 裸 level 作为全局兜底。
      assert_true(f.threshold_for("unknown") == Level::Info)
    }
    Err(_) => abort_unreachable()
  }
}

///|
/// parse_env_filter 对非法级别标签返回带定位的错误（不产生部分构造）。
test "parse_env_filter reports error on invalid level after refactor" {
  match parse_env_filter("net=nope") {
    Ok(_) => abort_unreachable()
    Err(e) => assert_true(e.message.contains("unrecognized level label"))
  }
}
