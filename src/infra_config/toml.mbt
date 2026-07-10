// toml.mbt —— TOML 核心子集解析器（toml.io v1.0.0）。
//
// paper-to-code（对照 TOML v1.0.0 规范章节）：
// - 键：裸键 [A-Za-z0-9_-]、引号键（基本/字面量）、点分键（§Keys）；
// - 字符串：基本 "..."（\b \t \n \f \r \" \\ \uXXXX \UXXXXXXXX 转义）、
//   字面量 '...'（§String）；多行字符串（"""/'''，含首行换行剔除、
//   行尾反斜杠续行、紧邻结束定界符的 1–2 个引号内容、连续 6+ 引号
//   拒绝）；控制字符（U+0000–U+0008/U+000B/U+000C/U+000E–U+001F/
//   U+007F）未转义出现一律拒绝（多行形态允许换行）；
// - 整数：十进制（可下划线分隔）、0x/0o/0b 前缀（§Integer）；
// - 浮点：小数/指数、inf/nan（§Float）；
// - 布尔：true/false（§Boolean）；
// - 日期时间：RFC 3339 全形态语义校验（月/日/闰年/时分秒/偏移范围），
//   合法者按原文字符串保留（TomlDatetime，§Offset Date-Time）；
// - 数组（§Array）、内联表（§Inline Table）、[table] 与 [[array-of-tables]]
//   （§Table / §Array of Tables）、重复定义表报错。

///|
/// TOML 值。表用保序键值对数组表示（确定性遍历、三后端一致）。
pub(all) enum TomlValue {
  TomlString(String)
  TomlInt(Int64)
  TomlFloat(Double)
  TomlBool(Bool)
  TomlDatetime(String)
  TomlArray(Array[TomlValue])
  TomlTable(Array[(String, TomlValue)])
} derive(Eq, Debug)

///|
/// 在表中按键查找。
pub fn toml_get(table : Array[(String, TomlValue)], key : String) -> TomlValue? {
  for kv in table {
    if kv.0 == key {
      return Some(kv.1)
    }
  }
  None
}

///|
/// 解析器状态。
priv struct TomlParser {
  chars : Array[Char]
  mut pos : Int
}

