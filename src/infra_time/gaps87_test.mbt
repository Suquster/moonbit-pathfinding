// gaps87_test.mbt —— 时间/时区余臂（第八十七批）。

///|
/// DateTime 的 Show 输出即 ISO-8601 渲染。
test "DateTime Show：ISO-8601 渲染" {
  let dt : DateTime = {
    year: 2026,
    month: 7,
    day: 12,
    hour: 11,
    minute: 45,
    second: 0,
    millis: 0,
  }
  assert_eq("\{dt}", format_iso8601(dt))
}

///|
/// days_in_month：月份越界返回 0。
test "days_in_month：越界月份为 0" {
  assert_eq(days_in_month(2026, 0), 0)
  assert_eq(days_in_month(2026, 13), 0)
}

///|
/// parse_posix_tz：过渡规则段为空（连续点）→ None。
test "parse_posix_tz：过渡规则空段拒绝" {
  assert_true(parse_posix_tz("PST8PDT,M3..10,M11.1.0") is None)
}

///|
/// parse_posix_tz：过渡规则含非数字字符 → None。
test "parse_posix_tz：过渡规则非数字拒绝" {
  assert_true(parse_posix_tz("PST8PDT,M3.x.0,M11.1.0") is None)
}

///|
/// parse_posix_tz：过渡规则以点结尾（末段缺失）→ None。
test "parse_posix_tz：过渡规则点结尾拒绝" {
  assert_true(parse_posix_tz("PST8PDT,M11.2.,M11.1.0") is None)
}
