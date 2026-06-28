// proto_grammar.mbt —— 完整 proto3 文法解析与规范打印（旗舰深化，旁路新增，R3）。
//
// 设计依据（design.md §4.2「完整 proto3 文法解析 parse_proto_full」）：既有
// `parse_proto`（proto_parser.mbt）冻结（骨架级）。本文件新增 `parse_proto_full`，
// 在 `@parser_combinator` 的 `Input`/`Pos`/`ParseResult` 模型之上（R3.8）覆盖完整
// proto3 文法：`message`/`enum`/全部标量类型/`oneof`/`map<K,V>`/嵌套类型（以限定名
// 登记）/`reserved`/字段选项 `[packed=...]`/`[deprecated=...]`。配套规范打印
// `print_proto` 支撑解析 round-trip（Property 11）。
//
// 复用：标识符/数字/空白与注释的终结符解析复用 proto_parser.mbt 的同包私有原语
// （`skip_trivia`/`parse_ident`/`parse_number`/`try_char`/`skip_until`/`skip_block`/
// `is_ident_char`），它们均构建于 `@parser_combinator` 的 `Input`/`Pos` 模型。
//
// 语法错误返回携带行列的 `ParseError`（复用既有 `ParseError::at`）且不构造
// `ProtoSchema`（R3.7）。

// ─────────────────────────────── 终结符辅助 ────────────────────────────────

///|
/// 期望并消费一个字符，失败返回携带定位的解析错误。
fn pg_expect_char(
  input : @parser_combinator.Input,
  c : Char,
  msg : String,
) -> Result[@parser_combinator.Input, ParseError] {
  match try_char(input, c) {
    Some(next) => Ok(next)
    None => Err(ParseError::at(input.pos, msg))
  }
}

///|
/// 期望并消费一个标识符。
fn pg_expect_ident(
  input : @parser_combinator.Input,
  msg : String,
) -> Result[(String, @parser_combinator.Input), ParseError] {
  match parse_ident(input) {
    Some(p) => Ok(p)
    None => Err(ParseError::at(input.pos, msg))
  }
}

///|
/// 期望并消费一个整数。
fn pg_expect_number(
  input : @parser_combinator.Input,
  msg : String,
) -> Result[(Int, @parser_combinator.Input), ParseError] {
  match parse_number(input) {
    Some(p) => Ok(p)
    None => Err(ParseError::at(input.pos, msg))
  }
}

///|
/// 将 proto3 标量关键字映射为 `ProtoType`；非标量关键字返回 `None`。
fn proto_type_of_keyword(name : String) -> ProtoType? {
  match name {
    "int32" => Some(PInt32)
    "int64" => Some(PInt64)
    "uint32" => Some(PUInt32)
    "uint64" => Some(PUInt64)
    "sint32" => Some(PSInt32)
    "sint64" => Some(PSInt64)
    "fixed32" => Some(PFixed32)
    "fixed64" => Some(PFixed64)
    "sfixed32" => Some(PSFixed32)
    "sfixed64" => Some(PSFixed64)
    "float" => Some(PFloat)
    "double" => Some(PDouble)
    "bool" => Some(PBool)
    "string" => Some(PString)
    "bytes" => Some(PBytes)
    _ => None
  }
}

///|
/// 解析一个以双引号包裹的字符串字面量（无转义处理）；未闭合返回 `None`。
fn pg_parse_string_lit(
  input : @parser_combinator.Input,
) -> (String, @parser_combinator.Input)? {
  match input.peek() {
    Some('"') => {
      let mut cur = input.advance()
      // 以 `@infra_text.TextBuilder` 顺序追加字符，消除原 `s = s + ...` 的循环内
      // O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
      let sb = @infra_text.TextBuilder::new()
      while true {
        match cur.peek() {
          Some('"') => {
            cur = cur.advance()
            break
          }
          Some(c) => {
            sb.push_char(c)
            cur = cur.advance()
          }
          None => return None
        }
      }
      Some((sb.build(), cur))
    }
    _ => None
  }
}