///|
fn TomlParser::peek(self : TomlParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
fn TomlParser::advance(self : TomlParser) -> Unit {
  self.pos = self.pos + 1
}

///|
/// 跳过行内空白（空格/制表符）。
fn TomlParser::skip_ws(self : TomlParser) -> Unit {
  while self.peek() is Some(c) && (c == ' ' || c == '\t') {
    self.advance()
  }
}

///|
/// 跳过空白、注释与换行。
fn TomlParser::skip_ws_comments_newlines(self : TomlParser) -> Unit {
  for ;; {
    self.skip_ws()
    match self.peek() {
      Some('#') =>
        while self.peek() is Some(c) && c != '\n' {
          self.advance()
        }
      Some('\r') => self.advance()
      Some('\n') => self.advance()
      _ => return
    }
  }
}

///|
/// 消费到行尾（允许尾随注释）；行上有非注释内容返回 false。
fn TomlParser::expect_line_end(self : TomlParser) -> Bool {
  self.skip_ws()
  match self.peek() {
    None => true
    Some('#') => {
      while self.peek() is Some(c) && c != '\n' {
        self.advance()
      }
      true
    }
    Some('\r') => {
      self.advance()
      if self.peek() is Some('\n') {
        self.advance()
        true
      } else {
        false
      }
    }
    Some('\n') => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
fn is_bare_key_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-'
}

///|
/// 解一个键段：裸键或引号键。
fn TomlParser::parse_key_part(self : TomlParser) -> String? {
  match self.peek() {
    Some('"') => {
      guard self.parse_basic_string() is Some(s) else { return None }
      Some(s)
    }
    Some('\'') => {
      guard self.parse_literal_string() is Some(s) else { return None }
      Some(s)
    }
    Some(c) if is_bare_key_char(c) => {
      let sb = StringBuilder::new()
      while self.peek() is Some(k) && is_bare_key_char(k) {
        sb.write_char(k)
        self.advance()
      }
      Some(sb.to_string())
    }
    _ => None
  }
}

///|
/// 解点分键：`a.b."c d"` → ["a","b","c d"]。
fn TomlParser::parse_dotted_key(self : TomlParser) -> Array[String]? {
  let parts : Array[String] = []
  guard self.parse_key_part() is Some(first) else { return None }
  parts.push(first)
  for ;; {
    self.skip_ws()
    if self.peek() is Some('.') {
      self.advance()
      self.skip_ws()
      guard self.parse_key_part() is Some(next) else { return None }
      parts.push(next)
    } else {
      return Some(parts)
    }
  }
}

///|
/// 十六进制字符值；非法返回 -1。
fn toml_hex_val(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - 48
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 87
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 55
  } else {
    -1
  }
}

///|
/// 基本字符串 "..."（含转义；开头的双引号在 pos 处）。
fn TomlParser::parse_basic_string(self : TomlParser) -> String? {
  guard self.peek() is Some('"') else { return None }
  self.advance()
  // 多行 """？
  if self.pos + 1 < self.chars.length() &&
    self.chars[self.pos] == '"' &&
    self.chars[self.pos + 1] == '"' {
    self.pos = self.pos + 2
    return self.parse_multiline_basic()
  }
  let sb = StringBuilder::new()
  for ;; {
    match self.peek() {
      None | Some('\n') | Some('\r') => return None
      Some('"') => {
        self.advance()
        return Some(sb.to_string())
      }
      Some('\\') => {
        self.advance()
        guard self.parse_escape() is Some(c) else { return None }
        sb.write_char(c)
      }
      Some(c) => {
        if toml_ctrl_banned(c) {
          return None
        }
        sb.write_char(c)
        self.advance()
      }
    }
  }
}

///|
/// TOML 字符串内禁止未转义出现的控制字符（§String）：
/// U+0000–U+0008、U+000B、U+000C、U+000E–U+001F、U+007F；
/// 制表符允许，换行由各形态自行处理。
fn toml_ctrl_banned(c : Char) -> Bool {
  let v = c.to_int()
  (v >= 0x00 && v <= 0x08) ||
  v == 0x0B ||
  v == 0x0C ||
  (v >= 0x0E && v <= 0x1F) ||
  v == 0x7F
}

///|
/// 处理一个反斜杠转义（反斜杠已消费）。
fn TomlParser::parse_escape(self : TomlParser) -> Char? {
  guard self.peek() is Some(e) else { return None }
  self.advance()
  match e {
    'b' => Some('\u0008')
    't' => Some('\t')
    'n' => Some('\n')
    'f' => Some('\u000C')
    'r' => Some('\r')
    '"' => Some('"')
    '\\' => Some('\\')
    'u' => self.parse_unicode_escape(4)
    'U' => self.parse_unicode_escape(8)
    _ => None
  }
}

///|
fn TomlParser::parse_unicode_escape(self : TomlParser, n : Int) -> Char? {
  let mut cp = 0
  for _ in 0..<n {
    guard self.peek() is Some(h) else { return None }
    let v = toml_hex_val(h)
    if v < 0 {
      return None
    }
    cp = cp * 16 + v
    self.advance()
  }
  if cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
    return None
  }
  cp.to_char()
}

///|
/// 多行基本字符串体（开头 """ 已消费）：首个紧邻换行剔除；
/// 行尾反斜杠续行（吞掉其后空白与换行）。
fn TomlParser::parse_multiline_basic(self : TomlParser) -> String? {
  if self.peek() is Some('\r') {
    self.advance()
  }
  if self.peek() is Some('\n') {
    self.advance()
  }
  let sb = StringBuilder::new()
  for ;; {
    match self.peek() {
      None => return None
      Some('"') => {
        // 引号跑（§String）：末三个为结束定界符，其前 0–2 个属内容；
        // 连续 6+ 引号（内容含 3+ 连续引号）非法。
        let mut run = 0
        while self.pos + run < self.chars.length() &&
              self.chars[self.pos + run] == '"' {
          run = run + 1
        }
        if run >= 3 {
          if run > 5 {
            return None
          }
          for _k in 0..<(run - 3) {
            sb.write_char('"')
          }
          self.pos = self.pos + run
          return Some(sb.to_string())
        } else {
          for _k in 0..<run {
            sb.write_char('"')
          }
          self.pos = self.pos + run
        }
      }
      Some('\\') => {
        // 行尾续行：反斜杠后仅空白直到换行 → 吞掉后续空白。
        let mut probe = self.pos + 1
        while probe < self.chars.length() &&
              (self.chars[probe] == ' ' || self.chars[probe] == '\t') {
          probe = probe + 1
        }
        if probe < self.chars.length() &&
          (self.chars[probe] == '\n' || self.chars[probe] == '\r') {
          self.pos = probe
          while self.peek() is Some(w) &&
                (w == ' ' || w == '\t' || w == '\n' || w == '\r') {
            self.advance()
          }
        } else {
          self.advance()
          guard self.parse_escape() is Some(c) else { return None }
          sb.write_char(c)
        }
      }
      Some(c) => {
        if c != '\n' && c != '\r' && toml_ctrl_banned(c) {
          return None
        }
        sb.write_char(c)
        self.advance()
      }
    }
  }
}

