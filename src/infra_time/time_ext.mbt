// time_ext.mbt —— 日期时间补深：Duration、日历运算、ISO 周历、比较。
//
// paper-to-code：
// - Duration：以毫秒整数承载的有符号时间跨度（对标 Go `time.Duration` /
//   Rust `std::time::Duration` 的确定性整数语义，无浮点漂移）；
// - 月份加减 clamp 语义：对标 java.time `LocalDate.plusMonths`——
//   2026-01-31 + 1 month = 2026-02-28（日期夹到目标月天数上限）；
// - ISO 8601 周历（ISO week date）：周一为一周之始，第 1 周为包含
//   当年第一个星期四的那一周（等价于包含 1 月 4 日的那一周）；
// - day_of_year / from_day_of_year：序数日期双射。
//
// 全部纯函数、三后端一致；不引入墙钟。

// ───────────────────────────── Duration ──────────────────────────────────

///|
/// 有符号时间跨度（毫秒整数承载；对标 Go time.Duration 的整数确定性）。
pub(all) struct Duration {
  millis : Int64
} derive(Eq, Debug)

///|
/// 由毫秒构造。
pub fn Duration::of_millis(ms : Int64) -> Duration {
  { millis: ms }
}

///|
/// 由秒构造。
pub fn Duration::of_seconds(s : Int64) -> Duration {
  { millis: s * 1000L }
}

///|
/// 由分钟构造。
pub fn Duration::of_minutes(m : Int64) -> Duration {
  { millis: m * 60_000L }
}

///|
/// 由小时构造。
pub fn Duration::of_hours(h : Int64) -> Duration {
  { millis: h * 3_600_000L }
}

///|
/// 由天构造。
pub fn Duration::of_days(d : Int64) -> Duration {
  { millis: d * 86_400_000L }
}

///|
/// 时长相加。
pub fn Duration::add(self : Duration, other : Duration) -> Duration {
  { millis: self.millis + other.millis }
}

///|
/// 时长相减。
pub fn Duration::sub(self : Duration, other : Duration) -> Duration {
  { millis: self.millis - other.millis }
}

///|
/// 取反。
pub fn Duration::neg(self : Duration) -> Duration {
  { millis: -self.millis }
}

///|
/// 绝对值。
pub fn Duration::abs(self : Duration) -> Duration {
  if self.millis < 0L {
    { millis: -self.millis }
  } else {
    self
  }
}

///|
/// 整数截断的分量读数（对标 Go `Hours()`/`Minutes()` 的整数版）。
pub fn Duration::total_seconds(self : Duration) -> Int64 {
  self.millis / 1000L
}

///|
/// 总分钟数（向零截断）。
pub fn Duration::total_minutes(self : Duration) -> Int64 {
  self.millis / 60_000L
}

///|
/// 总小时数（向零截断）。
pub fn Duration::total_hours(self : Duration) -> Int64 {
  self.millis / 3_600_000L
}

///|
/// 总天数（向零截断）。
pub fn Duration::total_days(self : Duration) -> Int64 {
  self.millis / 86_400_000L
}

///|
/// 人类可读格式（对标 Go `Duration.String()`）：`-?[Nd][Nh][Nm][N.mmms]`，
/// 零跨度输出 `0s`；例：`1d2h3m4.500s`、`-90m` → `-1h30m`。
pub fn Duration::to_string(self : Duration) -> String {
  if self.millis == 0L {
    return "0s"
  }
  let sb = StringBuilder::new()
  let mut rest = self.millis
  if rest < 0L {
    sb.write_string("-")
    rest = -rest
  }
  let d = rest / 86_400_000L
  rest = rest % 86_400_000L
  let h = rest / 3_600_000L
  rest = rest % 3_600_000L
  let m = rest / 60_000L
  rest = rest % 60_000L
  let s = rest / 1000L
  let ms = rest % 1000L
  if d > 0L {
    sb.write_string(d.to_string() + "d")
  }
  if h > 0L {
    sb.write_string(h.to_string() + "h")
  }
  if m > 0L {
    sb.write_string(m.to_string() + "m")
  }
  if s > 0L || ms > 0L {
    if ms > 0L {
      let frac = ms.to_int()
      let pad = if frac < 10 { "00" } else if frac < 100 { "0" } else { "" }
      sb.write_string(s.to_string() + "." + pad + frac.to_string() + "s")
    } else {
      sb.write_string(s.to_string() + "s")
    }
  }
  sb.to_string()
}

