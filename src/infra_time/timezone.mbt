// timezone.mbt —— POSIX TZ 时区规则与 RFC 2822 日期格式。
//
// paper-to-code：
// - POSIX.1-2017 §8.3 *TZ* 环境变量：`std offset[dst[offset][,start,end]]`
//   规则语法，`M月.周.日` 形态的 DST 切换点（如美东
//   `EST5EDT,M3.2.0,M11.1.0`：3 月第 2 个周日进入夏令时、
//   11 月第 1 个周日退出，切换默认发生在当地时 02:00）；
// - offset 符号约定：POSIX 的 offset 是 *UTC = wall + offset*
//   （即西为正，与 ISO 相反）；
// - RFC 2822/5322 §3.3 日期格式：`Tue, 07 Jul 2026 15:30:05 +0800`。
//
// glibc/musl `tzset` 与 Go `time.LoadLocation("posix")` 的纯函数子集。

///|
/// POSIX TZ DST 切换点：`M月.周.日`（月 1..12、周 1..5（5=最后）、
/// 日 0=周日..6=周六），切换于当地时 `at_seconds`（默认 7200 = 02:00）。
pub(all) struct TzTransition {
  month : Int
  week : Int
  weekday : Int
  at_seconds : Int
} derive(Eq, Debug)

///|
/// POSIX TZ 规则：标准名/偏移 + 可选 DST 名/偏移/切换点。
/// 偏移为 **UTC 偏移秒（东为正，ISO 约定）**——解析时已把
/// POSIX 的西正约定转为 ISO 约定，避免双重负号心智负担。
pub(all) struct TzRule {
  std_name : String
  std_offset : Int // 东为正秒数
  dst_name : String // 无 DST 时为空
  dst_offset : Int
  dst_start : TzTransition? // 无 DST 时 None
  dst_end : TzTransition?
} derive(Eq, Debug)

///|
/// 解析 `M3.2.0/7200` 形态切换点（`/时刻` 可省略，默认 02:00）。
fn parse_transition(text : String) -> TzTransition? {
  if text.length() < 6 || text.get_char(0).unwrap() != 'M' {
    return None
  }
  // 拆 `/` 时刻后缀。
  let mut main = text
  let mut at = 7200
  let mut slash = -1
  for i in 0..<text.length() {
    if text.get_char(i).unwrap() == '/' {
      slash = i
      break
    }
  }
  if slash >= 0 {
    main = text[:slash].to_owned()
    let hh_text = text[slash + 1:].to_owned()
    let mut hh = 0
    for c in hh_text {
      if c < '0' || c > '9' {
        return None
      }
      hh = hh * 10 + (c.to_int() - 48)
    }
    at = hh * 3600
  }
  // M月.周.日 三段。
  let parts : Array[Int] = []
  let mut cur = 0
  let mut has = false
  for i in 1..<main.length() {
    let c = main.get_char(i).unwrap()
    if c == '.' {
      if !has {
        return None
      }
      parts.push(cur)
      cur = 0
      has = false
    } else if c >= '0' && c <= '9' {
      cur = cur * 10 + (c.to_int() - 48)
      has = true
    } else {
      return None
    }
  }
  if !has {
    return None
  }
  parts.push(cur)
  if parts.length() != 3 {
    return None
  }
  let m = parts[0]
  let w = parts[1]
  let d = parts[2]
  if m < 1 || m > 12 || w < 1 || w > 5 || d < 0 || d > 6 {
    return None
  }
  Some({ month: m, week: w, weekday: d, at_seconds: at })
}

///|
/// 解析 POSIX TZ 字符串（`std offset[dst[offset][,start,end]]` 子集）：
/// 名字为 3+ 字母；offset 形如 `[+-]H[H]`（小时粒度，POSIX 西正 →
/// 存储为 ISO 东正）。例：`EST5EDT,M3.2.0,M11.1.0`、`UTC0`、
/// `CET-1CEST,M3.5.0,M10.5.0/3`。畸形返回 None。
pub fn parse_posix_tz(text : String) -> TzRule? {
  let n = text.length()
  let mut i = 0
  // 标准名（字母）。
  let std_sb = StringBuilder::new()
  while i < n {
    let c = text.get_char(i).unwrap()
    if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
      std_sb.write_char(c)
      i = i + 1
    } else {
      break
    }
  }
  let std_name = std_sb.to_string()
  if std_name.length() < 3 {
    return None
  }
  // 标准 offset（POSIX 西正）。
  let mut sign = 1
  if i < n && text.get_char(i).unwrap() == '-' {
    sign = -1
    i = i + 1
  } else if i < n && text.get_char(i).unwrap() == '+' {
    i = i + 1
  }
  let mut hours = 0
  let mut got = false
  while i < n {
    let c = text.get_char(i).unwrap()
    if c >= '0' && c <= '9' {
      hours = hours * 10 + (c.to_int() - 48)
      got = true
      i = i + 1
    } else {
      break
    }
  }
  if !got || hours > 24 {
    return None
  }
  let std_offset = -sign * hours * 3600 // POSIX 西正 → ISO 东正
  // 可选 DST 名。
  let dst_sb = StringBuilder::new()
  while i < n {
    let c = text.get_char(i).unwrap()
    if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
      dst_sb.write_char(c)
      i = i + 1
    } else {
      break
    }
  }
  let dst_name = dst_sb.to_string()
  if dst_name.length() == 0 {
    // 无 DST：后面不得再有内容。
    if i != n {
      return None
    }
    return Some({
      std_name,
      std_offset,
      dst_name: "",
      dst_offset: std_offset,
      dst_start: None,
      dst_end: None,
    })
  }
  // 可选 DST offset（缺省 = 标准偏移 + 1 小时）。
  let mut dst_offset = std_offset + 3600
  if i < n && text.get_char(i).unwrap() != ',' {
    let mut dsign = 1
    if text.get_char(i).unwrap() == '-' {
      dsign = -1
      i = i + 1
    } else if text.get_char(i).unwrap() == '+' {
      i = i + 1
    }
    let mut dh = 0
    let mut dgot = false
    while i < n {
      let c = text.get_char(i).unwrap()
      if c >= '0' && c <= '9' {
        dh = dh * 10 + (c.to_int() - 48)
        dgot = true
        i = i + 1
      } else {
        break
      }
    }
    if !dgot || dh > 24 {
      return None
    }
    dst_offset = -dsign * dh * 3600
  }
  // `,start,end` 规则。
  if i >= n || text.get_char(i).unwrap() != ',' {
    return None
  }
  let rest = text[i + 1:].to_owned()
  let mut comma = -1
  for k in 0..<rest.length() {
    if rest.get_char(k).unwrap() == ',' {
      comma = k
      break
    }
  }
  if comma < 0 {
    return None
  }
  let start = parse_transition(rest[:comma].to_owned())
  let end = parse_transition(rest[comma + 1:].to_owned())
  match (start, end) {
    (Some(s), Some(e)) =>
      Some({
        std_name,
        std_offset,
        dst_name,
        dst_offset,
        dst_start: Some(s),
        dst_end: Some(e),
      })
    _ => None
  }
}

