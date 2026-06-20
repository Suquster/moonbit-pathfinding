// json.mbt —— 包内最小、自包含的 JSON 值模型与解析/打印器（任务 14.1）。
//
// 见 moon.pkg 顶部说明：@serialization（R9）面向 protobuf，无通用 JSON 值类型
// 可复用，故在 lsp_binding 内实现最小 JSON 值模型 `Json` 及其往返编解码，逐字节
// （ASCII）地与 `Bytes` 互转，保证三后端（wasm-gc / js / native）行为一致。
//
// 数值采用「保留原始字面量文本」的 `JNum(String)` 表示：既满足 round-trip 无损
// （Property 11，任务 14.3），又规避不同后端浮点格式化差异对「三后端差分一致性」
// 质量门禁的冲击。

// ───────────────────────────── JSON 值模型 ─────────────────────────────

///|
/// 最小 JSON 值模型。`JNum` 保留数值的原始字面量文本以保证往返无损；`JObj`
/// 以「有序键值对数组」表示对象，保留插入顺序（利于确定性打印与往返）。
pub(all) enum Json {
  JNull
  JBool(Bool)
  JNum(String) // 原始数值字面量文本（如 "1"、"-3.14"、"2e10"）
  JStr(String)
  JArr(Array[Json])
  JObj(Array[(String, Json)])
} derive(Eq, Show)

///|
/// 在有序键值对中按 key 查找首个匹配项；不存在返回 `None`。
fn json_obj_get(fields : Array[(String, Json)], key : String) -> Json? {
  for kv in fields {
    let (k, v) = kv
    if k == key {
      return Some(v)
    }
  }
  None
}

// ───────────────────────────── 字节 ⇄ 文本 ─────────────────────────────

///|
/// `Bytes` → 文本：逐字节还原为字符（ASCII 无损；与既有方向 round-trip 测试中
/// 的字节↔文本约定一致）。JSON-RPC 控制结构均为 ASCII，骨架以此为前提。
fn bytes_to_text(b : Bytes) -> String {
  // 以 StringBuilder 摊还 O(1) 追加、O(n) 物化，规避循环内 `s = s + ...`
  // 的 O(n²) 拼接（quality-enforcement / anti-patterns 约束）。
  let sb = StringBuilder::new()
  let mut i = 0
  while i < b.length() {
    sb.write_char(b[i].to_int().unsafe_to_char())
    i = i + 1
  }
  sb.to_string()
}

///|
/// 文本 → `Bytes`：逐字符写出低 8 位（与 `bytes_to_text` 互逆，ASCII 无损）。
fn text_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

// ───────────────────────────── 解析器（recursive descent） ─────────────

///|
/// 解析游标：不可变字符序列 + 可变偏移。
struct JParser {
  chars : Array[Char]
  mut pos : Int
}

///|
/// 查看当前字符（不前进）；越界返回 `None`。
fn JParser::peek(self : JParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
/// 跳过零个或多个 JSON 空白（空格 / 制表 / 换行 / 回车）。
fn JParser::skip_ws(self : JParser) -> Unit {
  let mut go = true
  while go {
    match self.peek() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') =>
        self.pos = self.pos + 1
      _ => go = false
    }
  }
}

///|
/// 将一份文本解析为 JSON 值；要求整串恰为一个 JSON 值（尾随多余字符视为失败）。
/// 解析失败返回 `None`（由 decode_message 映射为规范的解析错误）。
fn parse_json(text : String) -> Json? {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let p = { chars, pos: 0 }
  p.skip_ws()
  match p.parse_value() {
    None => None
    Some(j) => {
      p.skip_ws()
      if p.pos == p.chars.length() {
        Some(j)
      } else {
        None // 尾随多余字符。
      }
    }
  }
}

///|
/// 解析单个 JSON 值（对象 / 数组 / 字符串 / 数值 / true / false / null）。
fn JParser::parse_value(self : JParser) -> Json? {
  self.skip_ws()
  match self.peek() {
    None => None
    Some('{') => self.parse_object()
    Some('[') => self.parse_array()
    Some('"') =>
      match self.parse_string_lit() {
        Some(s) => Some(JStr(s))
        None => None
      }
    Some('t') => self.parse_keyword("true", JBool(true))
    Some('f') => self.parse_keyword("false", JBool(false))
    Some('n') => self.parse_keyword("null", JNull)
    Some(c) =>
      if c == '-' || (c >= '0' && c <= '9') {
        self.parse_number()
      } else {
        None
      }
  }
}