///|
/// 两时刻之差（毫秒精度；self - other）。
pub fn DateTime::since(self : DateTime, other : DateTime) -> Duration {
  let ds = self.to_epoch_seconds() - other.to_epoch_seconds()
  { millis: ds * 1000L + (self.millis - other.millis).to_int64() }
}

///|
/// 时刻加跨度（毫秒精度，进位/借位归一化）。
pub fn DateTime::add_duration(self : DateTime, d : Duration) -> DateTime {
  let total = self.to_epoch_seconds() * 1000L +
    self.millis.to_int64() +
    d.millis
  let secs = floor_div(total, 1000L)
  let ms = total - secs * 1000L
  let base = datetime_from_epoch_seconds(secs)
  { ..base, millis: ms.to_int() }
}

// ───────────────────────────── 比较 ──────────────────────────────────────

///|
/// 全序比较：-1 / 0 / 1（按 UTC 时间线，毫秒精度）。
pub fn DateTime::compare_to(self : DateTime, other : DateTime) -> Int {
  let a = self.to_epoch_seconds() * 1000L + self.millis.to_int64()
  let b = other.to_epoch_seconds() * 1000L + other.millis.to_int64()
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// 时间先后比较：早于。
pub fn DateTime::is_before(self : DateTime, other : DateTime) -> Bool {
  self.compare_to(other) < 0
}

///|
/// 时间先后比较：晚于。
pub fn DateTime::is_after(self : DateTime, other : DateTime) -> Bool {
  self.compare_to(other) > 0
}

// ───────────────────────────── 日历运算 ──────────────────────────────────

///|
/// 加月份（clamp 语义，对标 java.time `plusMonths`）：目标月无同日则夹到
/// 该月最后一天（2026-01-31 + 1 → 2026-02-28）。
pub fn DateTime::add_months(self : DateTime, delta : Int) -> DateTime {
  let total = self.year * 12 + (self.month - 1) + delta
  let y = if total >= 0 { total / 12 } else { (total - 11) / 12 }
  let m = total - y * 12 + 1
  let dim = days_in_month(y, m)
  let d = if self.day > dim { dim } else { self.day }
  { ..self, year: y, month: m, day: d }
}

///|
/// 加年（clamp 语义：闰日 2 月 29 日加 1 年 → 2 月 28 日）。
pub fn DateTime::add_years(self : DateTime, delta : Int) -> DateTime {
  self.add_months(delta * 12)
}

///|
/// 当年第几天（1..365/366）。
pub fn DateTime::day_of_year(self : DateTime) -> Int {
  (days_from_civil(self.year, self.month, self.day) -
  days_from_civil(self.year, 1, 1)).to_int() +
  1
}

///|
/// 序数日期 → 公历日期（day 取 1..365/366，越界返回 None）。
pub fn date_from_day_of_year(year : Int, day : Int) -> DateTime? {
  let max = if is_leap_year(year) { 366 } else { 365 }
  if day < 1 || day > max {
    return None
  }
  let z = days_from_civil(year, 1, 1) + (day - 1).to_int64()
  let (y, m, d) = civil_from_days(z)
  Some({ year: y, month: m, day: d, hour: 0, minute: 0, second: 0, millis: 0 })
}

// ───────────────────────────── ISO 周历 ──────────────────────────────────

///|
/// ISO 8601 周历 `(iso_year, week 1..53, weekday 1..7 周一=1)`。
/// 第 1 周 = 包含当年第一个星期四的那一周（等价于含 1 月 4 日的周）。
pub fn DateTime::iso_week_date(self : DateTime) -> (Int, Int, Int) {
  let z = days_from_civil(self.year, self.month, self.day)
  // weekday_from_days：0=周日..6=周六 → ISO 1=周一..7=周日。
  let wd_raw = weekday_from_days(z)
  let iso_wd = if wd_raw == 0 { 7 } else { wd_raw }
  // 本周星期四所在的年份即 ISO 年。
  let thursday = z + (4 - iso_wd).to_int64()
  let (iso_year, _, _) = civil_from_days(thursday)
  // 该 ISO 年第 1 周的星期一：1 月 4 日所在周的周一。
  let jan4 = days_from_civil(iso_year, 1, 4)
  let jan4_wd_raw = weekday_from_days(jan4)
  let jan4_wd = if jan4_wd_raw == 0 { 7 } else { jan4_wd_raw }
  let week1_monday = jan4 - (jan4_wd - 1).to_int64()
  let week = ((z - week1_monday) / 7L).to_int() + 1
  (iso_year, week, iso_wd)
}

///|
/// ISO 周历格式化：`YYYY-Www-D`（如 2026-W28-2）。
pub fn format_iso_week_date(dt : DateTime) -> String {
  let (y, w, d) = dt.iso_week_date()
  let wpad = if w < 10 { "0" } else { "" }
  "\{y}-W\{wpad}\{w}-\{d}"
}

// ───────────────────────────── RFC 3339 偏移输出 ─────────────────────────

///|
/// 以给定时区偏移（分钟，可负）输出 RFC 3339 时间戳：
/// `YYYY-MM-DDTHH:MM:SS[.mmm]±HH:MM`（偏移 0 输出 `Z`）。
/// 内部时刻恒为 UTC，本函数仅做显示换算。
pub fn format_rfc3339_with_offset(
  dt : DateTime,
  offset_minutes : Int,
) -> String {
  let shifted = dt.add_duration(Duration::of_minutes(offset_minutes.to_int64()))
  let base = format_iso8601(shifted)
  // format_iso8601 以 "Z" 结尾；替换为显式偏移。
  let body = base[:base.length() - 1].to_owned()
  if offset_minutes == 0 {
    base
  } else {
    let sign = if offset_minutes < 0 { "-" } else { "+" }
    let a = if offset_minutes < 0 { -offset_minutes } else { offset_minutes }
    let hh = a / 60
    let mm = a % 60
    let hp = if hh < 10 { "0" } else { "" }
    let mp = if mm < 10 { "0" } else { "" }
    body + sign + hp + hh.to_string() + ":" + mp + mm.to_string()
  }
}

// ───────────────────────────── Duration 解析 ─────────────────────────────

///|
/// 解析人类可读时长（Go `time.ParseDuration` 风格子集）：
/// `-?(\d+d)?(\d+h)?(\d+m)?(\d+(\.\d{1,3})?s)?(\d+ms)?`，
/// 单位须按 d>h>m>s>ms 递减出现、至少一个分量；畸形返回 None。
/// 与 `Duration::to_string` 互逆（roundtrip）。
pub fn parse_duration(text : String) -> Duration? {
  if text.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if text.get_char(0).unwrap() == '-' {
    neg = true
    i = 1
  }
  if text == "0s" || text == "-0s" {
    return Some(Duration::of_millis(0L))
  }
  let mut total = 0L
  let mut seen = false
  let mut last_rank = 0 // 已消费的最大单位等级（d=1 h=2 m=3 s=4 ms=5）
  while i < text.length() {
    // 读整数。
    let start = i
    let mut num = 0L
    while i < text.length() {
      let c = text.get_char(i).unwrap()
      if c >= '0' && c <= '9' {
        num = num * 10L + (c.to_int() - 48).to_int64()
        i = i + 1
      } else {
        break
      }
    }
    if i == start || i >= text.length() {
      return None
    }
    let c = text.get_char(i).unwrap()
    if c == 'd' {
      if last_rank >= 1 {
        return None
      }
      total = total + num * 86_400_000L
      last_rank = 1
      i = i + 1
    } else if c == 'h' {
      if last_rank >= 2 {
        return None
      }
      total = total + num * 3_600_000L
      last_rank = 2
      i = i + 1
    } else if c == 'm' {
      // 'm' 或 'ms'。
      if i + 1 < text.length() && text.get_char(i + 1).unwrap() == 's' {
        if last_rank >= 5 {
          return None
        }
        total = total + num
        last_rank = 5
        i = i + 2
      } else {
        if last_rank >= 3 {
          return None
        }
        total = total + num * 60_000L
        last_rank = 3
        i = i + 1
      }
    } else if c == '.' {
      // 小数秒：num.frac s（毫秒精度，1..3 位）。
      if last_rank >= 4 {
        return None
      }
      i = i + 1
      let fstart = i
      let mut frac = 0
      while i < text.length() {
        let fc = text.get_char(i).unwrap()
        if fc >= '0' && fc <= '9' {
          frac = frac * 10 + (fc.to_int() - 48)
          i = i + 1
        } else {
          break
        }
      }
      let digits = i - fstart
      if digits < 1 || digits > 3 || i >= text.length() {
        return None
      }
      if text.get_char(i).unwrap() != 's' {
        return None
      }
      let mut ms = frac
      for _ in digits..<3 {
        ms = ms * 10
      }
      total = total + num * 1000L + ms.to_int64()
      last_rank = 4
      i = i + 1
    } else if c == 's' {
      if last_rank >= 4 {
        return None
      }
      total = total + num * 1000L
      last_rank = 4
      i = i + 1
    } else {
      return None
    }
    seen = true
  }
  if !seen {
    return None
  }
  Some(Duration::of_millis(if neg { -total } else { total }))
}

// ───────────────────────────── 格式化模式 ────────────────────────────────

///|
/// strftime 风格格式化（POSIX 常用子集）：
/// `%Y` 四位年、`%m` 两位月、`%d` 两位日、`%H` 两位时、`%M` 两位分、
/// `%S` 两位秒、`%j` 三位年积日、`%a` 英文星期缩写、`%b` 英文月份缩写、
/// `%e` 无前导零日、`%%` 字面 `%`；未知指示符原样保留。
pub fn strftime(dt : DateTime, pattern : String) -> String {
  let sb = StringBuilder::new()
  let pad2 = fn(v : Int) -> String {
    if v < 10 {
      "0" + v.to_string()
    } else {
      v.to_string()
    }
  }
  let wd_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  let mon_names = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let mut i = 0
  while i < pattern.length() {
    let c = pattern.get_char(i).unwrap()
    if c != '%' || i + 1 >= pattern.length() {
      sb.write_char(c)
      i = i + 1
      continue
    }
    let d = pattern.get_char(i + 1).unwrap()
    match d {
      'Y' => {
        let y = dt.year
        if y < 10 {
          sb.write_string("000" + y.to_string())
        } else if y < 100 {
          sb.write_string("00" + y.to_string())
        } else if y < 1000 {
          sb.write_string("0" + y.to_string())
        } else {
          sb.write_string(y.to_string())
        }
      }
      'm' => sb.write_string(pad2(dt.month))
      'd' => sb.write_string(pad2(dt.day))
      'H' => sb.write_string(pad2(dt.hour))
      'M' => sb.write_string(pad2(dt.minute))
      'S' => sb.write_string(pad2(dt.second))
      'j' => {
        let doy = dt.day_of_year()
        if doy < 10 {
          sb.write_string("00" + doy.to_string())
        } else if doy < 100 {
          sb.write_string("0" + doy.to_string())
        } else {
          sb.write_string(doy.to_string())
        }
      }
      'a' => {
        // weekday(): 0=Sunday..6=Saturday（time.mbt 语义）→ 转 ISO 下标。
        let wd = dt.weekday()
        let iso = if wd == 0 { 6 } else { wd - 1 }
        sb.write_string(wd_names[iso])
      }
      'b' => sb.write_string(mon_names[dt.month - 1])
      'e' =>
        sb.write_string(
          if dt.day < 10 {
            " " + dt.day.to_string()
          } else {
            dt.day.to_string()
          },
        )
      '%' => sb.write_string("%")
      _ => {
        sb.write_char('%')
        sb.write_char(d)
      }
    }
    i = i + 2
  }
  sb.to_string()
}
