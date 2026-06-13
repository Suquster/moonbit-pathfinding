// json.mbt —— L2 旗舰示例：JSON 解析器 / 打印器（R11.1~R11.4, R11.7）。
//
// 对应 tasks.md 任务 12.1 / 12.2，构建于 L0（原语 / 组合子 / 衍生组合子 / lazy）
// 与 L1（commit / recover）之上。展示递归结构、字符串转义解码、错误定位与
// 数组/对象元素级错误恢复。
//
// 论文映射：递归下降 + `alt` 有序选择 + `chainl/sep_by` 等衍生组合子源自
// Hutton & Meijer 1998 与 Ford 2002 的 PEG 设计。

///|
/// JSON 值（递归结构）。`derive(Eq)` 供往返等价比较（Property 28）。
pub(all) enum Json {
  JNull
  JBool(Bool)
  JNumber(Double)
  JString(String)
  JArray(Array[Json])
  JObject(Array[(String, Json)])
} derive(Eq)

// ---------------------------------------------------------------------------
// 词法辅助（whitespace / 字符类）
// ---------------------------------------------------------------------------

///|
/// 是否为 JSON 空白字符（空格 / 制表 / 换行 / 回车）。
fn json_is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// 跳过零个或多个空白字符（产出 Unit）。
fn json_ws() -> Parser[Unit] {
  map(many(satisfy(json_is_ws, label="空白")), fn(_chars) { () })
}

///|
/// 先跳过前导空白再匹配字符 `c`（lexeme 风格）。
fn json_lex_char(c : Char) -> Parser[Char] {
  bind(json_ws(), fn(_u) { pchar(c) })
}

///|
/// 十进制数字字符。
fn json_digit() -> Parser[Char] {
  satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
}

///|
/// 十六进制数字 → 其数值 [0,15]。
fn json_hexdigit() -> Parser[Int] {
  map(
    satisfy(
      fn(c) {
        (c >= '0' && c <= '9') ||
        (c >= 'a' && c <= 'f') ||
        (c >= 'A' && c <= 'F')
      },
      label="十六进制数字",
    ),
    fn(c) {
      if c >= '0' && c <= '9' {
        c.to_int() - '0'.to_int()
      } else if c >= 'a' && c <= 'f' {
        c.to_int() - 'a'.to_int() + 10
      } else {
        c.to_int() - 'A'.to_int() + 10
      }
    },
  )
}

// ---------------------------------------------------------------------------
// 字符串字面量（转义解码，R11.2）
// ---------------------------------------------------------------------------

///|
/// `\uXXXX` 转义 → 对应字符。
fn json_unicode_escape() -> Parser[Char] {
  bind(pchar('u'), fn(_u) {
    bind(json_hexdigit(), fn(h1) {
      bind(json_hexdigit(), fn(h2) {
        bind(json_hexdigit(), fn(h3) {
          map(json_hexdigit(), fn(h4) {
            let code = ((h1 * 16 + h2) * 16 + h3) * 16 + h4
            code.unsafe_to_char()
          })
        })
      })
    })
  })
}

///|
/// 转义序列：`\" \\ \/ \b \f \n \r \t \uXXXX` → 对应字符（R11.2）。
fn json_escape() -> Parser[Char] {
  bind(pchar('\\'), fn(_u) {
    alt([
      map(pchar('"'), fn(_c) { '"' }),
      map(pchar('\\'), fn(_c) { '\\' }),
      map(pchar('/'), fn(_c) { '/' }),
      map(pchar('b'), fn(_c) { '\u{0008}' }),
      map(pchar('f'), fn(_c) { '\u{000C}' }),
      map(pchar('n'), fn(_c) { '\n' }),
      map(pchar('r'), fn(_c) { '\r' }),
      map(pchar('t'), fn(_c) { '\t' }),
      json_unicode_escape(),
    ])
  })
}

///|
/// 字符串内单字符：转义序列或非 `"` / `\` 的普通字符。
fn json_str_char() -> Parser[Char] {
  alt([
    json_escape(),
    satisfy(fn(c) { c != '"' && c != '\\' }, label="字符串字符"),
  ])
}

///|
/// 解析带引号的字符串字面量，返回**解码后**的内容字符串（已跳过前导空白）。
fn json_string_raw() -> Parser[String] {
  bind(json_ws(), fn(_u) {
    bind(pchar('"'), fn(_q) {
      bind(many(json_str_char()), fn(chars) {
        map(pchar('"'), fn(_q2) {
          let mut s = ""
          for c in chars {
            s = s + "\{c}"
          }
          s
        })
      })
    })
  })
}

// ---------------------------------------------------------------------------
// 数值
// ---------------------------------------------------------------------------

///|
/// 计算 10 的整数次幂（支持负指数）。
fn json_pow10(e : Int) -> Double {
  let mut r = 1.0
  if e >= 0 {
    let mut i = 0
    while i < e {
      r = r * 10.0
      i = i + 1
    }
  } else {
    let mut i = 0
    while i < -e {
      r = r / 10.0
      i = i + 1
    }
  }
  r
}

