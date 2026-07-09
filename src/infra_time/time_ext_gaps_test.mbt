// time_ext_gaps_test.mbt —— Duration 解析与 strftime 分支覆盖收口
// （INFRA 第二十一批）：单位次序违规、小数秒截断、未知单位拒绝、
// 年/年积日补零各档、星期换算与未知指示符保留的确定性见证。

///|
fn teg_dt(y : Int, mo : Int, d : Int, h : Int, mi : Int, s : Int) -> DateTime {
  { year: y, month: mo, day: d, hour: h, minute: mi, second: s, millis: 0 }
}

///|
test "parse_duration 单位次序与畸形拒绝" {
  // 空串 / 纯负号 / 无数字 / 尾悬数字。
  assert_true(parse_duration("") is None)
  assert_true(parse_duration("-") is None)
  assert_true(parse_duration("h") is None)
  assert_true(parse_duration("5") is None)
  // 单位次序违规：低阶后不得出现同阶或更高阶。
  assert_true(parse_duration("1h1d") is None)
  assert_true(parse_duration("1m1h") is None)
  assert_true(parse_duration("1s1m") is None)
  assert_true(parse_duration("1ms1s") is None)
  assert_true(parse_duration("1d1d") is None)
  assert_true(parse_duration("1s1.5s") is None)
  // 未知单位字符。
  assert_true(parse_duration("3x") is None)
  // 小数秒：0 位 / 4 位 / 缺 s / 尾截断均拒绝。
  assert_true(parse_duration("1.s") is None)
  assert_true(parse_duration("1.2345s") is None)
  assert_true(parse_duration("1.25") is None)
  assert_true(parse_duration("1.25m") is None)
  // 合法全谱与零。
  assert_true(parse_duration("0s") == Some(Duration::of_millis(0L)))
  assert_true(parse_duration("-0s") == Some(Duration::of_millis(0L)))
  assert_true(
    parse_duration("1d2h3m4.5s") ==
    Some(Duration::of_millis(86_400_000L + 7_200_000L + 180_000L + 4_500L)),
  )
  assert_true(parse_duration("2ms") == Some(Duration::of_millis(2L)))
  assert_true(
    parse_duration("-1h30m") == Some(Duration::of_millis(-5_400_000L)),
  )
  // 小数秒补齐到毫秒：.5 → 500ms、.05 → 50ms、.005 → 5ms。
  assert_true(parse_duration("0.5s") == Some(Duration::of_millis(500L)))
  assert_true(parse_duration("0.05s") == Some(Duration::of_millis(50L)))
  assert_true(parse_duration("0.005s") == Some(Duration::of_millis(5L)))
}

///|
test "strftime 年补零各档与指示符全谱" {
  // 年位数各档补零。
  assert_true(strftime(teg_dt(7, 1, 2, 3, 4, 5), "%Y") == "0007")
  assert_true(strftime(teg_dt(77, 1, 2, 3, 4, 5), "%Y") == "0077")
  assert_true(strftime(teg_dt(777, 1, 2, 3, 4, 5), "%Y") == "0777")
  assert_true(strftime(teg_dt(2024, 1, 2, 3, 4, 5), "%Y") == "2024")
  // 年积日各档：1/9 → 001/009，40 → 040，300 → 300。
  assert_true(strftime(teg_dt(2024, 1, 9, 0, 0, 0), "%j") == "009")
  assert_true(strftime(teg_dt(2024, 2, 9, 0, 0, 0), "%j") == "040")
  assert_true(strftime(teg_dt(2024, 10, 26, 0, 0, 0), "%j") == "300")
  // 日期时间两位补零与 %e 无前导零。
  assert_true(
    strftime(teg_dt(2024, 3, 5, 6, 7, 8), "%m-%d %H:%M:%S") == "03-05 06:07:08",
  )
  assert_true(strftime(teg_dt(2024, 3, 5, 0, 0, 0), "%e") == " 5")
  assert_true(strftime(teg_dt(2024, 3, 15, 0, 0, 0), "%e") == "15")
  // 星期换算：2024-01-07 为周日（wd=0 → Sun），01-08 为周一。
  assert_true(strftime(teg_dt(2024, 1, 7, 0, 0, 0), "%a") == "Sun")
  assert_true(strftime(teg_dt(2024, 1, 8, 0, 0, 0), "%a") == "Mon")
  // 月份缩写 / 字面 % / 未知指示符保留 / 尾部孤立 %。
  assert_true(strftime(teg_dt(2024, 12, 1, 0, 0, 0), "%b") == "Dec")
  assert_true(strftime(teg_dt(2024, 1, 1, 0, 0, 0), "100%%") == "100%")
  assert_true(strftime(teg_dt(2024, 1, 1, 0, 0, 0), "%q") == "%q")
  assert_true(strftime(teg_dt(2024, 1, 1, 0, 0, 0), "x%") == "x%")
}