///|
/// 解析一个选项取值：双引号字符串、或由标识符字符/`-`/`+` 组成的裸记号。
fn pg_parse_option_value(
  input : @parser_combinator.Input,
) -> (String, @parser_combinator.Input)? {
  match input.peek() {
    Some('"') => pg_parse_string_lit(input)
    Some(_) => {
      let mut cur = input
      // 以 `@infra_text.TextBuilder` 顺序追加字符，消除原 `s = s + ...` 的循环内
      // O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
      let sb = @infra_text.TextBuilder::new()
      let mut go = true
      while go {
        match cur.peek() {
          Some(c) =>
            if is_ident_char(c) || c == '-' || c == '+' {
              sb.push_char(c)
              cur = cur.advance()
            } else {
              go = false
            }
          None => go = false
        }
      }
      let s = sb.build()
      if s == "" {
        None
      } else {
        Some((s, cur))
      }
    }
    None => None
  }
}

///|
/// 解析可选的字段选项块 `[name=value, ...]`。
///
/// `packed` 选项被提取为 `packed_override`（不进 options 列表）；其余进 options。
/// 输入应已 skip_trivia 至潜在的 `[`。
fn pg_parse_field_options(
  input : @parser_combinator.Input,
) -> Result[(Array[FieldOption], Bool?, @parser_combinator.Input), ParseError] {
  match input.peek() {
    Some('[') => {
      let mut cur = input.advance()
      let opts : Array[FieldOption] = []
      let mut packed_override : Bool? = None
      let mut done = false
      while !done {
        cur = skip_trivia(cur)
        let (oname, r1) = match pg_expect_ident(cur, "选项期望名称") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        let r2 = skip_trivia(r1)
        let r3 = match pg_expect_char(r2, '=', "选项期望 '='") {
          Ok(c) => c
          Err(e) => return Err(e)
        }
        let r4 = skip_trivia(r3)
        let (oval, r5) = match pg_parse_option_value(r4) {
          Some(p) => p
          None => return Err(ParseError::at(r4.pos, "选项期望取值"))
        }
        if oname == "packed" {
          packed_override = Some(oval == "true")
        } else {
          opts.push({ name: oname, value: oval })
        }
        let r6 = skip_trivia(r5)
        match r6.peek() {
          Some(',') => cur = r6.advance()
          Some(']') => {
            cur = r6.advance()
            done = true
          }
          _ => return Err(ParseError::at(r6.pos, "选项期望 ',' 或 ']'"))
        }
      }
      Ok((opts, packed_override, cur))
    }
    _ => Ok(([], None, input))
  }
}

// ─────────────────────────────── 块解析 ───────────────────────────────────