///|
/// JSON 数值：可选负号、整数部分、可选小数部分、可选指数 → `JNumber(Double)`。
fn json_number() -> Parser[Json] {
  bind(json_ws(), fn(_u) {
    bind(optional(pchar('-')), fn(neg) {
      bind(many1(json_digit()), fn(intd) {
        bind(optional(seq(pchar('.'), many1(json_digit()))), fn(fracopt) {
          bind(optional(json_exponent()), fn(expopt) {
            let mut mant = 0.0
            for c in intd {
              mant = mant * 10.0 + (c.to_int() - '0'.to_int()).to_double()
            }
            match fracopt {
              Some((_dot, fd)) => {
                let mut scale = 0.1
                for c in fd {
                  mant = mant + (c.to_int() - '0'.to_int()).to_double() * scale
                  scale = scale / 10.0
                }
              }
              None => ()
            }
            let mut value = mant
            match expopt {
              Some(e) => value = value * json_pow10(e)
              None => ()
            }
            match neg {
              Some(_) => value = -value
              None => ()
            }
            pure(JNumber(value))
          })
        })
      })
    })
  })
}

///|
/// 指数部分 `(e|E)(+|-)?digits` → 整数指数。
fn json_exponent() -> Parser[Int] {
  bind(alt([pchar('e'), pchar('E')]), fn(_e) {
    bind(optional(alt([pchar('+'), pchar('-')])), fn(sign) {
      map(many1(json_digit()), fn(ds) {
        let mut n = 0
        for c in ds {
          n = n * 10 + (c.to_int() - '0'.to_int())
        }
        match sign {
          Some('-') => -n
          _ => n
        }
      })
    })
  })
}

// ---------------------------------------------------------------------------
// 复合值（递归经 lazy_parser 打破构造期循环）
// ---------------------------------------------------------------------------

///|
/// 字面量 `null` / `true` / `false`（已跳过前导空白）。
fn json_literal() -> Parser[Json] {
  bind(json_ws(), fn(_u) {
    alt([
      map(ptoken("null"), fn(_s) { JNull }),
      map(ptoken("true"), fn(_s) { JBool(true) }),
      map(ptoken("false"), fn(_s) { JBool(false) }),
    ])
  })
}

///|
/// JSON 值：`null|true|false | number | string | array | object`（R11.1）。
pub fn json_parser() -> Parser[Json] {
  lazy_parser(fn() {
    bind(json_ws(), fn(_u) {
      alt([
        json_literal(),
        json_number(),
        map(json_string_raw(), fn(s) { JString(s) }),
        json_array(),
        json_object(),
      ])
    })
  })
}

///|
/// JSON 数组：`'[' (value (',' value)*)? ']'` → `JArray`（空白宽容）。
fn json_array() -> Parser[Json] {
  map(
    between(
      json_lex_char('['),
      sep_by(json_parser(), json_lex_char(',')),
      json_lex_char(']'),
    ),
    fn(items) { JArray(items) },
  )
}

///|
/// 键值对：`string ':' value`（已跳过前导空白）。
fn json_pair() -> Parser[(String, Json)] {
  bind(json_string_raw(), fn(key) {
    bind(json_lex_char(':'), fn(_c) { map(json_parser(), fn(v) { (key, v) }) })
  })
}

///|
/// JSON 对象：`'{' (pair (',' pair)*)? '}'` → `JObject`（空白宽容）。
fn json_object() -> Parser[Json] {
  map(
    between(
      json_lex_char('{'),
      sep_by(json_pair(), json_lex_char(',')),
      json_lex_char('}'),
    ),
    fn(pairs) { JObject(pairs) },
  )
}

// ---------------------------------------------------------------------------
// 打印器（规范化，支撑往返 R11.7）
// ---------------------------------------------------------------------------

///|
/// 打印字符串字面量（转义特殊字符），与解析器互为逆。
fn print_json_string(s : String) -> String {
  let mut out = "\""
  for c in s {
    if c == '"' {
      out = out + "\\\""
    } else if c == '\\' {
      out = out + "\\\\"
    } else if c == '\n' {
      out = out + "\\n"
    } else if c == '\r' {
      out = out + "\\r"
    } else if c == '\t' {
      out = out + "\\t"
    } else if c == '\u{0008}' {
      out = out + "\\b"
    } else if c == '\u{000C}' {
      out = out + "\\f"
    } else {
      out = out + "\{c}"
    }
  }
  out + "\""
}

///|
/// 打印数值：整数值打印为整数形式，否则用 Double 的默认表示（规范化）。
fn print_json_number(d : Double) -> String {
  let i = d.to_int()
  if i.to_double() == d {
    "\{i}"
  } else {
    "\{d}"
  }
}

