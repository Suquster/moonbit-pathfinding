// time_test.mbt —— 公历算法 + ISO-8601 测试（已知向量 + PBT roundtrip）。

///|
test "civil days known anchors" {
  // Unix 纪元。
  assert_eq(@infra_time.days_from_civil(1970, 1, 1), 0L)
  assert_true(@infra_time.civil_from_days(0L) == (1970, 1, 1))
  // 纪元前一天。
  assert_eq(@infra_time.days_from_civil(1969, 12, 31), -1L)
  // 千年虫日。
  assert_eq(@infra_time.days_from_civil(2000, 1, 1), 10957L)
  // 闰日 2000-02-29（能被 400 整除的世纪闰年）。
  assert_eq(@infra_time.days_from_civil(2000, 2, 29), 11016L)
  // 32 位秒溢出著名时刻 2038-01-19。
  assert_eq(@infra_time.days_from_civil(2038, 1, 19), 24855L)
  // 1900 非闰年（被 100 整除但不被 400 整除）。
  assert_true(!@infra_time.is_leap_year(1900))
  assert_true(@infra_time.is_leap_year(2000))
  assert_true(@infra_time.is_leap_year(2024))
  assert_true(!@infra_time.is_leap_year(2026))
  assert_eq(@infra_time.days_in_month(2024, 2), 29)
  assert_eq(@infra_time.days_in_month(2026, 2), 28)
}

///|
test "weekday known anchors" {
  // 1970-01-01 是周四（4）。
  assert_eq(@infra_time.weekday_from_days(0L), 4)
  // 2026-07-06 是周一（1）。
  assert_eq(
    @infra_time.weekday_from_days(@infra_time.days_from_civil(2026, 7, 6)),
    1,
  )
  // 2000-01-01 是周六（6）。
  assert_eq(
    @infra_time.weekday_from_days(@infra_time.days_from_civil(2000, 1, 1)),
    6,
  )
}

///|
test "epoch seconds conversion" {
  let dt : @infra_time.DateTime = {
    year: 2026,
    month: 7,
    day: 6,
    hour: 13,
    minute: 30,
    second: 45,
    millis: 0,
  }
  let secs = dt.to_epoch_seconds()
  assert_true(@infra_time.datetime_from_epoch_seconds(secs) == dt)
  // 纪元零点。
  assert_eq(@infra_time.datetime_from_epoch_seconds(0L).to_epoch_seconds(), 0L)
  // 负时间戳（1969-12-31T23:59:59Z）。
  let before = @infra_time.datetime_from_epoch_seconds(-1L)
  assert_eq(before.year, 1969)
  assert_eq(before.second, 59)
}

///|
test "iso8601 format and parse" {
  let dt : @infra_time.DateTime = {
    year: 2026,
    month: 7,
    day: 6,
    hour: 13,
    minute: 30,
    second: 45,
    millis: 0,
  }
  assert_eq(@infra_time.format_iso8601(dt), "2026-07-06T13:30:45Z")
  assert_eq(@infra_time.format_iso_date(dt), "2026-07-06")
  assert_true(@infra_time.parse_iso8601("2026-07-06T13:30:45Z") == Some(dt))
  // 毫秒。
  let with_ms = { ..dt, millis: 7 }
  assert_eq(@infra_time.format_iso8601(with_ms), "2026-07-06T13:30:45.007Z")
  assert_true(
    @infra_time.parse_iso8601("2026-07-06T13:30:45.007Z") == Some(with_ms),
  )
  // 仅日期。
  let date_only : @infra_time.DateTime = {
    year: 2026,
    month: 7,
    day: 6,
    hour: 0,
    minute: 0,
    second: 0,
    millis: 0,
  }
  assert_true(@infra_time.parse_iso8601("2026-07-06") == Some(date_only))
  // 空格分隔符（RFC 3339 §5.6 允许）。
  assert_true(@infra_time.parse_iso8601("2026-07-06 13:30:45Z") == Some(dt))
  // 微秒截断为毫秒。
  assert_true(
    @infra_time.parse_iso8601("2026-07-06T13:30:45.007123Z") == Some(with_ms),
  )
}

