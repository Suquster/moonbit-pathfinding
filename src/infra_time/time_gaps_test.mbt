// time_gaps_test.mbt —— ISO-8601 解析与 POSIX TZ 规则错误分支覆盖收口
// （INFRA 第十九批）：逐段截断/分隔符错位/字段越界、切换点词法、
// DST 显式偏移与南半球跨年的确定性见证。

///|
test "parse_iso8601 逐段截断与分隔符错位拒绝" {
  // 年/月/日各段截断与分隔符错误。
  assert_true(parse_iso8601("202") is None)
  assert_true(parse_iso8601("2024x01-02") is None)
  assert_true(parse_iso8601("2024-1x-02") is None)
  assert_true(parse_iso8601("2024-01x02") is None)
  assert_true(parse_iso8601("2024-01-0x") is None)
  // 日期字段越界。
  assert_true(parse_iso8601("2024-13-01") is None)
  assert_true(parse_iso8601("2024-02-30") is None)
  // 时间段：分隔符 / 截断 / 字段越界。
  assert_true(parse_iso8601("2024-01-02X03:04:05") is None)
  assert_true(parse_iso8601("2024-01-02T0x:04:05") is None)
  assert_true(parse_iso8601("2024-01-02T03x04:05") is None)
  assert_true(parse_iso8601("2024-01-02T03:0x:05") is None)
  assert_true(parse_iso8601("2024-01-02T03:04x05") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:0x") is None)
  assert_true(parse_iso8601("2024-01-02T24:00:00") is None)
  // 毫秒截断 / 高精度截断为毫秒。
  assert_true(parse_iso8601("2024-01-02T03:04:05.1") is None)
  match parse_iso8601("2024-01-02T03:04:05.123456") {
    Some(dt) => assert_true(dt.millis == 123)
    None => assert_true(false)
  }
  // 时区标记：Z 后多余 / 非法符号 / 偏移截断 / 偏移越界。
  assert_true(parse_iso8601("2024-01-02T03:04:05Zx") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05x") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05+0x:00") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05+05x00") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05+05:0x") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05+24:00") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05+05:60") is None)
  assert_true(parse_iso8601("2024-01-02T03:04:05+05:000") is None)
  // 无时区标记按 UTC / 负偏移归一化。
  assert_true(parse_iso8601("2024-01-02T03:04:05") is Some(_))
  match parse_iso8601("2024-01-02T03:04:05-01:30") {
    Some(dt) => assert_true(dt.hour == 4 && dt.minute == 34)
    None => assert_true(false)
  }
}

///|
test "parse_posix_tz 词法与结构拒绝" {
  // 标准名太短 / 无 offset / offset 越界。
  assert_true(parse_posix_tz("UT") is None)
  assert_true(parse_posix_tz("UTC") is None)
  assert_true(parse_posix_tz("UTC25") is None)
  // 无 DST：后面有多余内容。
  assert_true(parse_posix_tz("UTC0!") is None)
  assert_true(parse_posix_tz("EST5") is Some(_))
  // 正号标准 offset（西正 → ISO 东负）。
  match parse_posix_tz("ABC+3") {
    Some(r) => assert_true(r.std_offset == -3 * 3600)
    None => assert_true(false)
  }
  // 显式 DST offset：正负号与越界。
  match parse_posix_tz("EST5EDT4,M3.2.0,M11.1.0") {
    Some(r) => assert_true(r.dst_offset == -4 * 3600)
    None => assert_true(false)
  }
  match parse_posix_tz("ABC-3DEF-4,M3.2.0,M11.1.0") {
    Some(r) => assert_true(r.dst_offset == 4 * 3600)
    None => assert_true(false)
  }
  assert_true(parse_posix_tz("EST5EDT25,M3.2.0,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT+,M3.2.0,M11.1.0") is None)
}

///|
test "parse_posix_tz 切换点词法拒绝与时刻后缀" {
  // 非 M 前缀 / 段缺失 / 段过多 / 非数字 / 字段越界。
  assert_true(parse_posix_tz("EST5EDT,J60,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M3.2,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M3.2.0.1,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M3.x.0,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M13.2.0,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M3.6.0,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M3.2.7,M11.1.0") is None)
  assert_true(parse_posix_tz("EST5EDT,M3..0,M11.1.0") is None)
  // `/时刻` 后缀：合法与非法。
  match parse_posix_tz("EST5EDT,M3.2.0/3,M11.1.0/1") {
    Some(r) =>
      match (r.dst_start, r.dst_end) {
        (Some(s), Some(e)) =>
          assert_true(s.at_seconds == 3 * 3600 && e.at_seconds == 3600)
        _ => assert_true(false)
      }
    None => assert_true(false)
  }
  assert_true(parse_posix_tz("EST5EDT,M3.2.0/x,M11.1.0") is None)
}

///|
test "tz 南半球跨年 DST 与偏移查询" {
  // 南半球：DST 始于 10 月、终于 4 月（start > end 跨年臂）。
  match parse_posix_tz("AEST-10AEDT-11,M10.1.0,M4.1.0") {
    Some(rule) => {
      let jan : DateTime = {
        year: 2024,
        month: 1,
        day: 15,
        hour: 12,
        minute: 0,
        second: 0,
        millis: 0,
      }
      let jul : DateTime = { ..jan, month: 7 }
      assert_true(is_dst(rule, jan))
      assert_true(is_dst(rule, jul) == false)
      let (off, name) = tz_offset_at(rule, jan)
      assert_true(off == 11 * 3600 && name == "AEDT")
      let (off2, name2) = tz_offset_at(rule, jul)
      assert_true(off2 == 10 * 3600 && name2 == "AEST")
    }
    None => assert_true(false)
  }
  // 无 DST 规则：is_dst 恒 false（_ 臂）。
  match parse_posix_tz("EST5") {
    Some(rule) => {
      let d : DateTime = {
        year: 2024,
        month: 6,
        day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        millis: 0,
      }
      assert_true(is_dst(rule, d) == false)
    }
    None => assert_true(false)
  }
}
