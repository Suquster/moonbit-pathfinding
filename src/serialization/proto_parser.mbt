// proto_parser.mbt —— `.proto` 解析（高层接口 parse_proto），构建于 @parser_combinator。
//
// 对应任务 7.1 的 parse_proto 高层接口，且满足"proto_parser 构建于
// @parser_combinator"的设计约束（design.md §「方向九」模块边界）：标识符、
// 关键字等终结符以 @parser_combinator 的原语（satisfy / many1）与统一的
// Input / Pos / ParseResult 模型解析。
//
// 范围（Requirement 9.5「解析为消息/字段/枚举的模式描述」）：解析顶层
//   * `syntax` / `package` / `import` / `option` 语句（跳过，以 ';' 结尾）；
//   * `message` 块 —— 收集名称与简单字段（`[repeated] 类型 名称 = 字段号;`）；
//   * `enum` 块 —— 收集名称与 `标识符 = 取值;` 枚举值；
//   * `service` 块 —— 跳过块体（不收集）。
// 支持行注释 `//` 与块注释，跳过字段选项 `[...]`。完整 proto3 文法（oneof / map /
// 嵌套类型展开 / 全部标量类型）属于后续子 spec 迭代。
//
// 失败契约（Requirement 9.6）：任何语法错误返回**含行列位置**的 `ParseError`。

///|
/// 是否为空白字符（空格 / 制表 / 换行 / 回车）。
fn is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// 是否为标识符字符（字母 / 数字 / 下划线 / 点，后者用于带包前缀的限定名）。
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '.'
}

///|
/// 跳过零个或多个空白与注释（行注释 `//`、块注释），返回跳过后的输入。
fn skip_trivia(input : @parser_combinator.Input) -> @parser_combinator.Input {
  let mut cur = input
  let mut go = true
  while go {
    match cur.peek() {
      Some(c) =>
        if is_ws(c) {
          cur = cur.advance()
        } else if c == '/' {
          let nxt = cur.advance()
          match nxt.peek() {
            Some('/') => {
              // 行注释：跳到行尾。
              let mut c2 = nxt.advance()
              let mut inner = true
              while inner {
                match c2.peek() {
                  Some('\n') => {
                    c2 = c2.advance()
                    inner = false
                  }
                  None => inner = false
                  Some(_) => c2 = c2.advance()
                }
              }
              cur = c2
            }
            Some('*') => {
              // 块注释：跳到 `*/`。
              let mut c2 = nxt.advance()
              let mut inner = true
              while inner {
                match c2.peek() {
                  None => inner = false
                  Some('*') => {
                    let after = c2.advance()
                    match after.peek() {
                      Some('/') => {
                        c2 = after.advance()
                        inner = false
                      }
                      _ => c2 = after
                    }
                  }
                  Some(_) => c2 = c2.advance()
                }
              }
              cur = c2
            }
            _ => go = false // 孤立的 '/'，非注释，停止跳过。
          }
        } else {
          go = false
        }
      None => go = false
    }
  }
  cur
}

///|
/// 解析一个标识符，返回 `(名称, 剩余输入)`；失败返回 `None`。
/// 复用 @parser_combinator.many1 + satisfy 构建（至少一个标识符字符）。
fn parse_ident(
  input : @parser_combinator.Input,
) -> (String, @parser_combinator.Input)? {
  let ident_char = @parser_combinator.satisfy(
    is_ident_char,
    label="标识符字符",
  )
  match @parser_combinator.many1(ident_char).parse(input) {
    Ok(chars, rest) => {
      // 以 `@infra_text.TextBuilder` 顺序追加字符，消除原 `name = name + ...`
      // 的循环内 O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
      let sb = @infra_text.TextBuilder::new()
      for c in chars {
        sb.push_char(c)
      }
      Some((sb.build(), rest))
    }
    Fail(_, ..) => None
  }
}