///|
test "iso8601 offset normalizes to utc" {
  // +08:00 的 21:30 即 UTC 13:30。
  let dt = @infra_time.parse_iso8601("2026-07-06T21:30:45+08:00").unwrap()
  assert_eq(@infra_time.format_iso8601(dt), "2026-07-06T13:30:45Z")
  // -05:00 的 08:30 即 UTC 13:30。
  let dt2 = @infra_time.parse_iso8601("2026-07-06T08:30:45-05:00").unwrap()
  assert_eq(@infra_time.format_iso8601(dt2), "2026-07-06T13:30:45Z")
  // 偏移跨日：+10:00 的 05:00 是前一日 19:00 UTC。
  let dt3 = @infra_time.parse_iso8601("2026-07-06T05:00:00+10:00").unwrap()
  assert_eq(@infra_time.format_iso8601(dt3), "2026-07-05T19:00:00Z")
}

///|
test "iso8601 rejects malformed input" {
  assert_true(@infra_time.parse_iso8601("") == None)
  assert_true(@infra_time.parse_iso8601("2026-13-01") == None) // 月越界
  assert_true(@infra_time.parse_iso8601("2026-02-29") == None) // 非闰年
  assert_true(@infra_time.parse_iso8601("2024-02-29") is Some(_)) // 闰年 OK
  assert_true(@infra_time.parse_iso8601("2026-07-06T24:00:00Z") == None) // 时越界
  assert_true(@infra_time.parse_iso8601("2026-07-06T13:30") == None) // 缺秒
  assert_true(@infra_time.parse_iso8601("2026/07/06") == None) // 分隔符错
  assert_true(@infra_time.parse_iso8601("2026-07-06T13:30:45Zx") == None) // 尾随
  assert_true(@infra_time.parse_iso8601("2026-07-06T13:30:45+8:00") == None) // 偏移位数错
  assert_true(@infra_time.parse_iso8601("2026-07-06T13:30:45+25:00") == None) // 偏移越界
}

///|
test "date arithmetic" {
  let dt = @infra_time.parse_iso8601("2026-07-06T13:30:45Z").unwrap()
  assert_eq(@infra_time.format_iso8601(dt.add_days(6)), "2026-07-12T13:30:45Z")
  assert_eq(
    @infra_time.format_iso8601(dt.add_seconds(-86400L * 6L)),
    "2026-06-30T13:30:45Z",
  )
  // 跨闰日。
  let feb28 = @infra_time.parse_iso8601("2024-02-28T00:00:00Z").unwrap()
  assert_eq(@infra_time.format_iso_date(feb28.add_days(1)), "2024-02-29")
  assert_eq(@infra_time.format_iso_date(feb28.add_days(2)), "2024-03-01")
  // diff。
  let a = @infra_time.parse_iso8601("2026-07-06T00:00:00Z").unwrap()
  let b = @infra_time.parse_iso8601("2026-07-05T23:59:00Z").unwrap()
  assert_eq(a.diff_seconds(b), 60L)
}

///|
test "civil days bijection (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<300 {
    // 覆盖 [-1e6, 1e6] 天（约 ±2700 年）。
    let z = (rng.next_below(2000001) - 1000000).to_int64()
    let (y, m, d) = @infra_time.civil_from_days(z)
    assert_eq(@infra_time.days_from_civil(y, m, d), z)
    assert_true(m >= 1 && m <= 12)
    assert_true(d >= 1 && d <= @infra_time.days_in_month(y, m))
  }
}

///|
test "iso8601 format parse roundtrip (pbt)" {
  let rng = @infra_pbt.rng_new(42UL)
  for _ in 0..<200 {
    let secs = (rng.next_below(2000000000) - 1000000000).to_int64()
    let dt = @infra_time.datetime_from_epoch_seconds(secs)
    let text = @infra_time.format_iso8601(dt)
    assert_true(@infra_time.parse_iso8601(text) == Some(dt))
    // 纪元秒数往返。
    assert_eq(dt.to_epoch_seconds(), secs)
    // 相邻天 weekday 递增模 7。
    let wd = dt.weekday()
    let next = dt.add_days(1)
    assert_eq(next.weekday(), (wd + 1) % 7)
  }
}