///|
/// 解析 enum 块（输入位于 `enum` 关键字之后），返回 `(块后输入, 限定名)`。
fn pg_parse_enum(
  after_kw : @parser_combinator.Input,
  prefix : String,
  enums : Array[EnumDef],
) -> Result[(@parser_combinator.Input, String), ParseError] {
  let a1 = skip_trivia(after_kw)
  let (name, after_name) = match
    pg_expect_ident(a1, "enum 后期望枚举名") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let qualified = if prefix == "" { name } else { prefix + "." + name }
  let bb = skip_trivia(after_name)
  let mut cur = match pg_expect_char(bb, '{', "枚举名后期望 '{'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let values : Array[(String, Int)] = []
  let mut done = false
  while !done {
    cur = skip_trivia(cur)
    match cur.peek() {
      None => return Err(ParseError::at(cur.pos, "enum 块未闭合"))
      Some('}') => {
        cur = cur.advance()
        done = true
      }
      Some(';') => cur = cur.advance()
      _ => {
        let (vname, after_v) = match
          pg_expect_ident(cur, "枚举值期望标识符") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        if vname == "option" || vname == "reserved" {
          match skip_until(after_v, ';', "声明缺少结尾 ';'") {
            Ok(r) => cur = r
            Err(e) => return Err(e)
          }
        } else {
          let r1 = skip_trivia(after_v)
          let r2 = match pg_expect_char(r1, '=', "枚举值期望 '='") {
            Ok(c) => c
            Err(e) => return Err(e)
          }
          let r3 = skip_trivia(r2)
          let (v, r4) = match
            pg_expect_number(r3, "枚举值期望整数取值") {
            Ok(p) => p
            Err(e) => return Err(e)
          }
          let r5 = skip_trivia(r4)
          let (_, _, r6) = match pg_parse_field_options(r5) {
            Ok(t) => t
            Err(e) => return Err(e)
          }
          let r7 = skip_trivia(r6)
          let r8 = match pg_expect_char(r7, ';', "枚举值期望 ';'") {
            Ok(c) => c
            Err(e) => return Err(e)
          }
          values.push((vname, v))
          cur = r8
        }
      }
    }
  }
  enums.push({ name: qualified, values })
  Ok((cur, qualified))
}

///|
/// 解析 reserved 声明的字段号 / 范围列表（输入位于 `reserved` 之后）。
fn pg_parse_reserved_numbers(
  after_kw : @parser_combinator.Input,
  reserved_numbers : Array[ReservedRange],
) -> Result[@parser_combinator.Input, ParseError] {
  let mut rc = after_kw
  let mut done = false
  while !done {
    rc = skip_trivia(rc)
    let (lo, r1) = match pg_expect_number(rc, "reserved 期望字段号") {
      Ok(p) => p
      Err(e) => return Err(e)
    }
    let r2 = skip_trivia(r1)
    let (hi, r3) = match parse_ident(r2) {
      Some(("to", rr)) => {
        let rr1 = skip_trivia(rr)
        match pg_expect_number(rr1, "reserved 范围期望上界") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
      }
      _ => (lo, r2)
    }
    reserved_numbers.push({ lo, hi })
    let r4 = skip_trivia(r3)
    match r4.peek() {
      Some(',') => rc = r4.advance()
      Some(';') => {
        rc = r4.advance()
        done = true
      }
      _ => return Err(ParseError::at(r4.pos, "reserved 期望 ',' 或 ';'"))
    }
  }
  Ok(rc)
}

///|
/// 解析 reserved 声明的字段名列表（输入位于首个 `"` 处）。
fn pg_parse_reserved_names(
  start : @parser_combinator.Input,
  reserved_names : Array[String],
) -> Result[@parser_combinator.Input, ParseError] {
  let mut rc = start
  let mut done = false
  while !done {
    rc = skip_trivia(rc)
    let (nm, r1) = match pg_parse_string_lit(rc) {
      Some(p) => p
      None => return Err(ParseError::at(rc.pos, "reserved 期望字符串名"))
    }
    reserved_names.push(nm)
    let r2 = skip_trivia(r1)
    match r2.peek() {
      Some(',') => rc = r2.advance()
      Some(';') => {
        rc = r2.advance()
        done = true
      }
      _ => return Err(ParseError::at(r2.pos, "reserved 期望 ',' 或 ';'"))
    }
  }
  Ok(rc)
}

///|
/// 解析 message 块（输入位于 `message` 关键字之后），返回 `(块后输入, 限定名)`。
/// 嵌套 message/enum 递归解析并以限定名登记到顶层 `messages`/`enums`（R3.4）。
fn pg_parse_message(
  after_kw : @parser_combinator.Input,
  prefix : String,
  messages : Array[ProtoMessage],
  enums : Array[EnumDef],
) -> Result[(@parser_combinator.Input, String), ParseError] {
  let a1 = skip_trivia(after_kw)
  let (name, after_name) = match
    pg_expect_ident(a1, "message 后期望消息名") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let qualified = if prefix == "" { name } else { prefix + "." + name }
  let bb = skip_trivia(after_name)
  let mut cur = match pg_expect_char(bb, '{', "消息名后期望 '{'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let fields : Array[ProtoField] = []
  let maps : Array[MapEntry] = []
  let oneofs : Array[OneofDef] = []
  let reserved_numbers : Array[ReservedRange] = []
  let reserved_names : Array[String] = []
  let nested_messages : Array[String] = []
  let nested_enums : Array[String] = []
  let mut done = false
  while !done {
    cur = skip_trivia(cur)
    match cur.peek() {
      None => return Err(ParseError::at(cur.pos, "message 块未闭合"))
      Some('}') => {
        cur = cur.advance()
        done = true
      }
      Some(';') => cur = cur.advance()
      _ => {
        let (tok, after_tok) = match
          pg_expect_ident(cur, "成员期望标识符") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        if tok == "message" {
          match pg_parse_message(after_tok, qualified, messages, enums) {
            Ok((next, qname)) => {
              nested_messages.push(qname)
              cur = next
            }
            Err(e) => return Err(e)
          }
        } else if tok == "enum" {
          match pg_parse_enum(after_tok, qualified, enums) {
            Ok((next, qname)) => {
              nested_enums.push(qname)
              cur = next
            }
            Err(e) => return Err(e)
          }
        } else if tok == "oneof" {
          match pg_parse_oneof(after_tok, fields, oneofs) {
            Ok(next) => cur = next
            Err(e) => return Err(e)
          }
        } else if tok == "reserved" {
          let res = skip_trivia(after_tok)
          match res.peek() {
            Some('"') =>
              match pg_parse_reserved_names(res, reserved_names) {
                Ok(next) => cur = next
                Err(e) => return Err(e)
              }
            _ =>
              match pg_parse_reserved_numbers(res, reserved_numbers) {
                Ok(next) => cur = next
                Err(e) => return Err(e)
              }
          }
        } else if tok == "option" || tok == "extensions" {
          match skip_until(after_tok, ';', "声明缺少结尾 ';'") {
            Ok(next) => cur = next
            Err(e) => return Err(e)
          }
        } else {
          let look = skip_trivia(after_tok)
          if tok == "map" && look.peek() == Some('<') {
            match pg_parse_map_field(look, maps) {
              Ok(next) => cur = next
              Err(e) => return Err(e)
            }
          } else {
            match pg_parse_field(tok, after_tok, fields) {
              Ok(next) => cur = next
              Err(e) => return Err(e)
            }
          }
        }
      }
    }
  }
  messages.push({
    name: qualified,
    fields,
    maps,
    oneofs,
    reserved_numbers,
    reserved_names,
    nested_messages,
    nested_enums,
  })
  Ok((cur, qualified))
}

///|
/// 解析 oneof 块（输入位于 `oneof` 关键字之后）。成员以 `LOneof` 标签入 `fields`，
/// 组信息入 `oneofs`。
fn pg_parse_oneof(
  after_kw : @parser_combinator.Input,
  fields : Array[ProtoField],
  oneofs : Array[OneofDef],
) -> Result[@parser_combinator.Input, ParseError] {
  let o1 = skip_trivia(after_kw)
  let (oneof_name, o2) = match pg_expect_ident(o1, "oneof 后期望名称") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let o3 = skip_trivia(o2)
  let mut oc = match pg_expect_char(o3, '{', "oneof 名后期望 '{'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let members : Array[Int] = []
  let mut done = false
  while !done {
    oc = skip_trivia(oc)
    match oc.peek() {
      None => return Err(ParseError::at(oc.pos, "oneof 块未闭合"))
      Some('}') => {
        oc = oc.advance()
        done = true
      }
      Some(';') => oc = oc.advance()
      _ => {
        let (tname, t1) = match
          pg_expect_ident(oc, "oneof 成员期望类型") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        let mt = skip_trivia(t1)
        let (mname, t2) = match
          pg_expect_ident(mt, "oneof 成员期望字段名") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        let t3 = skip_trivia(t2)
        let t4 = match pg_expect_char(t3, '=', "oneof 成员期望 '='") {
          Ok(c) => c
          Err(e) => return Err(e)
        }
        let t5 = skip_trivia(t4)
        let (mnum, t6) = match
          pg_expect_number(t5, "oneof 成员期望字段号") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        let t7 = skip_trivia(t6)
        let (mopts, _, t8) = match pg_parse_field_options(t7) {
          Ok(t) => t
          Err(e) => return Err(e)
        }
        let t9 = skip_trivia(t8)
        let t10 = match pg_expect_char(t9, ';', "oneof 成员期望 ';'") {
          Ok(c) => c
          Err(e) => return Err(e)
        }
        let mptype = match proto_type_of_keyword(tname) {
          Some(t) => t
          None => PMessage(tname)
        }
        fields.push({
          name: mname,
          number: mnum,
          ptype: mptype,
          label: LOneof(group=oneof_name),
          options: mopts,
        })
        members.push(mnum)
        oc = t10
      }
    }
  }
  oneofs.push({ name: oneof_name, members })
  Ok(oc)
}

///|
/// 解析 map 字段（输入位于 `<` 处）。
fn pg_parse_map_field(
  at_lt : @parser_combinator.Input,
  maps : Array[MapEntry],
) -> Result[@parser_combinator.Input, ParseError] {
  let m1 = at_lt.advance() // 消费 '<'
  let m2 = skip_trivia(m1)
  let (kname, m3) = match pg_expect_ident(m2, "map 期望键类型") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let m4 = skip_trivia(m3)
  let m5 = match pg_expect_char(m4, ',', "map 键类型后期望 ','") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let m6 = skip_trivia(m5)
  let (vname, m7) = match pg_expect_ident(m6, "map 期望值类型") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let m8 = skip_trivia(m7)
  let m9 = match pg_expect_char(m8, '>', "map 值类型后期望 '>'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let m10 = skip_trivia(m9)
  let (fname, m11) = match pg_expect_ident(m10, "map 期望字段名") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let m12 = skip_trivia(m11)
  let m13 = match pg_expect_char(m12, '=', "map 字段期望 '='") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let m14 = skip_trivia(m13)
  let (num, m15) = match pg_expect_number(m14, "map 字段期望字段号") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let m16 = skip_trivia(m15)
  let (_, _, m17) = match pg_parse_field_options(m16) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let m18 = skip_trivia(m17)
  let m19 = match pg_expect_char(m18, ';', "map 字段期望 ';'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let key_type = match proto_type_of_keyword(kname) {
    Some(t) => t
    None => PMessage(kname)
  }
  let value_type = match proto_type_of_keyword(vname) {
    Some(t) => t
    None => PMessage(vname)
  }
  maps.push({ name: fname, number: num, key: key_type, value: value_type })
  Ok(m19)
}

///|
/// 解析一条普通字段（`tok` 已读入，是 label 或类型记号）。
fn pg_parse_field(
  tok : String,
  after_tok : @parser_combinator.Input,
  fields : Array[ProtoField],
) -> Result[@parser_combinator.Input, ParseError] {
  let mut repeated = false
  let mut type_token = tok
  let mut tail = after_tok
  if tok == "repeated" ||
    tok == "optional" ||
    tok == "singular" ||
    tok == "required" {
    repeated = tok == "repeated"
    let a = skip_trivia(after_tok)
    match pg_expect_ident(a, "期望字段类型") {
      Ok((t, r)) => {
        type_token = t
        tail = r
      }
      Err(e) => return Err(e)
    }
  }
  let after_type = skip_trivia(tail)
  let (fname, r1) = match pg_expect_ident(after_type, "期望字段名") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let r2 = skip_trivia(r1)
  let r3 = match pg_expect_char(r2, '=', "字段期望 '='") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let r4 = skip_trivia(r3)
  let (num, r5) = match pg_expect_number(r4, "字段期望字段号") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let r6 = skip_trivia(r5)
  let (opts, packed_override, r7) = match pg_parse_field_options(r6) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let r8 = skip_trivia(r7)
  let r9 = match pg_expect_char(r8, ';', "字段期望 ';'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let ptype = match proto_type_of_keyword(type_token) {
    Some(t) => t
    None => PMessage(type_token)
  }
  let label = if repeated {
    let default_packed = proto_is_numeric_scalar(ptype)
    let packed = match packed_override {
      Some(b) => b
      None => default_packed
    }
    LRepeated(packed~)
  } else {
    LSingular
  }
  fields.push({ name: fname, number: num, ptype, label, options: opts })
  Ok(r9)
}

// ─────────────────────────────── 顶层入口 ─────────────────────────────────

///|
/// 名称是否为嵌套限定名（含 '.'）。
fn pg_is_nested_name(name : String) -> Bool {
  name.contains(".")
}

///|
/// 名称是否在数组中。
fn pg_name_in(names : Array[String], n : String) -> Bool {
  for x in names {
    if x == n {
      return true
    }
  }
  false
}

///|
/// 解析后处理：把引用到已知枚举名的 `PMessage` 重写为 `PEnum`。
fn pg_resolve_enums(schema : ProtoSchema) -> ProtoSchema {
  let enum_names : Array[String] = []
  for e in schema.enums {
    enum_names.push(e.name)
  }
  let resolve = fn(t : ProtoType) -> ProtoType {
    match t {
      PMessage(n) =>
        if pg_name_in(enum_names, n) {
          PEnum(n)
        } else {
          PMessage(n)
        }
      other => other
    }
  }
  let new_messages : Array[ProtoMessage] = []
  for m in schema.messages {
    let nf : Array[ProtoField] = []
    for f in m.fields {
      nf.push({
        name: f.name,
        number: f.number,
        ptype: resolve(f.ptype),
        label: f.label,
        options: f.options,
      })
    }
    let nmaps : Array[MapEntry] = []
    for mp in m.maps {
      nmaps.push({
        name: mp.name,
        number: mp.number,
        key: mp.key,
        value: resolve(mp.value),
      })
    }
    new_messages.push({
      name: m.name,
      fields: nf,
      maps: nmaps,
      oneofs: m.oneofs,
      reserved_numbers: m.reserved_numbers,
      reserved_names: m.reserved_names,
      nested_messages: m.nested_messages,
      nested_enums: m.nested_enums,
    })
  }
  { messages: new_messages, enums: schema.enums }
}

///|
/// 完整 proto3 文法解析（R3.1–3.8）。语法错误返回携带行列的 `ParseError`
/// 且不构造 `ProtoSchema`（R3.7）。
pub fn parse_proto_full(src : String) -> Result[ProtoSchema, ParseError] {
  let messages : Array[ProtoMessage] = []
  let enums : Array[EnumDef] = []
  let mut input = @parser_combinator.Input::from_string(src)
  while true {
    input = skip_trivia(input)
    if input.is_eof() {
      break
    }
    let (kw, after_kw) = match
      pg_expect_ident(input, "期望顶层声明（message / enum / 语句）") {
      Ok(p) => p
      Err(e) => return Err(e)
    }
    if kw == "message" {
      match pg_parse_message(after_kw, "", messages, enums) {
        Ok((next, _)) => input = next
        Err(e) => return Err(e)
      }
    } else if kw == "enum" {
      match pg_parse_enum(after_kw, "", enums) {
        Ok((next, _)) => input = next
        Err(e) => return Err(e)
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
  Ok(pg_resolve_enums({ messages, enums }))
}

// ─────────────────────────────── 规范打印 ─────────────────────────────────

///|
/// 由缩进层级产出缩进字符串（每层两空格）。
///
/// 以 `@infra_text.TextBuilder` 顺序追加，消除原 `s = s + "  "` 的循环内 O(n²)
/// 字符串拼接（R1.5）；逐字符等价于原实现。
fn pg_indent(level : Int) -> String {
  let sb = @infra_text.TextBuilder::new()
  for _i in 0..<level {
    sb.push_str("  ")
  }
  sb.build()
}

///|
/// 取限定名的最末段（局部名）。
fn pg_simple_name(qualified : String) -> String {
  let chars = qualified.to_array()
  let mut last = 0
  for i in 0..<chars.length() {
    if chars[i] == '.' {
      last = i + 1
    }
  }
  let out : Array[Char] = []
  for i in last..<chars.length() {
    out.push(chars[i])
  }
  String::from_array(out)
}

///|
/// 将 `ProtoType` 打印为规范关键字 / 引用名。
fn pg_type_name(t : ProtoType) -> String {
  match t {
    PInt32 => "int32"
    PInt64 => "int64"
    PUInt32 => "uint32"
    PUInt64 => "uint64"
    PSInt32 => "sint32"
    PSInt64 => "sint64"
    PFixed32 => "fixed32"
    PFixed64 => "fixed64"
    PSFixed32 => "sfixed32"
    PSFixed64 => "sfixed64"
    PFloat => "float"
    PDouble => "double"
    PBool => "bool"
    PString => "string"
    PBytes => "bytes"
    PMessage(n) => pg_simple_name(n)
    PEnum(n) => pg_simple_name(n)
  }
}

///|
/// 用分隔符连接字符串数组。
///
/// 以 `@infra_text.TextBuilder` 顺序追加片段，消除原 `s = s + ...` 的循环内
/// O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
fn pg_join(parts : Array[String], sep : String) -> String {
  let sb = @infra_text.TextBuilder::new()
  for i in 0..<parts.length() {
    if i > 0 {
      sb.push_str(sep)
    }
    sb.push_str(parts[i])
  }
  sb.build()
}

///|
/// 打印字段的选项后缀（含 packed 覆盖与其他选项）。
fn pg_print_options(f : ProtoField) -> String {
  let opts : Array[String] = []
  match f.label {
    LRepeated(packed~) => {
      let default_packed = proto_is_numeric_scalar(f.ptype)
      if packed != default_packed {
        opts.push("packed=" + (if packed { "true" } else { "false" }))
      }
    }
    _ => ()
  }
  for o in f.options {
    opts.push(o.name + "=" + o.value)
  }
  if opts.length() > 0 {
    " [" + pg_join(opts, ", ") + "]"
  } else {
    ""
  }
}

///|
/// 打印一条普通字段（含 repeated 标签与选项）。
///
/// 以 `@infra_text.TextBuilder` 顺序追加片段，避免超过 3 次顺序 `+`（R1.5 /
/// 质量门禁缓冲方案约定）；逐字符等价于原实现。
fn pg_print_field(f : ProtoField) -> String {
  let label = match f.label {
    LRepeated(..) => "repeated "
    _ => ""
  }
  let out = @infra_text.TextBuilder::new()
  out.push_str(label)
  out.push_str(pg_type_name(f.ptype))
  out.push_str(" ")
  out.push_str(f.name)
  out.push_str(" = ")
  out.push_str(f.number.to_string())
  out.push_str(pg_print_options(f))
  out.push_str(";")
  out.build()
}

///|
/// 打印一个 oneof 成员（无标签）。
///
/// 以 `@infra_text.TextBuilder` 顺序追加片段，避免超过 3 次顺序 `+`（R1.5 /
/// 质量门禁缓冲方案约定）；逐字符等价于原实现。
fn pg_print_oneof_member(f : ProtoField) -> String {
  let out = @infra_text.TextBuilder::new()
  out.push_str(pg_type_name(f.ptype))
  out.push_str(" ")
  out.push_str(f.name)
  out.push_str(" = ")
  out.push_str(f.number.to_string())
  out.push_str(pg_print_options(f))
  out.push_str(";")
  out.build()
}

///|
/// 在消息中按字段号查找字段定义（用于 oneof 成员打印）。
fn pg_find_field_by_number(m : ProtoMessage, number : Int) -> ProtoField? {
  for f in m.fields {
    if f.number == number {
      return Some(f)
    }
  }
  None
}

///|
/// 递归打印一个消息定义。
///
/// 以 `@infra_text.TextBuilder` 顺序追加片段，消除原 `out = out + ...` 的循环内
/// O(n²) 字符串拼接（R1.5），对总输出长度线性；逐字符等价于原实现。
fn pg_print_message(
  schema : ProtoSchema,
  m : ProtoMessage,
  level : Int,
) -> String {
  let pad = pg_indent(level)
  let pad2 = pg_indent(level + 1)
  let out = @infra_text.TextBuilder::new()
  out.push_str(pad)
  out.push_str("message ")
  out.push_str(pg_simple_name(m.name))
  out.push_str(" {\n")
  // reserved 字段号 / 范围。
  if m.reserved_numbers.length() > 0 {
    let parts : Array[String] = []
    for r in m.reserved_numbers {
      if r.lo == r.hi {
        parts.push(r.lo.to_string())
      } else {
        parts.push(r.lo.to_string() + " to " + r.hi.to_string())
      }
    }
    out.push_str(pad2)
    out.push_str("reserved ")
    out.push_str(pg_join(parts, ", "))
    out.push_str(";\n")
  }
  // reserved 名。
  if m.reserved_names.length() > 0 {
    let parts : Array[String] = []
    for nm in m.reserved_names {
      parts.push("\"" + nm + "\"")
    }
    out.push_str(pad2)
    out.push_str("reserved ")
    out.push_str(pg_join(parts, ", "))
    out.push_str(";\n")
  }
  // 非 oneof 字段。
  for f in m.fields {
    match f.label {
      LOneof(..) => ()
      _ => {
        out.push_str(pad2)
        out.push_str(pg_print_field(f))
        out.push_str("\n")
      }
    }
  }
  // oneof 块。
  for o in m.oneofs {
    out.push_str(pad2)
    out.push_str("oneof ")
    out.push_str(o.name)
    out.push_str(" {\n")
    let pad3 = pg_indent(level + 2)
    for num in o.members {
      match pg_find_field_by_number(m, num) {
        Some(f) => {
          out.push_str(pad3)
          out.push_str(pg_print_oneof_member(f))
          out.push_str("\n")
        }
        None => ()
      }
    }
    out.push_str(pad2)
    out.push_str("}\n")
  }
  // map 字段。
  for mp in m.maps {
    out.push_str(pad2)
    out.push_str("map<")
    out.push_str(pg_type_name(mp.key))
    out.push_str(", ")
    out.push_str(pg_type_name(mp.value))
    out.push_str("> ")
    out.push_str(mp.name)
    out.push_str(" = ")
    out.push_str(mp.number.to_string())
    out.push_str(";\n")
  }
  // 嵌套类型。
  for nm_name in m.nested_messages {
    match schema.message(nm_name) {
      Some(nm) => out.push_str(pg_print_message(schema, nm, level + 1))
      None => ()
    }
  }
  for ne_name in m.nested_enums {
    match schema.enum_def(ne_name) {
      Some(ne) => out.push_str(pg_print_enum(ne, level + 1))
      None => ()
    }
  }
  out.push_str(pad)
  out.push_str("}\n")
  out.build()
}

///|
/// 递归打印一个枚举定义。
///
/// 以 `@infra_text.TextBuilder` 顺序追加片段，消除原 `out = out + ...` 的循环内
/// O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
fn pg_print_enum(e : EnumDef, level : Int) -> String {
  let pad = pg_indent(level)
  let pad2 = pg_indent(level + 1)
  let out = @infra_text.TextBuilder::new()
  out.push_str(pad)
  out.push_str("enum ")
  out.push_str(pg_simple_name(e.name))
  out.push_str(" {\n")
  for pair in e.values {
    let (name, v) = pair
    out.push_str(pad2)
    out.push_str(name)
    out.push_str(" = ")
    out.push_str(v.to_string())
    out.push_str(";\n")
  }
  out.push_str(pad)
  out.push_str("}\n")
  out.build()
}

///|
/// 规范化打印富模式为 `.proto` 源码（供解析 round-trip 与调试，Property 11）。
///
/// 以确定性形态输出：顶层消息/枚举按登记顺序、固定两空格缩进、标量类型用规范
/// 关键字；嵌套类型在其父块内递归打印。`parse_proto_full(print_proto(s))` 与 `s`
/// 等价。
pub fn print_proto(schema : ProtoSchema) -> String {
  // 以 `@infra_text.TextBuilder` 顺序追加片段，消除原 `out = out + ...` 的循环内
  // O(n²) 字符串拼接（R1.5）；逐字符等价于原实现。
  let out = @infra_text.TextBuilder::new()
  out.push_str("syntax = \"proto3\";\n")
  for m in schema.messages {
    if !pg_is_nested_name(m.name) {
      out.push_str(pg_print_message(schema, m, 0))
    }
  }
  for e in schema.enums {
    if !pg_is_nested_name(e.name) {
      out.push_str(pg_print_enum(e, 0))
    }
  }
  out.build()
}