///|
/// 解析一个（可带负号的）十进制整数，返回 `(值, 剩余输入)`；失败返回 `None`。
fn parse_number(
  input : @parser_combinator.Input,
) -> (Int, @parser_combinator.Input)? {
  let mut cur = input
  let mut neg = false
  match cur.peek() {
    Some('-') => {
      neg = true
      cur = cur.advance()
    }
    _ => ()
  }
  // 以 `@infra_text.TextBuilder` 顺序追加数字字符，消除原 `digits = digits + ...`
  // 的循环内 O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
  let digits_buf = @infra_text.TextBuilder::new()
  let mut go = true
  while go {
    match cur.peek() {
      Some(d) =>
        if d >= '0' && d <= '9' {
          digits_buf.push_char(d)
          cur = cur.advance()
        } else {
          go = false
        }
      None => go = false
    }
  }
  let digits = digits_buf.build()
  if digits == "" {
    return None
  }
  let mut v = 0
  for ch in digits {
    v = v * 10 + (ch.to_int() - '0'.to_int())
  }
  Some((if neg { -v } else { v }, cur))
}

///|
/// 若当前字符等于 `c` 则消费并返回剩余输入；否则返回 `None`。
fn try_char(
  input : @parser_combinator.Input,
  c : Char,
) -> @parser_combinator.Input? {
  match input.peek() {
    Some(x) => if x == c { Some(input.advance()) } else { None }
    None => None
  }
}

///|
/// 从 `{` 之后开始按括号配平跳过块体，返回 `}` 之后的输入；未闭合 → 错误。
fn skip_block(
  after_open : @parser_combinator.Input,
) -> Result[@parser_combinator.Input, ParseError] {
  let mut cur = after_open
  let mut depth = 1
  while depth > 0 {
    match cur.peek() {
      None =>
        return Err(
          ParseError::at(after_open.pos, "块未闭合：缺少匹配的 '}'"),
        )
      Some(c) => {
        if c == '{' {
          depth = depth + 1
        } else if c == '}' {
          depth = depth - 1
        }
        cur = cur.advance()
      }
    }
  }
  Ok(cur)
}

///|
/// 跳过一段直到（并消费）指定终止字符 `stop`，返回其后的输入；未遇到 → 错误。
fn skip_until(
  input : @parser_combinator.Input,
  stop : Char,
  what : String,
) -> Result[@parser_combinator.Input, ParseError] {
  let mut cur = input
  while true {
    match cur.peek() {
      None => return Err(ParseError::at(input.pos, what))
      Some(c) => {
        cur = cur.advance()
        if c == stop {
          return Ok(cur)
        }
      }
    }
  }
  Ok(cur)
}

///|
/// 将 proto 标量/引用类型名映射为 schema 字段类型。
///
/// 已知标量关键字映射为对应标量类型；其余按消息引用 `TMessage` 处理（若该名
/// 实为枚举，将在 `parse_proto` 的解析后处理阶段重写为 `TEnum`）。
fn field_type_of(name : String) -> FieldType {
  match name {
    "int32" => TInt32
    "sint32" => TInt32
    "sfixed32" => TInt32
    "fixed32" => TInt32
    "int64" => TInt64
    "sint64" => TInt64
    "sfixed64" => TInt64
    "fixed64" => TInt64
    "uint32" => TUInt32
    "uint64" => TUInt64
    "bool" => TBool
    "string" => TString
    "bytes" => TBytes
    _ => TMessage(name)
  }
}

