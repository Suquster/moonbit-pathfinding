// time.mbt —— 日期时间基础设施：公历算法 + ISO-8601（RFC 3339 profile）。
//
// paper-to-code：Howard Hinnant. *chrono-Compatible Low-Level Date
// Algorithms*（https://howardhinnant.github.io/date_algorithms.html）：
// - `days_from_civil` / `civil_from_days`：公历 (y,m,d) 与 1970-01-01
//   起算天数的无分支双射，基于 400 年周期（era = 146097 天）与
//   「三月起算年」（把闰日移到年末）的商-余分解，全域 O(1)；
// - `weekday_from_days`：1970-01-01 为星期四的模 7 平移。
//
// ISO-8601 / RFC 3339：`YYYY-MM-DD[THH:MM:SS[.mmm]][Z|±HH:MM]`；
// 解析为总体函数（畸形返回 None），带时区偏移的输入归一化到 UTC。
// 所有时刻语义均为 UTC（proleptic Gregorian，无闰秒）。

///|
/// 公历日期时间（UTC，毫秒精度）。
pub(all) struct DateTime {
  year : Int
  month : Int // 1..12
  day : Int // 1..days_in_month
  hour : Int // 0..23
  minute : Int // 0..59
  second : Int // 0..59
  millis : Int // 0..999
} derive(Eq, Debug)

///|
/// 诊断输出（ISO-8601 形式）。
pub impl Show for DateTime with fn output(self, logger) {
  logger.write_string(format_iso8601(self))
}

///|
/// 是否闰年（proleptic Gregorian：能被 4 整除且不被 100 整除，或被 400 整除）。
pub fn is_leap_year(y : Int) -> Bool {
  y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
}

///|
/// 某年某月天数（month 取 1..12，越界返回 0）。
pub fn days_in_month(y : Int, m : Int) -> Int {
  match m {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(y) { 29 } else { 28 }
    _ => 0
  }
}

