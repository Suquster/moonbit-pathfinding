// time_ext_test.mbt —— Duration / 日历运算 / ISO 周历 / RFC 3339 偏移测试。

///|
fn dt(y : Int, mo : Int, d : Int, h : Int, mi : Int, s : Int) -> DateTime {
  { year: y, month: mo, day: d, hour: h, minute: mi, second: s, millis: 0 }
}

///|
/// Duration 构造 / 运算 / 分量读数 / 字符串。
test "duration arithmetic and formatting" {
  let d = Duration::of_days(1L)
    .add(Duration::of_hours(2L))
    .add(Duration::of_minutes(3L))
    .add(Duration::of_seconds(4L))
    .add(Duration::of_millis(500L))
  assert_true(d.to_string() == "1d2h3m4.500s")
  assert_true(d.total_hours() == 26L)
  assert_true(d.neg().to_string() == "-1d2h3m4.500s")
  assert_true(d.neg().abs() == d)
  assert_true(Duration::of_millis(0L).to_string() == "0s")
  assert_true(Duration::of_minutes(90L).to_string() == "1h30m")
  assert_true(d.sub(d).millis == 0L)
}

///|
/// since / add_duration 毫秒精度互逆（含负跨度与跨日借位）。
test "datetime since and add_duration roundtrip" {
  let a = dt(2026, 7, 7, 15, 30, 0)
  let b = dt(2026, 7, 8, 16, 31, 1)
  let gap = b.since(a)
  assert_true(gap.to_string() == "1d1h1m1s")
  assert_true(a.add_duration(gap) == b)
  assert_true(b.add_duration(gap.neg()) == a)
  // 毫秒借位：00:00:00.000 - 1ms → 前一天 23:59:59.999。
  let midnight = dt(2026, 1, 1, 0, 0, 0)
  let before = midnight.add_duration(Duration::of_millis(-1L))
  assert_true(
    before ==
    {
      year: 2025,
      month: 12,
      day: 31,
      hour: 23,
      minute: 59,
      second: 59,
      millis: 999,
    },
  )
}

///|
/// 比较全序与 is_before / is_after。
test "datetime comparison" {
  let a = dt(2026, 7, 7, 0, 0, 0)
  let b = dt(2026, 7, 7, 0, 0, 1)
  assert_true(a.is_before(b) && b.is_after(a))
  assert_true(a.compare_to(a) == 0)
}

///|
/// 加月 clamp 语义（对标 java.time plusMonths）与负增量、跨年。
test "add_months clamps to month end" {
  assert_true(
    dt(2026, 1, 31, 0, 0, 0).add_months(1) == dt(2026, 2, 28, 0, 0, 0),
  )
  assert_true(
    dt(2024, 1, 31, 0, 0, 0).add_months(1) == dt(2024, 2, 29, 0, 0, 0),
  ) // 闰年
  assert_true(
    dt(2026, 3, 31, 0, 0, 0).add_months(-1) == dt(2026, 2, 28, 0, 0, 0),
  )
  assert_true(
    dt(2026, 11, 30, 0, 0, 0).add_months(3) == dt(2027, 2, 28, 0, 0, 0),
  )
  // 闰日加年 clamp。
  assert_true(dt(2024, 2, 29, 0, 0, 0).add_years(1) == dt(2025, 2, 28, 0, 0, 0))
}

///|
/// 序数日期双射：day_of_year 与 date_from_day_of_year 互逆。
test "day_of_year bijection" {
  assert_true(dt(2026, 1, 1, 0, 0, 0).day_of_year() == 1)
  assert_true(dt(2026, 12, 31, 0, 0, 0).day_of_year() == 365)
  assert_true(dt(2024, 12, 31, 0, 0, 0).day_of_year() == 366) // 闰年
  match date_from_day_of_year(2026, 188) {
    Some(d) => {
      assert_true(d == dt(2026, 7, 7, 0, 0, 0))
      assert_true(d.day_of_year() == 188)
    }
    None => fail("expected valid ordinal date")
  }
  assert_true(date_from_day_of_year(2026, 366) is None) // 平年无 366
  assert_true(date_from_day_of_year(2026, 0) is None)
}