///|
/// 解析 message 块体（输入位于起始 `{` 之后），收集简单字段定义。
fn parse_message_body(
  start : @parser_combinator.Input,
) -> Result[(Array[FieldDef], @parser_combinator.Input), ParseError] {
  let fields : Array[FieldDef] = []
  let mut cur = start
  while true {
    cur = skip_trivia(cur)
    match cur.peek() {
      None => return Err(ParseError::at(start.pos, "message 块未闭合"))
      Some('}') => return Ok((fields, cur.advance()))
      Some(';') => cur = cur.advance() // 容忍空语句。
      _ =>
        match parse_ident(cur) {
          None =>
            return Err(ParseError::at(cur.pos, "字段声明期望标识符"))
          Some((tok, after)) =>
            if tok == "message" || tok == "enum" || tok == "oneof" {
              // 嵌套类型：跳过可选名 + 配平块体（骨架不展开嵌套）。
              let a1 = skip_trivia(after)
              let a2 = match parse_ident(a1) {
                Some((_, r)) => r
                None => a1
              }
              let a3 = skip_trivia(a2)
              match a3.peek() {
                Some('{') =>
                  match skip_block(a3.advance()) {
                    Ok(r) => cur = r
                    Err(e) => return Err(e)
                  }
                _ =>
                  return Err(ParseError::at(a3.pos, "嵌套类型期望 '{'"))
              }
            } else if tok == "reserved" ||
              tok == "option" ||
              tok == "extensions" {
              match skip_until(after, ';', "声明缺少结尾 ';'") {
                Ok(r) => cur = r
                Err(e) => return Err(e)
              }
            } else {
              // 字段：[repeated/optional/required] 类型 名称 = 字段号 [选项] ;
              let mut repeated = false
              let mut type_name = tok
              let mut tail = after
              if tok == "repeated" || tok == "optional" || tok == "required" {
                repeated = tok == "repeated"
                let a1 = skip_trivia(after)
                match parse_ident(a1) {
                  Some((t2, r2)) => {
                    type_name = t2
                    tail = r2
                  }
                  None =>
                    return Err(ParseError::at(a1.pos, "期望字段类型"))
                }
              }
              let aws = skip_trivia(tail)
              // map<...> 等带尖括号的复合类型：骨架跳过整条声明。
              if aws.peek() == Some('<') {
                match skip_until(aws, ';', "map 字段缺少结尾 ';'") {
                  Ok(r) => {
                    cur = r
                    continue
                  }
                  Err(e) => return Err(e)
                }
              }
              match parse_ident(aws) {
                None => return Err(ParseError::at(aws.pos, "期望字段名"))
                Some((fname, r1)) => {
                  let r2 = skip_trivia(r1)
                  match try_char(r2, '=') {
                    None =>
                      return Err(ParseError::at(r2.pos, "字段期望 '='"))
                    Some(r3) => {
                      let r4 = skip_trivia(r3)
                      match parse_number(r4) {
                        None =>
                          return Err(
                            ParseError::at(r4.pos, "字段期望字段号"),
                          )
                        Some((num, r5)) => {
                          let r6 = skip_trivia(r5)
                          // 可选字段选项 `[...]`。
                          let r7 = if r6.peek() == Some('[') {
                            match
                              skip_until(r6, ']', "字段选项缺少 ']'") {
                              Ok(r) => r
                              Err(e) => return Err(e)
                            }
                          } else {
                            r6
                          }
                          let r8 = skip_trivia(r7)
                          match try_char(r8, ';') {
                            None =>
                              return Err(
                                ParseError::at(r8.pos, "字段期望 ';'"),
                              )
                            Some(r9) => {
                              fields.push({
                                name: fname,
                                number: num,
                                ftype: field_type_of(type_name),
                                repeated,
                              })
                              cur = r9
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
        }
    }
  }
  Ok((fields, cur))
}

///|
/// 解析 enum 块体（输入位于起始 `{` 之后），收集 `标识符 = 取值;` 枚举值。
fn parse_enum_body(
  start : @parser_combinator.Input,
) -> Result[(Array[(String, Int)], @parser_combinator.Input), ParseError] {
  let values : Array[(String, Int)] = []
  let mut cur = start
  while true {
    cur = skip_trivia(cur)
    match cur.peek() {
      None => return Err(ParseError::at(start.pos, "enum 块未闭合"))
      Some('}') => return Ok((values, cur.advance()))
      Some(';') => cur = cur.advance()
      _ =>
        match parse_ident(cur) {
          None =>
            return Err(ParseError::at(cur.pos, "枚举值期望标识符"))
          Some((name, after)) =>
            if name == "option" || name == "reserved" {
              match skip_until(after, ';', "声明缺少结尾 ';'") {
                Ok(r) => cur = r
                Err(e) => return Err(e)
              }
            } else {
              let r1 = skip_trivia(after)
              match try_char(r1, '=') {
                None =>
                  return Err(ParseError::at(r1.pos, "枚举值期望 '='"))
                Some(r2) => {
                  let r3 = skip_trivia(r2)
                  match parse_number(r3) {
                    None =>
                      return Err(
                        ParseError::at(r3.pos, "枚举值期望整数取值"),
                      )
                    Some((v, r4)) => {
                      let r5 = skip_trivia(r4)
                      match try_char(r5, ';') {
                        None =>
                          return Err(
                            ParseError::at(r5.pos, "枚举值期望 ';'"),
                          )
                        Some(r6) => {
                          values.push((name, v))
                          cur = r6
                        }
                      }
                    }
                  }
                }
              }
            }
        }
    }
  }
  Ok((values, cur))
}

///|
/// 若 `name` 是已解析枚举之一则返回 `TEnum`，否则原样返回 `ftype`。
fn resolve_enum_ref(ftype : FieldType, enum_names : Array[String]) -> FieldType {
  match ftype {
    TMessage(n) => {
      for en in enum_names {
        if en == n {
          return TEnum(n)
        }
      }
      ftype
    }
    _ => ftype
  }
}

///|
/// 将一份 `.proto` 源码解析为模式描述（Requirement 9.5）。
///
/// 收集顶层 `message`（名称 + 简单字段）与 `enum`（名称 + 枚举值）；`syntax` /
/// `package` / `import` / `option` 语句与 `service` 块被跳过。任何语法错误返回
/// 含行列位置的 `ParseError`（Requirement 9.6）。解析后处理阶段把引用到已知枚举
/// 的字段类型由 `TMessage` 重写为 `TEnum`。
pub fn parse_proto(src : String) -> Result[Schema, ParseError] {
  let messages : Array[MessageDef] = []
  let enums : Array[EnumDef] = []
  let mut input = @parser_combinator.Input::from_string(src)
  while true {
    input = skip_trivia(input)
    if input.is_eof() {
      break
    }
    match parse_ident(input) {
      None =>
        return Err(
          ParseError::at(
            input.pos,
            "期望顶层声明（message / enum / 语句）",
          ),
        )
      Some((kw, after_kw)) =>
        if kw == "message" {
          let a1 = skip_trivia(after_kw)
          match parse_ident(a1) {
            None =>
              return Err(ParseError::at(a1.pos, "message 后期望消息名"))
            Some((name, after_name)) => {
              let before_brace = skip_trivia(after_name)
              match before_brace.peek() {
                Some('{') =>
                  match parse_message_body(before_brace.advance()) {
                    Ok((fields, after_block)) => {
                      messages.push({ name, fields })
                      input = after_block
                    }
                    Err(e) => return Err(e)
                  }
                _ =>
                  return Err(
                    ParseError::at(before_brace.pos, "消息名后期望 '{'"),
                  )
              }
            }
          }
        } else if kw == "enum" {
          let a1 = skip_trivia(after_kw)
          match parse_ident(a1) {
            None =>
              return Err(ParseError::at(a1.pos, "enum 后期望枚举名"))
            Some((name, after_name)) => {
              let before_brace = skip_trivia(after_name)
              match before_brace.peek() {
                Some('{') =>
                  match parse_enum_body(before_brace.advance()) {
                    Ok((values, after_block)) => {
                      enums.push({ name, values })
                      input = after_block
                    }
                    Err(e) => return Err(e)
                  }
                _ =>
                  return Err(
                    ParseError::at(before_brace.pos, "枚举名后期望 '{'"),
                  )
              }
            }
          }
        } else if kw == "service" {
          let a1 = skip_trivia(after_kw)
          let a2 = match parse_ident(a1) {
            Some((_, r)) => r
            None => a1
          }
          let before_brace = skip_trivia(a2)
          match before_brace.peek() {
            Some('{') =>
              match skip_block(before_brace.advance()) {
                Ok(r) => input = r
                Err(e) => return Err(e)
              }
            _ =>
              return Err(
                ParseError::at(before_brace.pos, "service 名后期望 '{'"),
              )
          }
        } else {
          // syntax / package / import / option 等：跳到 ';'。
          match skip_until(after_kw, ';', "顶层语句缺少结尾 ';'") {
            Ok(r) => input = r
            Err(e) => return Err(e)
          }
        }
    }
  }
  // 解析后处理：把引用已知枚举的字段类型由 TMessage 重写为 TEnum。
  let enum_names : Array[String] = []
  for en in enums {
    enum_names.push(en.name)
  }
  let resolved : Array[MessageDef] = []
  for m in messages {
    let new_fields : Array[FieldDef] = []
    for f in m.fields {
      new_fields.push({
        name: f.name,
        number: f.number,
        ftype: resolve_enum_ref(f.ftype, enum_names),
        repeated: f.repeated,
      })
    }
    resolved.push({ name: m.name, fields: new_fields })
  }
  Ok({ messages: resolved, enums })
}
