// cli_typed.mbt —— 类型化取值与声明式校验（对标 clap 的 value_parser /
// required / value_enum 语义，旁路扩展，既有 parse / help_text 冻结）。
//
// - 类型化读数：`int_of` / `bool_of` / `float_of`（总体函数，畸形返回错误）；
// - 声明式规则 `ValueRule`：required（必填）、choices（枚举约束，clap
//   `value_enum`）、类型（VInt/VFloat/VBool/VString）一次声明，
//   `validate_rules` 汇总全部违例（不短路，一次报告所有问题——对标
//   clap 的批量错误报告体验）；
// - 组合短 flag `-abc` ≡ `-a -b -c`（POSIX guideline 5）：
//   `expand_bundled_shorts` 预处理器，喂给既有 `parse` 前调用。

///|
/// 类型化取值错误。
pub(all) enum TypedError {
  NotPresent(String) // 选项未出现且无默认
  BadInt(String, String) // (选项名, 原始文本)
  BadFloat(String, String)
  BadBool(String, String)
  NotInChoices(String, String) // (选项名, 原始文本)
} derive(Eq, Debug)

///|
/// 诊断输出。
pub impl Show for TypedError with fn output(self, logger) {
  match self {
    NotPresent(n) => logger.write_string("missing required option: --" + n)
    BadInt(n, v) => logger.write_string("--" + n + ": not an integer: " + v)
    BadFloat(n, v) => logger.write_string("--" + n + ": not a number: " + v)
    BadBool(n, v) => logger.write_string("--" + n + ": not a boolean: " + v)
    NotInChoices(n, v) =>
      logger.write_string("--" + n + ": invalid choice: " + v)
  }
}

///|
/// 十进制整数解析（可带 `-`/`+` 前缀；空串/非数字返回 None；不吞溢出：
/// 用 Int64 承载，CLI 场景足够）。
fn parse_int_text(text : String) -> Int64? {
  if text.length() == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1L
  let c0 = text.get_char(0).unwrap()
  if c0 == '-' {
    sign = -1L
    i = 1
  } else if c0 == '+' {
    i = 1
  }
  if i >= text.length() {
    return None
  }
  let mut acc = 0L
  while i < text.length() {
    let c = text.get_char(i).unwrap()
    if c < '0' || c > '9' {
      return None
    }
    acc = acc * 10L + (c.to_int() - 48).to_int64()
    i = i + 1
  }
  Some(sign * acc)
}

///|
/// 类型化整数读取：未出现 → NotPresent；畸形 → BadInt。
pub fn ParsedArgs::int_of(
  self : ParsedArgs,
  name : String,
) -> Result[Int64, TypedError] {
  match self.value_of(name) {
    None => Err(NotPresent(name))
    Some(v) =>
      match parse_int_text(v) {
        Some(n) => Ok(n)
        None => Err(BadInt(name, v))
      }
  }
}

///|
/// 类型化布尔读取：接受 true/false/1/0/yes/no/on/off（大小写不敏感）。
pub fn ParsedArgs::bool_of(
  self : ParsedArgs,
  name : String,
) -> Result[Bool, TypedError] {
  match self.value_of(name) {
    None => Err(NotPresent(name))
    Some(v) => {
      let lower = to_ascii_lower(v)
      match lower {
        "true" | "1" | "yes" | "on" => Ok(true)
        "false" | "0" | "no" | "off" => Ok(false)
        _ => Err(BadBool(name, v))
      }
    }
  }
}

