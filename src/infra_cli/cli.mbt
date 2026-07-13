// cli.mbt —— CLI 参数解析（对标 Rust clap / Go flag 的核心子集）。
//
// 语义遵循 POSIX Utility Syntax Guidelines + GNU 长选项扩展：
// - `-v` 短 flag、`--verbose` 长 flag；
// - `--name value` 与 `--name=value` 两种取值形式；
// - `--` 之后全部按位置参数处理（POSIX guideline 10）;
// - 子命令（git 风格）：第一个非 flag 参数若匹配已注册子命令则切换；
// - 未知 flag / 缺值 / 重复定义返回结构化错误（总体函数，不崩溃）。

///|
/// 选项种类。
pub(all) enum ArgKind {
  Flag // 布尔开关，出现即真
  Value // 带一个值
} derive(Eq, Debug)

///|
/// 选项规格。
pub(all) struct ArgSpec {
  name : String // 长名（不含 --）
  short : String // 短名（不含 -），空串表示无
  kind : ArgKind
  help : String
  default : String? // Value 类型的默认值
} derive(Eq, Debug)

///|
/// 命令定义（可带子命令）。
pub(all) struct Command {
  name : String
  about : String
  specs : Array[ArgSpec]
  subcommands : Array[Command]
} derive(Debug)

///|
/// 解析错误。
pub(all) enum CliError {
  UnknownFlag(String)
  MissingValue(String)
  DuplicateSpec(String)
} derive(Eq, Debug)

///|
/// 诊断输出。
pub impl Show for CliError with fn output(self, logger) {
  match self {
    UnknownFlag(s) => logger.write_string("unknown flag: " + s)
    MissingValue(s) => logger.write_string("missing value for: " + s)
    DuplicateSpec(s) => logger.write_string("duplicate spec: " + s)
  }
}

///|
/// 解析结果。
pub(all) struct ParsedArgs {
  command_path : Array[String] // 命中的子命令链
  flags : Array[String] // 出现的布尔 flag（长名）
  values : Array[(String, String)] // 带值选项（长名, 值）
  positionals : Array[String]
} derive(Eq, Debug)

///|
/// 布尔 flag 是否出现。
pub fn ParsedArgs::has_flag(self : ParsedArgs, name : String) -> Bool {
  for f in self.flags {
    if f == name {
      return true
    }
  }
  false
}

///|
/// 取带值选项（含默认值回退需在 spec 侧处理后写入）。
pub fn ParsedArgs::value_of(self : ParsedArgs, name : String) -> String? {
  for kv in self.values {
    if kv.0 == name {
      return Some(kv.1)
    }
  }
  None
}

///|
/// 便捷构造 Flag 规格。
pub fn flag_spec(name : String, short : String, help : String) -> ArgSpec {
  { name, short, kind: Flag, help, default: None }
}

///|
/// 便捷构造 Value 规格。
pub fn value_spec(
  name : String,
  short : String,
  help : String,
  default : String?,
) -> ArgSpec {
  { name, short, kind: Value, help, default }
}

///|
/// token 从 `off` 起的尾部是否等于 `name`（零分配比较）。
fn tail_eq(token : String, off : Int, name : String) -> Bool {
  if token.length() - off != name.length() {
    return false
  }
  for i in 0..<name.length() {
    if token.unsafe_charcode_at(off + i) != name.unsafe_charcode_at(i) {
      return false
    }
  }
  true
}

///|
/// 在规格表中查找（长名或短名）。
fn find_spec(specs : Array[ArgSpec], token : String) -> ArgSpec? {
  if token.has_prefix("--") {
    for s in specs {
      if tail_eq(token, 2, s.name) {
        return Some(s)
      }
    }
  } else if token.has_prefix("-") && token.length() > 1 {
    for s in specs {
      if s.short != "" && tail_eq(token, 1, s.short) {
        return Some(s)
      }
    }
  }
  None
}

///|
/// 找 '=' 分割 `--name=value`；无 '=' 返回 None。
fn split_eq(token : String) -> (String, String)? {
  let n = token.length()
  for i in 2..<n {
    if token.unsafe_charcode_at(i) == 61 { // '='
      return Some((token[0:i].to_string(), token[i + 1:n].to_string()))
    }
  }
  None
}

///|
/// 校验规格表无重名。
fn validate_specs(specs : Array[ArgSpec]) -> CliError? {
  for i in 0..<specs.length() {
    for j in (i + 1)..<specs.length() {
      if specs[i].name == specs[j].name ||
        (specs[i].short != "" && specs[i].short == specs[j].short) {
        return Some(DuplicateSpec(specs[i].name))
      }
    }
  }
  None
}