///|
/// 规范化 JSON 打印器：产出可被 `json_parser` 无歧义解析回来的紧凑文本（R11.7）。
pub fn print_json(j : Json) -> String {
  match j {
    JNull => "null"
    JBool(b) => if b { "true" } else { "false" }
    JNumber(d) => print_json_number(d)
    JString(s) => print_json_string(s)
    JArray(items) => {
      let mut out = "["
      for i, it in items {
        if i > 0 {
          out = out + ","
        }
        out = out + print_json(it)
      }
      out + "]"
    }
    JObject(pairs) => {
      let mut out = "{"
      for i, kv in pairs {
        if i > 0 {
          out = out + ","
        }
        out = out + print_json_string(kv.0) + ":" + print_json(kv.1)
      }
      out + "}"
    }
  }
}

// ---------------------------------------------------------------------------
// 顶层入口（R11.1 / R11.3）
// ---------------------------------------------------------------------------

///|
/// 顶层 JSON 解析入口：解析单个 JSON 值并要求完整消费至输入末尾。
///
/// 成功返回 `Ok(json)`；语法错误或尾随未消费输入返回携带行列与期望的
/// `@core.PathError`，且**不产生部分构造的 Json**（R11.3）。
pub fn parse_json(src : String) -> Result[Json, @core.PathError] {
  let full = bind(json_parser(), fn(v) { map(json_ws(), fn(_u) { v }) })
  match full.parse_string(src) {
    Ok(v, rest) =>
      if rest.is_eof() {
        Ok(v)
      } else {
        Err(
          @core.PathError::InvalidInput(
            "解析成功但存在尾随未消费输入于 \{rest.pos}（offset \{rest.pos.offset}）",
          ),
        )
      }
    Fail(_, ..) as f =>
      match f.to_path_error() {
        Some(e) => Err(e)
        None => Err(@core.PathError::InvalidInput("JSON 解析失败"))
      }
  }
}

// ---------------------------------------------------------------------------
// 引擎版与错误恢复（R11.4）
// ---------------------------------------------------------------------------

///|
/// JSON 值的引擎版富解析器（支持 packrat 记忆化运行入口）。
pub fn json_value_grammar() -> Grammar[Json] {
  lift(json_parser())
}

///|
/// 启用错误恢复的 JSON 数组解析：数组元素发生语法错误时记录该错误并同步到下
/// 一个 `,` 或 `]` 以继续解析后续元素（R11.4）。
///
/// 返回 `(解析出的值?, 错误列表)`：顶层为数组时按元素恢复；非数组时退化为
/// 严格的 `parse_json`（错误进入列表、值为 None 或成功值）。
pub fn parse_json_recover(src : String) -> (Json?, Array[@core.PathError]) {
  let errors : Array[@core.PathError] = []
  let input = Input::from_string(src)
  // 跳过前导空白，探测是否为数组。
  let after_ws = skip_ws_input(input)
  match after_ws.peek() {
    Some('[') => {
      let (items, rest) = recover_array_elements(after_ws.advance(), errors)
      let _ = rest
      (Some(JArray(items)), errors)
    }
    _ =>
      // 非数组：严格解析。
      match parse_json(src) {
        Ok(v) => (Some(v), errors)
        Err(e) => {
          errors.push(e)
          (None, errors)
        }
      }
  }
}

///|
/// 推进输入越过空白，返回新的 `Input`。
fn skip_ws_input(input : Input) -> Input {
  let mut cur = input
  while true {
    match cur.peek() {
      Some(c) => if json_is_ws(c) { cur = cur.advance() } else { break }
      None => break
    }
  }
  cur
}

///|
/// 从 `'['` 之后开始，按元素恢复地解析数组体直至匹配 `']'` 或输入耗尽。
///
/// 每个元素以 `json_parser` 解析；失败则记录错误并扫描到下一个 `,` 或 `]`
/// （同步点）继续。返回成功解析出的元素与剩余输入。
fn recover_array_elements(
  start : Input,
  errors : Array[@core.PathError],
) -> (Array[Json], Input) {
  let items : Array[Json] = []
  let mut cur = skip_ws_input(start)
  // 空数组：紧跟 ']'。
  match cur.peek() {
    Some(']') => return (items, cur.advance())
    _ => ()
  }
  let mut running = true
  while running {
    let elem_start = skip_ws_input(cur)
    match json_parser().parse(elem_start) {
      Ok(v, rest) => {
        items.push(v)
        cur = skip_ws_input(rest)
      }
      Fail(_, ..) as f => {
        match f.to_path_error() {
          Some(e) => errors.push(e)
          None => ()
        }
        // 同步：扫描到下一个 ',' 或 ']'。
        cur = sync_to_separator(elem_start)
      }
    }
    // 处理分隔符 / 终止符。
    match cur.peek() {
      Some(',') => cur = cur.advance()
      Some(']') => {
        cur = cur.advance()
        running = false
      }
      None => running = false
      _ =>
        // 既非分隔符也非终止符：再次同步以避免卡死。
        cur = sync_to_separator(cur)
    }
  }
  (items, cur)
}

///|
/// 扫描输入直至遇到 `,` 或 `]`（停在该分隔符上，不消费它）或输入末尾。
fn sync_to_separator(input : Input) -> Input {
  let mut cur = input
  while true {
    match cur.peek() {
      Some(',') => break
      Some(']') => break
      Some(_) => cur = cur.advance()
      None => break
    }
  }
  cur
}