///|
/// 类型化浮点读取：`[-+]?digits[.digits]`（CLI 常用子集，不支持指数）。
pub fn ParsedArgs::float_of(
  self : ParsedArgs,
  name : String,
) -> Result[Double, TypedError] {
  match self.value_of(name) {
    None => Err(NotPresent(name))
    Some(v) => {
      // 拆整数与小数部分复用整数解析。
      let mut dot = -1
      for i in 0..<v.length() {
        if v.get_char(i).unwrap() == '.' {
          if dot >= 0 {
            return Err(BadFloat(name, v))
          }
          dot = i
        }
      }
      if dot < 0 {
        match parse_int_text(v) {
          Some(n) => return Ok(n.to_double())
          None => return Err(BadFloat(name, v))
        }
      }
      let int_part = v[:dot].to_owned()
      let frac_part = v[dot + 1:].to_owned()
      if frac_part.length() == 0 {
        return Err(BadFloat(name, v))
      }
      let base = match parse_int_text(int_part) {
        Some(n) => n
        None => return Err(BadFloat(name, v))
      }
      let frac = match parse_int_text(frac_part) {
        Some(n) => if n < 0L { return Err(BadFloat(name, v)) } else { n }
        None => return Err(BadFloat(name, v))
      }
      let mut scale = 1.0
      for _ in 0..<frac_part.length() {
        scale = scale * 10.0
      }
      let magnitude = if base < 0L { -base } else { base }
      let neg = base < 0L ||
        (int_part.length() > 0 && int_part.get_char(0).unwrap() == '-')
      let abs = magnitude.to_double() + frac.to_double() / scale
      Ok(if neg { -abs } else { abs })
    }
  }
}

///|
/// ASCII 小写化（选项值大小写归一）。
fn to_ascii_lower(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s.iter() {
    let cp = c.to_int()
    if cp >= 65 && cp <= 90 {
      sb.write_char(Int::unsafe_to_char(cp + 32))
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

// ───────────────────────────── 声明式校验规则 ────────────────────────────

///|
/// 值类型约束。
pub(all) enum ValueType {
  VString
  VInt
  VFloat
  VBool
} derive(Eq, Debug)

///|
/// 单选项校验规则（clap 风格声明式约束）。
pub(all) struct ValueRule {
  name : String
  required : Bool
  vtype : ValueType
  choices : Array[String] // 空数组表示不限
} derive(Eq, Debug)

///|
/// 便捷构造。
pub fn rule(
  name : String,
  required? : Bool = false,
  vtype? : ValueType = VString,
  choices? : Array[String] = [],
) -> ValueRule {
  { name, required, vtype, choices }
}

///|
/// 批量校验（不短路，汇总全部违例——对标 clap 一次报告所有错误）。
pub fn validate_rules(
  parsed : ParsedArgs,
  rules : Array[ValueRule],
) -> Array[TypedError] {
  let errs : Array[TypedError] = []
  for r in rules {
    match parsed.value_of(r.name) {
      None => if r.required { errs.push(NotPresent(r.name)) }
      Some(v) => {
        match r.vtype {
          VString => ()
          VInt => if parse_int_text(v) is None { errs.push(BadInt(r.name, v)) }
          VFloat =>
            match parsed.float_of(r.name) {
              Err(e) => errs.push(e)
              Ok(_) => ()
            }
          VBool =>
            match parsed.bool_of(r.name) {
              Err(e) => errs.push(e)
              Ok(_) => ()
            }
        }
        if r.choices.length() > 0 {
          let mut hit = false
          for c in r.choices {
            if c == v {
              hit = true
              break
            }
          }
          if !hit {
            errs.push(NotInChoices(r.name, v))
          }
        }
      }
    }
  }
  errs
}

// ───────────────────────────── 组合短 flag 展开 ──────────────────────────

///|
/// POSIX guideline 5：`-abc` ≡ `-a -b -c`（成员须全部是已注册短 Flag；
/// 任一成员不是短 Flag 则该 token 原样保留，交由 parse 报错或按值处理）。
/// `--` 之后不展开。喂给既有 `parse` 前调用。
pub fn expand_bundled_shorts(
  args : Array[String],
  specs : Array[ArgSpec],
) -> Array[String] {
  let out : Array[String] = []
  let mut after_dd = false
  for a in args {
    if after_dd || a == "--" {
      if a == "--" {
        after_dd = true
      }
      out.push(a)
      continue
    }
    if a.length() > 2 &&
      a.get_char(0).unwrap() == '-' &&
      a.get_char(1).unwrap() != '-' {
      // 校验每个成员都是已注册的短 Flag。
      let mut all_flags = true
      for i in 1..<a.length() {
        let ch = a.get_char(i).unwrap().to_string()
        let mut hit = false
        for s in specs {
          if s.short == ch && s.kind == Flag {
            hit = true
            break
          }
        }
        if !hit {
          all_flags = false
          break
        }
      }
      if all_flags {
        for i in 1..<a.length() {
          out.push("-" + a.get_char(i).unwrap().to_string())
        }
        continue
      }
    }
    out.push(a)
  }
  out
}