///|
/// ISO 周历规范样例（ISO 8601 官方边界年）。
test "iso week date canonical examples" {
  // 2005-01-01 是 2004-W53-6（跨年归前）。
  assert_true(dt(2005, 1, 1, 0, 0, 0).iso_week_date() == (2004, 53, 6))
  // 2007-01-01 是 2007-W01-1（周一开年）。
  assert_true(dt(2007, 1, 1, 0, 0, 0).iso_week_date() == (2007, 1, 1))
  // 2008-12-29 是 2009-W01-1（跨年归后）。
  assert_true(dt(2008, 12, 29, 0, 0, 0).iso_week_date() == (2009, 1, 1))
  // 2026-07-07 是周二。
  assert_true(format_iso_week_date(dt(2026, 7, 7, 0, 0, 0)) == "2026-W28-2")
}

///|
/// RFC 3339 偏移输出：UTC 时刻按 +08:00 / -05:00 显示，偏移 0 输出 Z。
test "rfc3339 offset formatting" {
  let utc = dt(2026, 7, 7, 15, 30, 0)
  assert_true(
    format_rfc3339_with_offset(utc, 480) == "2026-07-07T23:30:00+08:00",
  )
  assert_true(
    format_rfc3339_with_offset(utc, -300) == "2026-07-07T10:30:00-05:00",
  )
  assert_true(format_rfc3339_with_offset(utc, 0) == "2026-07-07T15:30:00Z")
  // 跨日：+09:00 越过午夜。
  let late = dt(2026, 7, 7, 23, 0, 0)
  assert_true(
    format_rfc3339_with_offset(late, 540) == "2026-07-08T08:00:00+09:00",
  )
}

///|
/// 偏移输出与既有 parse_iso8601 互逆（解析归一化回 UTC）。
test "offset output parses back to same utc instant" {
  let utc = dt(2026, 7, 7, 15, 30, 0)
  for off in [0, 60, 480, -300, -690] {
    match parse_iso8601(format_rfc3339_with_offset(utc, off)) {
      Some(parsed) => assert_true(parsed == utc)
      None => fail("expected parseable rfc3339 output")
    }
  }
}

///|
/// parse_duration 与 to_string 互逆 + Go 风格分量组合。
test "parse_duration accepts go style spans" {
  assert_true(parse_duration("1h30m") == Some(Duration::of_minutes(90L)))
  assert_true(parse_duration("2d") == Some(Duration::of_days(2L)))
  assert_true(
    parse_duration("1d2h3m4.500s") ==
    Some(
      Duration::of_days(1L)
      .add(Duration::of_hours(2L))
      .add(Duration::of_minutes(3L))
      .add(Duration::of_seconds(4L))
      .add(Duration::of_millis(500L)),
    ),
  )
  assert_true(parse_duration("-90m") == Some(Duration::of_minutes(-90L)))
  assert_true(parse_duration("250ms") == Some(Duration::of_millis(250L)))
  assert_true(parse_duration("0s") == Some(Duration::of_millis(0L)))
  assert_true(parse_duration("1.5s") == Some(Duration::of_millis(1500L)))
}

///|
/// parse_duration 拒绝畸形与乱序单位。
test "parse_duration rejects malformed input" {
  assert_true(parse_duration("") is None)
  assert_true(parse_duration("abc") is None)
  assert_true(parse_duration("5") is None) // 缺单位
  assert_true(parse_duration("1m2h") is None) // 单位乱序
  assert_true(parse_duration("1.5000s") is None) // 小数超 3 位
  assert_true(parse_duration("1h1h") is None) // 单位重复
}

///|
/// to_string → parse_duration roundtrip（含负值与零）。
test "duration string roundtrip" {
  let cases = [
    Duration::of_millis(0L),
    Duration::of_minutes(90L),
    Duration::of_days(1L)
    .add(Duration::of_hours(2L))
    .add(Duration::of_minutes(3L))
    .add(Duration::of_seconds(4L))
    .add(Duration::of_millis(500L)),
    Duration::of_minutes(-90L),
    Duration::of_millis(250L),
  ]
  for d in cases {
    assert_true(parse_duration(d.to_string()) == Some(d))
  }
}

///|
/// strftime POSIX 常用指示符。
test "strftime posix subset" {
  let d = dt(2026, 7, 7, 15, 30, 5)
  assert_true(strftime(d, "%Y-%m-%d %H:%M:%S") == "2026-07-07 15:30:05")
  assert_true(strftime(d, "%a %b %e") == "Tue Jul  7")
  assert_true(strftime(d, "%j") == "188")
  assert_true(strftime(d, "100%%") == "100%")
  assert_true(strftime(d, "%q") == "%q") // 未知指示符原样保留
  let nye = dt(999, 1, 9, 0, 0, 0)
  assert_true(strftime(nye, "%Y-%m-%d") == "0999-01-09")
}
