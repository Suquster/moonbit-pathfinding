// ini.mbt —— INI 配置解析。
//
// 约定（业界共识语义，与 Python configparser / git config 对齐）：
// - `[section]` 节头；节前的键归入空名节 ""；
// - `key = value`（也接受 `key: value`），键值两侧空白剔除；
// - 行首 `;` 或 `#` 为注释；空行忽略；
// - 值可用双引号包裹（保留内部空白，剥去引号）；
// - 同节重复键取后者（last-wins）；节保序、节内键保序。
// 畸形行（无 = 或 : 的非空行、未闭合节头）返回 None。

///|
/// 解析 INI 文本 → 保序的 (节名, 保序键值对) 列表。
pub fn ini_parse(text : String) -> Array[(String, Array[(String, String)])]? {
  let sections : Array[(String, Array[(String, String)])] = []
  let mut current : Array[(String, String)] = []
  let mut current_name = ""
  let mut started = false
  for line in split_lines(text) {
    let t = trim_ws(line)
    if t == "" {
      continue
    }
    let cs = t.iter().to_array()
    if cs[0] == ';' || cs[0] == '#' {
      continue
    }
    if cs[0] == '[' {
      if cs[cs.length() - 1] != ']' {
        return None
      }
      if started || current.length() > 0 {
        sections.push((current_name, current))
      }
      let sb = StringBuilder::new()
      for i in 1..<(cs.length() - 1) {
        sb.write_char(cs[i])
      }
      current_name = trim_ws(sb.to_string())
      current = []
      started = true
      continue
    }
    // key = value 或 key: value（取首个分隔符）。
    let mut sep = -1
    for i in 0..<cs.length() {
      if cs[i] == '=' || cs[i] == ':' {
        sep = i
        break
      }
    }
    if sep <= 0 {
      return None
    }
    let ksb = StringBuilder::new()
    for i in 0..<sep {
      ksb.write_char(cs[i])
    }
    let vsb = StringBuilder::new()
    for i in (sep + 1)..<cs.length() {
      vsb.write_char(cs[i])
    }
    let key = trim_ws(ksb.to_string())
    let mut value = trim_ws(vsb.to_string())
    if key == "" {
      return None
    }
    // 剥去成对双引号。
    let vc = value.iter().to_array()
    if vc.length() >= 2 && vc[0] == '"' && vc[vc.length() - 1] == '"' {
      let sb = StringBuilder::new()
      for i in 1..<(vc.length() - 1) {
        sb.write_char(vc[i])
      }
      value = sb.to_string()
    }
    // last-wins。
    let mut replaced = false
    for i in 0..<current.length() {
      if current[i].0 == key {
        current[i] = (key, value)
        replaced = true
        break
      }
    }
    if !replaced {
      current.push((key, value))
    }
    started = true
  }
  if started || current.length() > 0 {
    sections.push((current_name, current))
  }
  Some(sections)
}

///|
/// 在解析结果里查 (节, 键)。
pub fn ini_get(
  sections : Array[(String, Array[(String, String)])],
  section : String,
  key : String,
) -> String? {
  for s in sections {
    if s.0 == section {
      for kv in s.1 {
        if kv.0 == key {
          return Some(kv.1)
        }
      }
    }
  }
  None
}

///|
/// 按 \n / \r\n 切行。
fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder::new()
  for c in text {
    if c == '\n' {
      out.push(sb.to_string())
      sb.reset()
    } else if c != '\r' {
      sb.write_char(c)
    }
  }
  out.push(sb.to_string())
  out
}

///|
/// 去除首尾空格/制表符。
fn trim_ws(s : String) -> String {
  let cs = s.iter().to_array()
  let mut start = 0
  let mut end = cs.length()
  while start < end && (cs[start] == ' ' || cs[start] == '\t') {
    start = start + 1
  }
  while end > start && (cs[end - 1] == ' ' || cs[end - 1] == '\t') {
    end = end - 1
  }
  let sb = StringBuilder::new()
  for i in start..<end {
    sb.write_char(cs[i])
  }
  sb.to_string()
}
