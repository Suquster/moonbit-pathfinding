// POSIX TZ 时区规则与 RFC 2822 测试。

///|
/// 构造 DateTime 简写（测试内部用）。
fn tzdt(y : Int, mo : Int, d : Int, h : Int, mi : Int, s : Int) -> DateTime {
  { year: y, month: mo, day: d, hour: h, minute: mi, second: s, millis: 0 }
}

///|
/// 解析美东规则 EST5EDT,M3.2.0,M11.1.0（glibc 同款）。
test "parse posix tz us eastern" {
  let r = parse_posix_tz("EST5EDT,M3.2.0,M11.1.0").unwrap()
  assert_true(r.std_name == "EST")
  assert_true(r.std_offset == -5 * 3600) // 西 5 区 → ISO 东正 = -18000
  assert_true(r.dst_name == "EDT")
  assert_true(r.dst_offset == -4 * 3600) // 缺省 DST = 标准 + 1h
  assert_true(
    r.dst_start == Some({ month: 3, week: 2, weekday: 0, at_seconds: 7200 }),
  )
  assert_true(
    r.dst_end == Some({ month: 11, week: 1, weekday: 0, at_seconds: 7200 }),
  )
}

///|
/// 解析中欧规则 CET-1CEST,M3.5.0,M10.5.0/3（负 offset = 东区、/3 时刻）。
test "parse posix tz central europe" {
  let r = parse_posix_tz("CET-1CEST,M3.5.0,M10.5.0/3").unwrap()
  assert_true(r.std_offset == 3600) // POSIX 的 -1 = UTC+1
  assert_true(r.dst_offset == 7200)
  assert_true(
    r.dst_end == Some({ month: 10, week: 5, weekday: 0, at_seconds: 10800 }),
  )
}

///|
/// 无 DST 规则与畸形输入拒绝。
test "parse posix tz plain and malformed" {
  let utc = parse_posix_tz("UTC0").unwrap()
  assert_true(utc.std_offset == 0 && utc.dst_start is None)
  let jst = parse_posix_tz("JST-9").unwrap()
  assert_true(jst.std_offset == 9 * 3600)
  assert_true(parse_posix_tz("") is None)
  assert_true(parse_posix_tz("AB1") is None) // 名字过短
  assert_true(parse_posix_tz("EST") is None) // 缺 offset
  assert_true(parse_posix_tz("EST5EDT") is None) // 有 DST 名但缺规则
  assert_true(parse_posix_tz("EST5EDT,M3.2.0") is None) // 缺 end
  assert_true(parse_posix_tz("EST5EDT,M13.2.0,M11.1.0") is None) // 月越界
}

///|
/// 切换日计算：与 tzdata 实际日期对拍（2026 年）。
test "transition day matches real calendar" {
  // 2026-03 第 2 个周日 = 3 月 8 日；2026-11 第 1 个周日 = 11 月 1 日。
  assert_true(
    transition_day(2026, { month: 3, week: 2, weekday: 0, at_seconds: 7200 }) ==
    8,
  )
  assert_true(
    transition_day(2026, { month: 11, week: 1, weekday: 0, at_seconds: 7200 }) ==
    1,
  )
  // 2026-03 最后一个周日 = 3 月 29 日（欧盟切换日）。
  assert_true(
    transition_day(2026, { month: 3, week: 5, weekday: 0, at_seconds: 7200 }) ==
    29,
  )
  // 2026-10 最后一个周日 = 10 月 25 日。
  assert_true(
    transition_day(2026, { month: 10, week: 5, weekday: 0, at_seconds: 7200 }) ==
    25,
  )
}

///|
/// DST 判定：美东 2026 边界（3/8 02:00 进入、11/1 02:00 退出）。
test "is_dst us eastern boundaries" {
  let r = parse_posix_tz("EST5EDT,M3.2.0,M11.1.0").unwrap()
  assert_true(is_dst(r, tzdt(2026, 1, 15, 12, 0, 0)) == false) // 冬
  assert_true(is_dst(r, tzdt(2026, 3, 8, 1, 59, 59)) == false) // 切换前 1 秒
  assert_true(is_dst(r, tzdt(2026, 3, 8, 2, 0, 0)) == true) // 恰好切换
  assert_true(is_dst(r, tzdt(2026, 7, 4, 12, 0, 0)) == true) // 夏
  assert_true(is_dst(r, tzdt(2026, 11, 1, 1, 59, 59)) == true) // 退出前
  assert_true(is_dst(r, tzdt(2026, 11, 1, 2, 0, 0)) == false) // 恰好退出
}

///|
/// 南半球跨年 DST（悉尼：10 月首周日进入、4 月首周日退出）。
test "is_dst southern hemisphere wraps year" {
  let r = parse_posix_tz("AEST-10AEDT,M10.1.0,M4.1.0/3").unwrap()
  assert_true(is_dst(r, tzdt(2026, 1, 15, 12, 0, 0)) == true) // 南半球夏（1 月）
  assert_true(is_dst(r, tzdt(2026, 7, 15, 12, 0, 0)) == false) // 南半球冬（7 月）
  assert_true(is_dst(r, tzdt(2026, 12, 25, 12, 0, 0)) == true) // 12 月已进入
}

///|
/// UTC → 当地折算（含 DST 生效偏移与缩写）。
test "utc_to_local and offset name" {
  let r = parse_posix_tz("EST5EDT,M3.2.0,M11.1.0").unwrap()
  // 夏令时：UTC 16:00 → EDT 12:00。
  let summer = utc_to_local(r, tzdt(2026, 7, 4, 16, 0, 0))
  assert_true(summer == tzdt(2026, 7, 4, 12, 0, 0))
  let (off_s, name_s) = tz_offset_at(r, summer)
  assert_true(off_s == -4 * 3600 && name_s == "EDT")
  // 标准时：UTC 16:00 → EST 11:00。
  let winter = utc_to_local(r, tzdt(2026, 1, 4, 16, 0, 0))
  assert_true(winter == tzdt(2026, 1, 4, 11, 0, 0))
  let (off_w, name_w) = tz_offset_at(r, winter)
  assert_true(off_w == -5 * 3600 && name_w == "EST")
}

///|
/// RFC 2822 格式化（Python email.utils.format_datetime 对拍）。
test "format rfc2822" {
  // 2026-07-07 是周二。
  assert_true(
    format_rfc2822(tzdt(2026, 7, 7, 15, 30, 5), 480) ==
    "Tue, 07 Jul 2026 15:30:05 +0800",
  )
  assert_true(
    format_rfc2822(tzdt(2026, 1, 1, 0, 0, 0), 0) ==
    "Thu, 01 Jan 2026 00:00:00 +0000",
  )
  assert_true(
    format_rfc2822(tzdt(2026, 11, 1, 1, 30, 0), -330) ==
    "Sun, 01 Nov 2026 01:30:00 -0530",
  )
}
