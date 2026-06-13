// prop_formatter_test.mbt —— 格式器确定性属性测试（任务 4.4）。
//
//   Feature: logging, Property 4: 格式器确定性（formatter determinism）
//   --------------------------------------------------------------------
//   *对任意* 事件 e 与任一格式器 fmt ∈ {Json, Logfmt, Pretty}，两次渲染产出
//   逐字节相同文本：`format_event(fmt, e) == format_event(fmt, e)`，即渲染由
//   事件内容唯一确定（三后端逐字节一致）。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。生成器 `sh_nested_event`。

///|
/// Feature: logging, Property 4: 格式器确定性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 2.2**
test "Feature: logging, Property 4: formatter determinism (holds_for_all)" {
  let ok = @infra_pbt.holds_for_all(sh_nested_event(), fn(e) {
    format_event(Formatter::Json, e) == format_event(Formatter::Json, e) &&
    format_event(Formatter::Logfmt, e) == format_event(Formatter::Logfmt, e) &&
    format_event(Formatter::Pretty, e) == format_event(Formatter::Pretty, e)
  })
  assert_true(ok)
}

///|
/// 三种格式器对同一事件产出各自确定的文本（具体见证）。
test "format_event is deterministic per formatter (witness)" {
  let e = Event::new(5L, Level::Info, { "svc": VStr("api"), "n": VInt(7L) })
  let j1 = format_event(Formatter::Json, e)
  let j2 = format_event(Formatter::Json, e)
  assert_eq(j1, j2)
  assert_eq(j1, format_json(e))
  let l1 = format_event(Formatter::Logfmt, e)
  assert_eq(l1, format_logfmt(e))
  let p1 = format_event(Formatter::Pretty, e)
  let p2 = format_event(Formatter::Pretty, e)
  assert_eq(p1, p2)
  // pretty 含级别标签与字段（不带引号）。
  assert_true(p1.contains("[INFO]"))
  assert_true(p1.contains("svc=api"))
}