///|
/// 匹配字面关键字（true / false / null）；不匹配返回 `None`。
fn JParser::parse_keyword(self : JParser, word : String, value : Json) -> Json? {
  for c in word {
    match self.peek() {
      Some(x) => if x == c { self.pos = self.pos + 1 } else { return None }
      None => return None
    }
  }
  Some(value)
}

///|
/// 当前字符是否为十进制数字。
fn is_digit(c : Char?) -> Bool {
  match c {
    Some(d) => d >= '0' && d <= '9'
    None => false
  }
}

///|
/// 解析 JSON 数值，保留原始字面量文本为 `JNum`。语法：可选负号、整数部分（至少
/// 一位）、可选小数部分、可选指数部分；任一部分非法返回 `None`。
fn JParser::parse_number(self : JParser) -> Json? {
  let start = self.pos
  if self.peek() == Some('-') {
    self.pos = self.pos + 1
  }
  let int_start = self.pos
  while is_digit(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.pos == int_start {
    return None // 整数部分至少需要一位数字。
  }
  if self.peek() == Some('.') {
    self.pos = self.pos + 1
    let frac_start = self.pos
    while is_digit(self.peek()) {
      self.pos = self.pos + 1
    }
    if self.pos == frac_start {
      return None // 小数点后至少需要一位数字。
    }
  }
  match self.peek() {
    Some('e') | Some('E') => {
      self.pos = self.pos + 1
      match self.peek() {
        Some('+') | Some('-') => self.pos = self.pos + 1
        _ => ()
      }
      let exp_start = self.pos
      while is_digit(self.peek()) {
        self.pos = self.pos + 1
      }
      if self.pos == exp_start {
        return None // 指数部分至少需要一位数字。
      }
    }
    _ => ()
  }
  let sb = StringBuilder::new()
  let mut i = start
  while i < self.pos {
    sb.write_char(self.chars[i])
    i = i + 1
  }
  Some(JNum(sb.to_string()))
}

///|
/// 解析一个 JSON 字符串字面量（含转义）。当前字符须为开引号 `"`。未闭合 / 非法
/// 转义返回 `None`。
fn JParser::parse_string_lit(self : JParser) -> String? {
  if self.peek() != Some('"') {
    return None
  }
  self.pos = self.pos + 1
  let sb = StringBuilder::new()
  while true {
    match self.peek() {
      None => return None // 未闭合。
      Some('"') => {
        self.pos = self.pos + 1
        return Some(sb.to_string())
      }
      Some('\\') => {
        self.pos = self.pos + 1
        match self.peek() {
          None => return None
          Some(e) => {
            self.pos = self.pos + 1
            match e {
              '"' => sb.write_char('"')
              '\\' => sb.write_char('\\')
              '/' => sb.write_char('/')
              'n' => sb.write_char('\n')
              't' => sb.write_char('\t')
              'r' => sb.write_char('\r')
              'b' => sb.write_char((0x08).unsafe_to_char())
              'f' => sb.write_char((0x0C).unsafe_to_char())
              'u' =>
                match self.parse_hex4() {
                  Some(code) => sb.write_char(code.unsafe_to_char())
                  None => return None
                }
              _ => return None // 非法转义。
            }
          }
        }
      }
      Some(c) => {
        self.pos = self.pos + 1
        sb.write_char(c)
      }
    }
  }
  None
}

///|
/// 解析 4 位十六进制（\uXXXX 的码位）；非法返回 `None`。
fn JParser::parse_hex4(self : JParser) -> Int? {
  let mut code = 0
  let mut i = 0
  while i < 4 {
    match self.peek() {
      None => return None
      Some(c) => {
        let d = hex_value(c)
        if d < 0 {
          return None
        }
        code = code * 16 + d
        self.pos = self.pos + 1
        i = i + 1
      }
    }
  }
  Some(code)
}

///|
/// 单个十六进制字符的数值（0..15）；非十六进制返回 -1。
fn hex_value(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// 解析 JSON 对象。当前字符须为 `{`。键非字符串 / 缺冒号 / 缺逗号或闭括号均返回
/// `None`。保留键的出现顺序。
fn JParser::parse_object(self : JParser) -> Json? {
  self.pos = self.pos + 1 // 消费 '{'
  let fields : Array[(String, Json)] = []
  self.skip_ws()
  if self.peek() == Some('}') {
    self.pos = self.pos + 1
    return Some(JObj(fields))
  }
  while true {
    self.skip_ws()
    let key = match self.parse_string_lit() {
      Some(k) => k
      None => return None
    }
    self.skip_ws()
    if self.peek() != Some(':') {
      return None
    }
    self.pos = self.pos + 1 // 消费 ':'
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    fields.push((key, value))
    self.skip_ws()
    match self.peek() {
      Some(',') => self.pos = self.pos + 1
      Some('}') => {
        self.pos = self.pos + 1
        return Some(JObj(fields))
      }
      _ => return None
    }
  }
  None
}

///|
/// 解析 JSON 数组。当前字符须为 `[`。缺逗号或闭括号返回 `None`。
fn JParser::parse_array(self : JParser) -> Json? {
  self.pos = self.pos + 1 // 消费 '['
  let items : Array[Json] = []
  self.skip_ws()
  if self.peek() == Some(']') {
    self.pos = self.pos + 1
    return Some(JArr(items))
  }
  while true {
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    items.push(value)
    self.skip_ws()
    match self.peek() {
      Some(',') => self.pos = self.pos + 1
      Some(']') => {
        self.pos = self.pos + 1
        return Some(JArr(items))
      }
      _ => return None
    }
  }
  None
}

// ───────────────────────────── 打印器 ─────────────────────────────────

///|
/// 将 JSON 值打印为紧凑（无多余空白）文本，与 `parse_json` 往返配套。
fn print_json(j : Json) -> String {
  let sb = StringBuilder::new()
  write_json(sb, j)
  sb.to_string()
}

///|
/// 将 JSON 值写入共享的 `StringBuilder`（摊还 O(1) 追加），规避递归打印时
/// 每层 `out = out + ...` 造成的 O(n²) 拼接。
fn write_json(sb : StringBuilder, j : Json) -> Unit {
  match j {
    JNull => sb.write_string("null")
    JBool(true) => sb.write_string("true")
    JBool(false) => sb.write_string("false")
    JNum(s) => sb.write_string(s)
    JStr(s) => write_json_string(sb, s)
    JArr(items) => {
      sb.write_char('[')
      let mut first = true
      for it in items {
        if first {
          first = false
        } else {
          sb.write_char(',')
        }
        write_json(sb, it)
      }
      sb.write_char(']')
    }
    JObj(fields) => {
      sb.write_char('{')
      let mut first = true
      for kv in fields {
        let (k, v) = kv
        if first {
          first = false
        } else {
          sb.write_char(',')
        }
        write_json_string(sb, k)
        sb.write_char(':')
        write_json(sb, v)
      }
      sb.write_char('}')
    }
  }
}

///|
/// 将带引号、按 JSON 规则转义的字符串写入 `StringBuilder`（摊还 O(1)）。
fn write_json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for c in s {
    let code = c.to_int()
    if c == '"' {
      sb.write_string("\\\"")
    } else if c == '\\' {
      sb.write_string("\\\\")
    } else if c == '\n' {
      sb.write_string("\\n")
    } else if c == '\t' {
      sb.write_string("\\t")
    } else if c == '\r' {
      sb.write_string("\\r")
    } else if code == 0x08 {
      sb.write_string("\\b")
    } else if code == 0x0C {
      sb.write_string("\\f")
    } else if code < 0x20 {
      sb.write_string("\\u")
      sb.write_string(hex4(code))
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char('"')
}

///|
/// 将一个码位格式化为 4 位小写十六进制（用于 \uXXXX 转义）。
fn hex4(code : Int) -> String {
  let d0 = code / 4096 % 16
  let d1 = code / 256 % 16
  let d2 = code / 16 % 16
  let d3 = code % 16
  hex_digit(d0) + hex_digit(d1) + hex_digit(d2) + hex_digit(d3)
}

///|
/// 单个十六进制位（0..15）→ 小写字符。
fn hex_digit(d : Int) -> String {
  if d < 10 {
    ('0'.to_int() + d).unsafe_to_char().to_string()
  } else {
    ('a'.to_int() + (d - 10)).unsafe_to_char().to_string()
  }
}

///|
/// 将一个 JSON 数值字面量文本解析为整数；非整数（含小数点 / 指数）返回 `None`。
/// 用于把 JSON 数值 id 还原为 `Id::IdNum`。
fn parse_int_literal(s : String) -> Int? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    i = 1
  } else if chars[0] == '+' {
    i = 1
  }
  if i >= chars.length() {
    return None
  }
  let mut v = 0
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      i = i + 1
    } else {
      return None // 非整数字面量。
    }
  }
  Some(if neg { -v } else { v })
}
