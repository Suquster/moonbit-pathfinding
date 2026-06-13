// logfmt.mbt —— logfmt 格式器与解析器（任务 4.1）。
//
// 设计依据：design.md §4.3「logfmt 格式器与解析器」（Requirement 2.3 / 2.6 /
// 2.7）。logfmt 是以空格分隔的 `key=value` 单行结构化日志约定（对标 Heroku
// logfmt 与 Go `go-kit/log`），见 README 的 paper-to-code 追溯（Requirement 10.4）。
//
// 关键编码取舍（保证类型保真往返，Requirement 2.7 / Property 3）：
//   字段取值统一以其 **JSON 表示**（复用 `value_to_json`）作为 logfmt 值 token：
//     * `VStr`  → JSON 双引号字符串（含转义），`k="hello world"`；引号使含空格 /
//       等号 / 控制字符的取值自描述边界，并与裸字面量区分（字符串恒带引号）；
//     * `VInt`  → 裸整数 `k=42`；`VFloat` → 裸浮点 `k=0.5`；`VBool` → 裸 `true`/`false`；
//     * 嵌套 `VMap` / `VList` → 紧凑 JSON 文本 `{...}` / `[...]`（自定界）。
//   解析时复用既有递归下降 JSON 读取器（`parse_value` / `jval_to_value`）从值
//   token 还原取值类型，故标量取值「先格式化再解析」严格往返（Property 3）。
//   `ts` 渲染为裸整数、`level` 渲染为大写标签（裸 token，经 `Level::from_label`
//   逆映射还原），解析时对这两个保留键特判读取裸 token。
//
// 错误处理（Requirement 13.3）：语法非法（键缺 `=`、值非法 JSON、级别标签
// 不可识别、缺 `ts`/`level`）一律返回 `None`，绝不产生部分构造事件。

///|
/// 将一条事件渲染为单行 logfmt 文本（Requirement 2.3）。
///
/// 形如 `ts=<n> level=<LABEL> <k>=<v> …`：先 `ts` 与 `level` 两个保留头，
/// 再是**按键名升序稳定排序**的字段（保证三后端逐字节一致与往返稳定）。
/// 每个字段取值以其 JSON 表示作为值 token（字符串带引号并转义，含空格 /
/// 等号 / 引号 / 控制字符的取值因此被安全包裹）。
pub fn format_logfmt(e : Event) -> String {
  let entries : Array[(String, Value)] = []
  e.fields.each(fn(k, v) { entries.push((k, v)) })
  sort_entries(entries)
  let mut out = "ts=" + e.ts.to_string() + " level=" + e.level.label()
  for i = 0; i < entries.length(); i = i + 1 {
    let (k, v) = entries[i]
    out = out + " " + k + "=" + value_to_json(v)
  }
  out
}

///|
/// 将 logfmt 文本解析回等价事件（Requirement 2.6）。
///
/// 逐 token 读取 `key=value`：`ts` / `level` 两个保留键读取裸 token 并分别
/// 还原为时间戳与级别；其余键以 JSON 读取器解析其值 token 并经 `jval_to_value`
/// 还原取值。任一项语法非法或缺 `ts`/`level` 返回 `None`（不产部分事件）。
pub fn parse_logfmt(s : String) -> Event? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let reader : JsonReader = { chars, pos: 0 }
  let mut ts_val : Int64? = None
  let mut level_val : Level? = None
  let fields : Map[String, Value] = Map::new()
  reader.skip_ws()
  while reader.pos < reader.chars.length() {
    // 读取键：到 '=' 为止；键中不得含空格（裸键约定）。
    let mut key = ""
    let mut saw_eq = false
    while reader.pos < reader.chars.length() {
      let c = reader.chars[reader.pos]
      if c == '=' {
        saw_eq = true
        reader.pos = reader.pos + 1
        break
      }
      if c == ' ' {
        break
      }
      key = key + c.to_string()
      reader.pos = reader.pos + 1
    }
    if not(saw_eq) || key == "" {
      return None
    }
    if key == "ts" {
      let tok = logfmt_read_bare(reader)
      match parse_int64(tok) {
        Some(n) => ts_val = Some(n)
        None => return None
      }
    } else if key == "level" {
      let tok = logfmt_read_bare(reader)
      match Level::from_label(tok) {
        Some(lv) => level_val = Some(lv)
        None => return None
      }
    } else {
      let jv = match parse_value(reader) {
        Some(v) => v
        None => return None
      }
      match jval_to_value(jv) {
        Some(v) => fields[key] = v
        None => return None
      }
    }
    // 值之后必须是空白分隔或行尾。
    if reader.pos < reader.chars.length() {
      let c = reader.chars[reader.pos]
      if c == ' ' {
        reader.skip_ws()
      } else {
        return None
      }
    }
  }
  match (ts_val, level_val) {
    (Some(ts), Some(level)) => Some(Event::new(ts, level, fields))
    _ => None
  }
}

///|
/// 读取一个裸 token（到空格或行尾为止），用于 `ts` / `level` 保留头的值。
fn logfmt_read_bare(r : JsonReader) -> String {
  let mut out = ""
  while r.pos < r.chars.length() {
    let c = r.chars[r.pos]
    if c == ' ' {
      break
    }
    out = out + c.to_string()
    r.pos = r.pos + 1
  }
  out
}