///|
/// 字面量字符串 '...'（无转义）。
fn TomlParser::parse_literal_string(self : TomlParser) -> String? {
  guard self.peek() is Some('\'') else { return None }
  self.advance()
  // 多行 '''？
  if self.pos + 1 < self.chars.length() &&
    self.chars[self.pos] == '\'' &&
    self.chars[self.pos + 1] == '\'' {
    self.pos = self.pos + 2
    if self.peek() is Some('\r') {
      self.advance()
    }
    if self.peek() is Some('\n') {
      self.advance()
    }
    let sb = StringBuilder::new()
    for ;; {
      match self.peek() {
        None => return None
        Some('\'') => {
          // 引号跑：同多行基本字符串，末三个为定界符、前 0–2 个属内容。
          let mut run = 0
          while self.pos + run < self.chars.length() &&
                self.chars[self.pos + run] == '\'' {
            run = run + 1
          }
          if run >= 3 {
            if run > 5 {
              return None
            }
            for _k in 0..<(run - 3) {
              sb.write_char('\'')
            }
            self.pos = self.pos + run
            return Some(sb.to_string())
          } else {
            for _k in 0..<run {
              sb.write_char('\'')
            }
            self.pos = self.pos + run
          }
        }
        Some(c) => {
          if c != '\n' && c != '\r' && toml_ctrl_banned(c) {
            return None
          }
          sb.write_char(c)
          self.advance()
        }
      }
    }
  }
  let sb = StringBuilder::new()
  for ;; {
    match self.peek() {
      None | Some('\n') | Some('\r') => return None
      Some('\'') => {
        self.advance()
        return Some(sb.to_string())
      }
      Some(c) => {
        if toml_ctrl_banned(c) {
          return None
        }
        sb.write_char(c)
        self.advance()
      }
    }
  }
}

///|
fn is_toml_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// 数字/布尔/日期时间等裸标量：先吃出词素再分类。
fn TomlParser::parse_scalar_token(self : TomlParser) -> TomlValue? {
  let sb = StringBuilder::new()
  while self.peek() is Some(c) &&
        (
          is_toml_digit(c) ||
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          c == '+' ||
          c == '-' ||
          c == '_' ||
          c == '.' ||
          c == ':' ||
          (
            c == ' ' &&
            sb.to_string().length() == 10 &&
            looks_like_date(sb.to_string())
          )
        ) {
    // 日期时间中的空格分隔符仅在 "YYYY-MM-DD HH:.." 形态出现。
    sb.write_char(c)
    self.advance()
  }
  let tok = sb.to_string()
  classify_scalar(tok)
}

///|
/// 判断 10 字符前缀是否形如 YYYY-MM-DD。
fn looks_like_date(s : String) -> Bool {
  if s.length() != 10 {
    return false
  }
  let cs = s.iter().to_array()
  for i in 0..<10 {
    if i == 4 || i == 7 {
      if cs[i] != '-' {
        return false
      }
    } else if !is_toml_digit(cs[i]) {
      return false
    }
  }
  true
}

///|
/// 词素分类：布尔 / inf,nan / 日期时间（原文保留）/ 整数 / 浮点。
fn classify_scalar(tok : String) -> TomlValue? {
  if tok == "true" {
    return Some(TomlBool(true))
  }
  if tok == "false" {
    return Some(TomlBool(false))
  }
  if tok == "inf" || tok == "+inf" {
    return Some(TomlFloat(1.0 / 0.0))
  }
  if tok == "-inf" {
    return Some(TomlFloat(-1.0 / 0.0))
  }
  if tok == "nan" || tok == "+nan" || tok == "-nan" {
    return Some(TomlFloat(0.0 / 0.0))
  }
  if tok.length() >= 8 && looks_like_date(prefix_of(tok, 10)) {
    return if toml_valid_datetime(tok) { Some(TomlDatetime(tok)) } else { None }
  }
  // 纯时刻 HH:MM:SS[.frac]。
  if tok.length() >= 8 && tok.iter().to_array()[2] == ':' {
    let cs = tok.iter().to_array()
    return if toml_valid_time(cs, 0, allow_offset=false) {
      Some(TomlDatetime(tok))
    } else {
      None
    }
  }
  parse_number(tok)
}