///|
/// 求 `year` 年中切换点对应的当地日期（月.第 week 个 weekday；
/// week=5 表示最后一个）。返回当月日号 1..31。
pub fn transition_day(year : Int, t : TzTransition) -> Int {
  // 当月 1 号星期几（0=周日）。
  let first_wd = weekday_from_days(days_from_civil(year, t.month, 1))
  // 第 1 个目标 weekday 的日号。
  let mut day = 1 + (t.weekday - first_wd + 7) % 7
  let dim = days_in_month(year, t.month)
  // 前进到第 week 个（若越界回退一周 → "最后一个"语义）。
  day = day + (t.week - 1) * 7
  while day > dim {
    day = day - 7
  }
  day
}

///|
/// 判定当地时刻（视为规则时区的墙钟时间）是否处于 DST。
/// 北半球（start < end）与南半球（start > end，跨年 DST）均正确。
pub fn is_dst(rule : TzRule, wall : DateTime) -> Bool {
  match (rule.dst_start, rule.dst_end) {
    (Some(s), Some(e)) => {
      // 墙钟时刻折算为"年内秒序"进行比较。
      let key = fn(month : Int, day : Int, secs : Int) -> Int64 {
        days_from_civil(wall.year, month, day) * 86400L + secs.to_int64()
      }
      let now = key(
        wall.month,
        wall.day,
        wall.hour * 3600 + wall.minute * 60 + wall.second,
      )
      let start = key(s.month, transition_day(wall.year, s), s.at_seconds)
      let end = key(e.month, transition_day(wall.year, e), e.at_seconds)
      if start <= end {
        now >= start && now < end // 北半球
      } else {
        now >= start || now < end // 南半球跨年
      }
    }
    _ => false
  }
}

///|
/// 当地时刻的生效 UTC 偏移秒（东为正）与时区缩写。
pub fn tz_offset_at(rule : TzRule, wall : DateTime) -> (Int, String) {
  if is_dst(rule, wall) {
    (rule.dst_offset, rule.dst_name)
  } else {
    (rule.std_offset, rule.std_name)
  }
}

///|
/// UTC 时刻 → 规则时区当地时刻（两阶段：先按标准偏移试算判定 DST，
/// 再按生效偏移折算——glibc `localtime` 同族做法）。
pub fn utc_to_local(rule : TzRule, utc : DateTime) -> DateTime {
  let guess = utc.add_seconds(rule.std_offset.to_int64())
  let (off, _) = tz_offset_at(rule, guess)
  utc.add_seconds(off.to_int64())
}

// ───────────────────────────── RFC 2822 ──────────────────────────────────

///|
/// RFC 2822/5322 §3.3 日期格式：`Tue, 07 Jul 2026 15:30:05 +0800`。
/// `offset_minutes` 为东正分钟数（`dt` 已是该偏移下的墙钟时刻）。
pub fn format_rfc2822(dt : DateTime, offset_minutes : Int) -> String {
  let wd_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let mon_names = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let abs_off = if offset_minutes < 0 {
    -offset_minutes
  } else {
    offset_minutes
  }
  let sb = StringBuilder::new()
  sb.write_string(wd_names[dt.weekday()])
  sb.write_string(", ")
  write_padded(sb, dt.day, 2)
  sb.write_char(' ')
  sb.write_string(mon_names[dt.month - 1])
  sb.write_char(' ')
  sb.write_string(dt.year.to_string())
  sb.write_char(' ')
  write_padded(sb, dt.hour, 2)
  sb.write_char(':')
  write_padded(sb, dt.minute, 2)
  sb.write_char(':')
  write_padded(sb, dt.second, 2)
  sb.write_char(' ')
  sb.write_char(if offset_minutes < 0 { '-' } else { '+' })
  write_padded(sb, abs_off / 60, 2)
  write_padded(sb, abs_off % 60, 2)
  sb.to_string()
}