///|
/// 向下取整除法（欧几里得商，处理负数）。
fn floor_div(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a % b != 0L && (a < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
/// 欧几里得模（结果非负）。
fn floor_mod(a : Int64, b : Int64) -> Int64 {
  let r = a % b
  if r < 0L {
    r + (if b < 0L { -b } else { b })
  } else {
    r
  }
}

///|
/// 公历 (y, m, d) → 1970-01-01 起算天数（Hinnant days_from_civil）。
pub fn days_from_civil(y : Int, m : Int, d : Int) -> Int64 {
  let yy = (if m <= 2 { y - 1 } else { y }).to_int64()
  let era = floor_div(yy, 400L)
  let yoe = yy - era * 400L // [0, 399]
  let mp = (if m > 2 { m - 3 } else { m + 9 }).to_int64() // 三月起算月 [0, 11]
  let doy = (153L * mp + 2L) / 5L + d.to_int64() - 1L // [0, 365]
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy // [0, 146096]
  era * 146097L + doe - 719468L
}

///|
/// 1970-01-01 起算天数 → 公历 (y, m, d)（Hinnant civil_from_days）。
pub fn civil_from_days(z : Int64) -> (Int, Int, Int) {
  let z2 = z + 719468L
  let era = floor_div(z2, 146097L)
  let doe = z2 - era * 146097L // [0, 146096]
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L // [0, 399]
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L) // [0, 365]
  let mp = (5L * doy + 2L) / 153L // [0, 11]
  let d = doy - (153L * mp + 2L) / 5L + 1L // [1, 31]
  let m = if mp < 10L { mp + 3L } else { mp - 9L } // [1, 12]
  let year = (if m <= 2L { y + 1L } else { y }).to_int()
  (year, m.to_int(), d.to_int())
}

///|
/// 星期（0=周日 .. 6=周六；1970-01-01 为周四）。
pub fn weekday_from_days(z : Int64) -> Int {
  floor_mod(z + 4L, 7L).to_int()
}

///|
/// 日期时间的星期（0=周日 .. 6=周六）。
pub fn DateTime::weekday(self : DateTime) -> Int {
  weekday_from_days(days_from_civil(self.year, self.month, self.day))
}

///|
/// 字段范围校验（含闰年 2 月）。
pub fn DateTime::is_valid(self : DateTime) -> Bool {
  self.month >= 1 &&
  self.month <= 12 &&
  self.day >= 1 &&
  self.day <= days_in_month(self.year, self.month) &&
  self.hour >= 0 &&
  self.hour <= 23 &&
  self.minute >= 0 &&
  self.minute <= 59 &&
  self.second >= 0 &&
  self.second <= 59 &&
  self.millis >= 0 &&
  self.millis <= 999
}

///|
/// 转 Unix 时间戳（秒，UTC，忽略毫秒）。
pub fn DateTime::to_epoch_seconds(self : DateTime) -> Int64 {
  days_from_civil(self.year, self.month, self.day) * 86400L +
  self.hour.to_int64() * 3600L +
  self.minute.to_int64() * 60L +
  self.second.to_int64()
}

///|
/// 从 Unix 时间戳（秒，UTC）构造（毫秒归零）。
pub fn datetime_from_epoch_seconds(secs : Int64) -> DateTime {
  let days = floor_div(secs, 86400L)
  let rem = floor_mod(secs, 86400L)
  let (y, m, d) = civil_from_days(days)
  {
    year: y,
    month: m,
    day: d,
    hour: (rem / 3600L).to_int(),
    minute: (rem % 3600L / 60L).to_int(),
    second: (rem % 60L).to_int(),
    millis: 0,
  }
}

///|
/// 加秒数（可为负；毫秒保持不变）。
pub fn DateTime::add_seconds(self : DateTime, delta : Int64) -> DateTime {
  let dt = datetime_from_epoch_seconds(self.to_epoch_seconds() + delta)
  { ..dt, millis: self.millis }
}

///|
/// 加天数（可为负）。
pub fn DateTime::add_days(self : DateTime, delta : Int) -> DateTime {
  self.add_seconds(delta.to_int64() * 86400L)
}

///|
/// 两时刻差（秒，self - other，忽略毫秒）。
pub fn DateTime::diff_seconds(self : DateTime, other : DateTime) -> Int64 {
  self.to_epoch_seconds() - other.to_epoch_seconds()
}

///|
/// 固定宽度十进制直接写入 builder（左补零，无中间字符串分配）；
/// 负数或超宽时退化为普通十进制输出。
fn write_padded(sb : StringBuilder, n : Int, width : Int) -> Unit {
  let mut div = 1
  for _ in 1..<width {
    div = div * 10
  }
  if n < 0 || n >= div * 10 {
    sb.write_string(n.to_string())
    return
  }
  let mut d = div
  while d > 0 {
    sb.write_char((48 + n / d % 10).unsafe_to_char())
    d = d / 10
  }
}

///|
/// 格式化为 ISO-8601 / RFC 3339（UTC，`YYYY-MM-DDTHH:MM:SS[.mmm]Z`；
/// 毫秒为 0 时省略小数部分）。
pub fn format_iso8601(dt : DateTime) -> String {
  let sb = StringBuilder::new()
  write_padded(sb, dt.year, 4)
  sb.write_char('-')
  write_padded(sb, dt.month, 2)
  sb.write_char('-')
  write_padded(sb, dt.day, 2)
  sb.write_char('T')
  write_padded(sb, dt.hour, 2)
  sb.write_char(':')
  write_padded(sb, dt.minute, 2)
  sb.write_char(':')
  write_padded(sb, dt.second, 2)
  if dt.millis > 0 {
    sb.write_char('.')
    write_padded(sb, dt.millis, 3)
  }
  sb.write_char('Z')
  sb.to_string()
}

///|
/// 仅日期格式（`YYYY-MM-DD`）。
pub fn format_iso_date(dt : DateTime) -> String {
  let sb = StringBuilder::new()
  write_padded(sb, dt.year, 4)
  sb.write_char('-')
  write_padded(sb, dt.month, 2)
  sb.write_char('-')
  write_padded(sb, dt.day, 2)
  sb.to_string()
}

///|
/// 解析固定宽度十进制；返回 (值, 下一位置)，非数字返回 None。
fn parse_digits(text : String, pos : Int, width : Int) -> (Int, Int)? {
  if pos + width > text.length() {
    return None
  }
  let mut acc = 0
  for i in 0..<width {
    let cp = text.unsafe_charcode_at(pos + i)
    if cp < 48 || cp > 57 {
      return None
    }
    acc = acc * 10 + (cp - 48)
  }
  Some((acc, pos + width))
}

///|
/// 解析 ISO-8601 / RFC 3339：`YYYY-MM-DD` 或
/// `YYYY-MM-DD[T ]HH:MM:SS[.mmm][Z|±HH:MM]`。
/// 带偏移的输入归一化为 UTC；字段越界 / 畸形返回 None。
pub fn parse_iso8601(text : String) -> DateTime? {
  let n = text.length()
  let (year, p1) = match parse_digits(text, 0, 4) {
    Some(r) => r
    None => return None
  }
  if p1 >= n || text.unsafe_charcode_at(p1) != 45 {
    return None
  }
  let (month, p2) = match parse_digits(text, p1 + 1, 2) {
    Some(r) => r
    None => return None
  }
  if p2 >= n || text.unsafe_charcode_at(p2) != 45 {
    return None
  }
  let (day, p3) = match parse_digits(text, p2 + 1, 2) {
    Some(r) => r
    None => return None
  }
  let date_only : DateTime = {
    year,
    month,
    day,
    hour: 0,
    minute: 0,
    second: 0,
    millis: 0,
  }
  if p3 == n {
    return if date_only.is_valid() { Some(date_only) } else { None }
  }
  if text.unsafe_charcode_at(p3) != 84 && text.unsafe_charcode_at(p3) != 32 {
    return None
  }
  let (hour, p4) = match parse_digits(text, p3 + 1, 2) {
    Some(r) => r
    None => return None
  }
  if p4 >= n || text.unsafe_charcode_at(p4) != 58 {
    return None
  }
  let (minute, p5) = match parse_digits(text, p4 + 1, 2) {
    Some(r) => r
    None => return None
  }
  if p5 >= n || text.unsafe_charcode_at(p5) != 58 {
    return None
  }
  let (second, p6) = match parse_digits(text, p5 + 1, 2) {
    Some(r) => r
    None => return None
  }
  let mut millis = 0
  let mut pos = p6
  if pos < n && text.unsafe_charcode_at(pos) == 46 {
    let (ms, p7) = match parse_digits(text, pos + 1, 3) {
      Some(r) => r
      None => return None
    }
    millis = ms
    pos = p7
    // 吞掉更高精度的小数位（微秒/纳秒截断为毫秒）。
    while pos < n &&
          text.unsafe_charcode_at(pos) >= 48 &&
          text.unsafe_charcode_at(pos) <= 57 {
      pos = pos + 1
    }
  }
  let dt : DateTime = { year, month, day, hour, minute, second, millis }
  if !dt.is_valid() {
    return None
  }
  if pos == n {
    return Some(dt) // 无时区标记：按 UTC 解释
  }
  if text.unsafe_charcode_at(pos) == 90 {
    return if pos + 1 == n { Some(dt) } else { None }
  }
  let sign = if text.unsafe_charcode_at(pos) == 43 {
    1L
  } else if text.unsafe_charcode_at(pos) == 45 {
    -1L
  } else {
    return None
  }
  let (oh, p8) = match parse_digits(text, pos + 1, 2) {
    Some(r) => r
    None => return None
  }
  if p8 >= n || text.unsafe_charcode_at(p8) != 58 {
    return None
  }
  let (om, p9) = match parse_digits(text, p8 + 1, 2) {
    Some(r) => r
    None => return None
  }
  if p9 != n || oh > 23 || om > 59 {
    return None
  }
  // 归一化到 UTC：本地时刻 - 偏移。
  Some(dt.add_seconds(-sign * (oh.to_int64() * 3600L + om.to_int64() * 60L)))
}