///|
/// 闰年判定（格里高历）。
fn toml_is_leap_year(y : Int) -> Bool {
  (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

///|
/// 读两位十进制；非法返回 -1。
fn toml_two_digits(cs : Array[Char], i : Int) -> Int {
  if i + 2 > cs.length() || !is_toml_digit(cs[i]) || !is_toml_digit(cs[i + 1]) {
    return -1
  }
  (cs[i].to_int() - 48) * 10 + (cs[i + 1].to_int() - 48)
}

///|
/// 校验 HH:MM:SS[.frac][Z|±HH:MM]（自 `i` 起到串尾）。
/// RFC 3339 §5.6：秒允许 60（闰秒）；`allow_offset` 控制是否
/// 接受尾部时区偏移（纯时刻不带偏移）。
fn toml_valid_time(
  cs : Array[Char],
  i : Int,
  allow_offset? : Bool = true,
) -> Bool {
  let n = cs.length()
  let hh = toml_two_digits(cs, i)
  if hh < 0 || hh > 23 || i + 2 >= n || cs[i + 2] != ':' {
    return false
  }
  let mm = toml_two_digits(cs, i + 3)
  if mm < 0 || mm > 59 || i + 5 >= n || cs[i + 5] != ':' {
    return false
  }
  let ss = toml_two_digits(cs, i + 6)
  if ss < 0 || ss > 60 {
    return false
  }
  let mut j = i + 8
  if j < n && cs[j] == '.' {
    j = j + 1
    let frac_start = j
    while j < n && is_toml_digit(cs[j]) {
      j = j + 1
    }
    if j == frac_start {
      return false // 小数点后至少一位
    }
  }
  if j == n {
    return true
  }
  if !allow_offset {
    return false
  }
  if cs[j] == 'Z' || cs[j] == 'z' {
    return j + 1 == n
  }
  if cs[j] == '+' || cs[j] == '-' {
    let oh = toml_two_digits(cs, j + 1)
    if oh < 0 || oh > 23 || j + 3 >= n || cs[j + 3] != ':' {
      return false
    }
    let om = toml_two_digits(cs, j + 4)
    return om >= 0 && om <= 59 && j + 6 == n
  }
  false
}

///|
/// 日期时间语义校验（RFC 3339 / TOML §Offset Date-Time 全形态）：
/// 本地日期、本地日期时间（T/空格/t 分隔）与带偏移形态；
/// 月 1..12、日按月份与闰年上限、时分秒/偏移范围逐项校验。
fn toml_valid_datetime(tok : String) -> Bool {
  let cs = tok.iter().to_array()
  let n = cs.length()
  if n < 10 {
    return false
  }
  let year = (cs[0].to_int() - 48) * 1000 +
    (cs[1].to_int() - 48) * 100 +
    (cs[2].to_int() - 48) * 10 +
    (cs[3].to_int() - 48)
  let month = toml_two_digits(cs, 5)
  let day = toml_two_digits(cs, 8)
  if month < 1 || month > 12 {
    return false
  }
  let max_day = match month {
    2 => if toml_is_leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  if day < 1 || day > max_day {
    return false
  }
  if n == 10 {
    return true // 本地日期
  }
  if cs[10] != 'T' && cs[10] != 't' && cs[10] != ' ' {
    return false
  }
  toml_valid_time(cs, 11)
}

///|
fn prefix_of(s : String, n : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  for c in s {
    if i >= n {
      break
    }
    sb.write_char(c)
    i = i + 1
  }
  sb.to_string()
}

///|
/// 整数（十/0x/0o/0b，可下划线）与浮点（小数/指数）解析。
fn parse_number(tok : String) -> TomlValue? {
  let cs = tok.iter().to_array()
  if cs.length() == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1L
  if cs[0] == '+' {
    i = 1
  } else if cs[0] == '-' {
    sign = -1L
    i = 1
  }
  if i >= cs.length() {
    return None
  }
  // 前缀基数。
  if cs[i] == '0' && i + 1 < cs.length() {
    let p = cs[i + 1]
    if p == 'x' || p == 'o' || p == 'b' {
      if sign < 0L {
        return None
      }
      let radix = if p == 'x' { 16L } else if p == 'o' { 8L } else { 2L }
      let mut v = 0L
      let mut any = false
      let mut k = i + 2
      while k < cs.length() {
        let c = cs[k]
        if c == '_' {
          k = k + 1
          continue
        }
        let d = toml_hex_val(c).to_int64()
        if d < 0L || d >= radix {
          return None
        }
        v = v * radix + d
        any = true
        k = k + 1
      }
      if !any {
        return None
      }
      return Some(TomlInt(v))
    }
  }
  // 判定整数或浮点。
  let mut has_dot = false
  let mut has_exp = false
  for k in i..<cs.length() {
    let c = cs[k]
    if c == '.' {
      has_dot = true
    } else if c == 'e' || c == 'E' {
      has_exp = true
    } else if !is_toml_digit(c) && c != '_' && c != '+' && c != '-' {
      return None
    }
  }
  if has_dot || has_exp {
    // 浮点：去掉下划线后交给 Double 解析（手写十进制累积）。
    let cleaned = StringBuilder::new()
    for c in tok {
      if c != '_' {
        cleaned.write_char(c)
      }
    }
    return parse_float_text(cleaned.to_string())
  }
  let mut v = 0L
  let mut any = false
  for k in i..<cs.length() {
    let c = cs[k]
    if c == '_' {
      continue
    }
    if !is_toml_digit(c) {
      return None
    }
    v = v * 10L + (c.to_int() - 48).to_int64()
    any = true
  }
  if !any {
    return None
  }
  Some(TomlInt(sign * v))
}

///|
/// 十进制浮点解析：先严格校验词法（尾数 + 可选小数 + 可选指数），
/// 再交给 @string.parse_double 做正确舍入的转换。
fn parse_float_text(s : String) -> TomlValue? {
  let cs = s.iter().to_array()
  let mut i = 0
  if i < cs.length() && (cs[i] == '+' || cs[i] == '-') {
    i = i + 1
  }
  let mut any_int = false
  while i < cs.length() && is_toml_digit(cs[i]) {
    any_int = true
    i = i + 1
  }
  if !any_int {
    return None
  }
  if i < cs.length() && cs[i] == '.' {
    i = i + 1
    let mut any_frac = false
    while i < cs.length() && is_toml_digit(cs[i]) {
      any_frac = true
      i = i + 1
    }
    if !any_frac {
      return None
    }
  }
  if i < cs.length() && (cs[i] == 'e' || cs[i] == 'E') {
    i = i + 1
    if i < cs.length() && (cs[i] == '+' || cs[i] == '-') {
      i = i + 1
    }
    let mut any_exp = false
    while i < cs.length() && is_toml_digit(cs[i]) {
      any_exp = true
      i = i + 1
    }
    if !any_exp {
      return None
    }
  }
  if i != cs.length() {
    return None
  }
  Some(TomlFloat(@string.parse_double(s))) catch {
    _ => None
  }
}

///|
/// 解一个值：字符串/数组/内联表/标量。
fn TomlParser::parse_value(self : TomlParser) -> TomlValue? {
  self.skip_ws()
  match self.peek() {
    Some('"') => {
      guard self.parse_basic_string() is Some(s) else { return None }
      Some(TomlString(s))
    }
    Some('\'') => {
      guard self.parse_literal_string() is Some(s) else { return None }
      Some(TomlString(s))
    }
    Some('[') => {
      self.advance()
      let items : Array[TomlValue] = []
      self.skip_ws_comments_newlines()
      if self.peek() is Some(']') {
        self.advance()
        return Some(TomlArray(items))
      }
      for ;; {
        guard self.parse_value() is Some(v) else { return None }
        items.push(v)
        self.skip_ws_comments_newlines()
        match self.peek() {
          Some(',') => {
            self.advance()
            self.skip_ws_comments_newlines()
            if self.peek() is Some(']') {
              self.advance()
              return Some(TomlArray(items)) // 允许尾逗号
            }
          }
          Some(']') => {
            self.advance()
            return Some(TomlArray(items))
          }
          _ => return None
        }
      }
    }
    Some('{') => {
      self.advance()
      let table : Array[(String, TomlValue)] = []
      self.skip_ws()
      if self.peek() is Some('}') {
        self.advance()
        return Some(TomlTable(table))
      }
      for ;; {
        self.skip_ws()
        guard self.parse_dotted_key() is Some(key_parts) else { return None }
        self.skip_ws()
        guard self.peek() is Some('=') else { return None }
        self.advance()
        guard self.parse_value() is Some(v) else { return None }
        if !insert_dotted(table, key_parts, 0, v) {
          return None
        }
        self.skip_ws()
        match self.peek() {
          Some(',') => self.advance()
          Some('}') => {
            self.advance()
            return Some(TomlTable(table))
          }
          _ => return None
        }
      }
    }
    _ => self.parse_scalar_token()
  }
}

///|
/// 沿点分键把值插入嵌套表；键冲突（已有非表值）返回 false。
fn insert_dotted(
  table : Array[(String, TomlValue)],
  parts : Array[String],
  depth : Int,
  value : TomlValue,
) -> Bool {
  let key = parts[depth]
  if depth == parts.length() - 1 {
    for kv in table {
      if kv.0 == key {
        return false // 重复键
      }
    }
    table.push((key, value))
    return true
  }
  for i in 0..<table.length() {
    if table[i].0 == key {
      match table[i].1 {
        TomlTable(inner) => return insert_dotted(inner, parts, depth + 1, value)
        _ => return false
      }
    }
  }
  let inner : Array[(String, TomlValue)] = []
  table.push((key, TomlTable(inner)))
  insert_dotted(inner, parts, depth + 1, value)
}

///|
/// 定位（必要时创建）[a.b.c] 表头指向的表。
/// last_is_array=true 时按 [[t]] 语义在末段追加新数组元素。
fn locate_table(
  root : Array[(String, TomlValue)],
  parts : Array[String],
  last_is_array : Bool,
) -> Array[(String, TomlValue)]? {
  let mut cur = root
  for depth in 0..<parts.length() {
    let key = parts[depth]
    let is_last = depth == parts.length() - 1
    let mut found = -1
    for i in 0..<cur.length() {
      if cur[i].0 == key {
        found = i
        break
      }
    }
    if found >= 0 {
      match cur[found].1 {
        TomlTable(inner) =>
          if is_last && last_is_array {
            return None // [[t]] 与已有普通表冲突
          } else {
            cur = inner
          }
        TomlArray(items) =>
          // 数组表：进入最后一个元素。
          if is_last && last_is_array {
            let fresh : Array[(String, TomlValue)] = []
            items.push(TomlTable(fresh))
            cur = fresh
          } else if items.length() > 0 &&
            items[items.length() - 1] is TomlTable(inner) {
            cur = inner
          } else {
            return None
          }
        _ => return None
      }
    } else if is_last && last_is_array {
      let fresh : Array[(String, TomlValue)] = []
      let arr : Array[TomlValue] = [TomlTable(fresh)]
      cur.push((key, TomlArray(arr)))
      cur = fresh
    } else {
      let fresh : Array[(String, TomlValue)] = []
      cur.push((key, TomlTable(fresh)))
      cur = fresh
    }
  }
  Some(cur)
}

///|
/// 解析 TOML 文档为根表；畸形输入返回 None。
pub fn toml_parse(text : String) -> Array[(String, TomlValue)]? {
  let p : TomlParser = { chars: text.iter().to_array(), pos: 0 }
  let root : Array[(String, TomlValue)] = []
  let mut current = root
  for ;; {
    p.skip_ws_comments_newlines()
    match p.peek() {
      None => return Some(root)
      Some('[') => {
        p.advance()
        let is_array = p.peek() is Some('[')
        if is_array {
          p.advance()
        }
        p.skip_ws()
        guard p.parse_dotted_key() is Some(parts) else { return None }
        p.skip_ws()
        guard p.peek() is Some(']') else { return None }
        p.advance()
        if is_array {
          guard p.peek() is Some(']') else { return None }
          p.advance()
        }
        if !p.expect_line_end() {
          return None
        }
        guard locate_table(root, parts, is_array) is Some(t) else {
          return None
        }
        current = t
      }
      _ => {
        guard p.parse_dotted_key() is Some(parts) else { return None }
        p.skip_ws()
        guard p.peek() is Some('=') else { return None }
        p.advance()
        guard p.parse_value() is Some(v) else { return None }
        if !p.expect_line_end() {
          return None
        }
        if !insert_dotted(current, parts, 0, v) {
          return None
        }
      }
    }
  }
}