///|
/// 解析参数向量（不含程序名）。
pub fn parse(
  cmd : Command,
  argv : Array[String],
) -> Result[ParsedArgs, CliError] {
  parse_at(cmd, argv, 0, [])
}

///|
fn parse_at(
  cmd : Command,
  argv : Array[String],
  start : Int,
  path : Array[String],
) -> Result[ParsedArgs, CliError] {
  match validate_specs(cmd.specs) {
    Some(e) => return Err(e)
    None => ()
  }
  let flags : Array[String] = []
  let values : Array[(String, String)] = []
  let positionals : Array[String] = []
  let mut i = start
  let mut after_dd = false
  while i < argv.length() {
    let tok = argv[i]
    if after_dd {
      positionals.push(tok)
      i = i + 1
      continue
    }
    if tok == "--" {
      after_dd = true
      i = i + 1
      continue
    }
    if tok.has_prefix("-") && tok.length() > 1 {
      // --name=value 形式。
      match split_eq(tok) {
        Some((name_part, value_part)) =>
          match find_spec(cmd.specs, name_part) {
            Some(spec) =>
              if spec.kind == Value {
                values.push((spec.name, value_part))
                i = i + 1
                continue
              } else {
                return Err(MissingValue(spec.name))
              }
            None => return Err(UnknownFlag(name_part))
          }
        None => ()
      }
      match find_spec(cmd.specs, tok) {
        Some(spec) =>
          match spec.kind {
            Flag => {
              flags.push(spec.name)
              i = i + 1
            }
            Value =>
              if i + 1 < argv.length() {
                values.push((spec.name, argv[i + 1]))
                i = i + 2
              } else {
                return Err(MissingValue(spec.name))
              }
          }
        None => return Err(UnknownFlag(tok))
      }
      continue
    }
    // 首个非 flag 位置：尝试子命令。
    if positionals.length() == 0 {
      for sub in cmd.subcommands {
        if sub.name == tok {
          path.push(tok)
          return parse_at(sub, argv, i + 1, path)
        }
      }
    }
    positionals.push(tok)
    i = i + 1
  }
  // 填充带默认值且未出现的 Value 选项。
  for s in cmd.specs {
    if s.kind == Value {
      let mut seen = false
      for kv in values {
        if kv.0 == s.name {
          seen = true
          break
        }
      }
      if !seen {
        match s.default {
          Some(d) => values.push((s.name, d))
          None => ()
        }
      }
    }
  }
  Ok({ command_path: path, flags, values, positionals })
}

///|
/// 生成 help 文本（usage + 选项对齐 + 子命令列表）。
pub fn help_text(cmd : Command) -> String {
  let sb = StringBuilder::new()
  sb.write_string(cmd.name)
  if cmd.about != "" {
    sb.write_string(" — " + cmd.about)
  }
  sb.write_string("\n\nUSAGE:\n    " + cmd.name + " [OPTIONS]")
  if cmd.subcommands.length() > 0 {
    sb.write_string(" [SUBCOMMAND]")
  }
  sb.write_string(" [ARGS]\n")
  if cmd.specs.length() > 0 {
    sb.write_string("\nOPTIONS:\n")
    // 计算对齐宽度。
    let mut width = 0
    for s in cmd.specs {
      let w = s.name.length() +
        (if s.short != "" { s.short.length() + 4 } else { 0 })
      if w > width {
        width = w
      }
    }
    for s in cmd.specs {
      let mut left_len = 4
      sb.write_string("    ")
      if s.short != "" {
        sb.write_char('-')
        sb.write_string(s.short)
        sb.write_string(", ")
        left_len = left_len + 3 + s.short.length()
      } else {
        sb.write_string("    ")
        left_len = left_len + 4
      }
      sb.write_string("--")
      sb.write_string(s.name)
      left_len = left_len + 2 + s.name.length()
      if s.kind == Value {
        sb.write_string(" <VALUE>")
        left_len = left_len + 8
      }
      while left_len < width + 20 {
        sb.write_char(' ')
        left_len = left_len + 1
      }
      sb.write_string(s.help)
      match s.default {
        Some(d) => {
          sb.write_string(" [default: ")
          sb.write_string(d)
          sb.write_char(']')
        }
        None => ()
      }
      sb.write_char('\n')
    }
  }
  if cmd.subcommands.length() > 0 {
    sb.write_string("\nSUBCOMMANDS:\n")
    for sub in cmd.subcommands {
      sb.write_string("    " + sub.name + "    " + sub.about + "\n")
    }
  }
  sb.to_string()
}
