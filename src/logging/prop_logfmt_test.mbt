// prop_logfmt_test.mbt —— logfmt 往返属性测试（任务 4.2）。
//
//   Feature: logging, Property 3: logfmt 往返（logfmt round-trip）
//   --------------------------------------------------------------------
//   *对任意* 仅含标量字段的事件 e，`parse_logfmt(format_logfmt(e)) == Some(e)`。
//   统摄 `key=value` 空格分隔结构、含特殊字符取值的引号与转义编解码保真。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。生成器 `sh_scalar_event`。

///|
/// Feature: logging, Property 3: logfmt 往返（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 2.3, 2.6, 2.7**
test "Feature: logging, Property 3: logfmt round-trip (holds_for_all)" {
  let ok = @infra_pbt.holds_for_all(sh_scalar_event(), fn(e) {
    parse_logfmt(format_logfmt(e)) == Some(e)
  })
  assert_true(ok)
}

///|
/// logfmt 往返具体见证：含空格 / 引号 / 控制字符的字符串、整数、浮点、布尔
/// 全部往返还原。
test "logfmt round-trips representative scalar events (witness)" {
  let samples : Array[Event] = [
    Event::new(1L, Level::Info, {
      "msg": VStr("hello world"),
      "count": VInt(42L),
      "ok": VBool(true),
      "ratio": VFloat(0.5),
    }),
    Event::new(-3L, Level::Error, { "raw": VStr("a\"b\\c\nd\te=f g") }),
    Event::new(0L, Level::Trace, Map([])),
  ]
  for e in samples {
    match parse_logfmt(format_logfmt(e)) {
      Some(out) => assert_true(out == e)
      None => fail("logfmt 往返不应失败")
    }
  }
}
