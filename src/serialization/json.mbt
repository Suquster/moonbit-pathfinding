// json.mbt —— proto3 JSON 映射与 base64（旗舰深化，旁路新增，R5）。
//
// 设计依据（design.md §4.7「proto3 JSON 映射」）：消息与 proto3 JSON 文本互转，
// 与二进制 wire 表示语义等价。映射规则：字段名 snake_case→camelCase；64 位整数
// 表示为 JSON 字符串（规避 IEEE-754 53 位精度损失）；`bytes` 用 base64；取默认值
// 标量省略。JSON 解析复用 `@parser_combinator.json_parser`（含行列定位），结构
// 非法返回携带定位的 `ParseError` 且不产生部分构造消息（R5.4）。
//
// 枚举以 JSON 数值表示（R5.1 显式列举的规则为 camelCase / 64 位整数为字符串 /
// bytes base64；枚举采用数值表示满足语义等价且无歧义）。
//
// base64 依 RFC 4648 标准字母表与填充实现（design.md §「算法说明」）。

// ─────────────────────────────── base64 ───────────────────────────────────

///|
/// RFC 4648 标准字母表。
let base64_alphabet : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// 将字节序列编码为 base64 文本（标准字母表 + '=' 填充）。
pub fn base64_encode(data : Bytes) -> String {
  let alpha = base64_alphabet.to_array()
  let out : Array[Char] = []
  let n = data.length()
  let mut i = 0
  while i + 3 <= n {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let b2 = data[i + 2].to_int()
    out.push(alpha[(b0 >> 2) & 0x3F])
    out.push(alpha[((b0 << 4) | (b1 >> 4)) & 0x3F])
    out.push(alpha[((b1 << 2) | (b2 >> 6)) & 0x3F])
    out.push(alpha[b2 & 0x3F])
    i = i + 3
  }
  let rem = n - i
  if rem == 1 {
    let b0 = data[i].to_int()
    out.push(alpha[(b0 >> 2) & 0x3F])
    out.push(alpha[(b0 << 4) & 0x3F])
    out.push('=')
    out.push('=')
  } else if rem == 2 {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    out.push(alpha[(b0 >> 2) & 0x3F])
    out.push(alpha[((b0 << 4) | (b1 >> 4)) & 0x3F])
    out.push(alpha[(b1 << 2) & 0x3F])
    out.push('=')
  }
  String::from_array(out)
}

///|
/// base64 字符 → 6 位值；非法字符返回 `-1`。
fn base64_value(c : Char) -> Int {
  if c >= 'A' && c <= 'Z' {
    c.to_int() - 'A'.to_int()
  } else if c >= 'a' && c <= 'z' {
    c.to_int() - 'a'.to_int() + 26
  } else if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int() + 52
  } else if c == '+' {
    62
  } else if c == '/' {
    63
  } else {
    -1
  }
}

///|
/// 将 base64 文本解码为字节序列；非法输入返回 `None`。
pub fn base64_decode(text : String) -> Bytes? {
  let chars = text.to_array()
  let vals : Array[Int] = []
  let mut k = 0
  while k < chars.length() {
    let c = chars[k]
    k = k + 1
    if c == '=' {
      break
    }
    if c == '\n' || c == '\r' || c == ' ' || c == '\t' {
      continue
    }
    let v = base64_value(c)
    if v < 0 {
      return None
    }
    vals.push(v)
  }
  let out : Array[Byte] = []
  let n = vals.length()
  let mut i = 0
  while i + 4 <= n {
    let v0 = vals[i]
    let v1 = vals[i + 1]
    let v2 = vals[i + 2]
    let v3 = vals[i + 3]
    out.push((((v0 << 2) | (v1 >> 4)) & 0xFF).to_byte())
    out.push((((v1 << 4) | (v2 >> 2)) & 0xFF).to_byte())
    out.push((((v2 << 6) | v3) & 0xFF).to_byte())
    i = i + 4
  }
  let rem = n - i
  if rem == 1 {
    return None
  } else if rem == 2 {
    let v0 = vals[i]
    let v1 = vals[i + 1]
    out.push((((v0 << 2) | (v1 >> 4)) & 0xFF).to_byte())
  } else if rem == 3 {
    let v0 = vals[i]
    let v1 = vals[i + 1]
    let v2 = vals[i + 2]
    out.push((((v0 << 2) | (v1 >> 4)) & 0xFF).to_byte())
    out.push((((v1 << 4) | (v2 >> 2)) & 0xFF).to_byte())
  }
  Some(Bytes::from_array(out))
}

// ─────────────────────────── 名称与字符串辅助 ─────────────────────────────

///|
/// snake_case → camelCase（下划线后首字母大写）。
fn snake_to_camel(s : String) -> String {
  let out : Array[Char] = []
  let mut up = false
  for c in s {
    if c == '_' {
      up = true
    } else if up {
      let ci = c.to_int()
      let uc = if ci >= 'a'.to_int() && ci <= 'z'.to_int() {
        Char::from_int(ci - 32)
      } else {
        c
      }
      out.push(uc)
      up = false
    } else {
      out.push(c)
    }
  }
  String::from_array(out)
}

///|
/// 将字符串转义并加双引号为 JSON 字符串字面量。
fn json_escape(s : String) -> String {
  let out : Array[Char] = []
  out.push('"')
  for c in s {
    if c == '"' {
      out.push('\\')
      out.push('"')
    } else if c == '\\' {
      out.push('\\')
      out.push('\\')
    } else if c == '\n' {
      out.push('\\')
      out.push('n')
    } else if c == '\r' {
      out.push('\\')
      out.push('r')
    } else if c == '\t' {
      out.push('\\')
      out.push('t')
    } else {
      out.push(c)
    }
  }
  out.push('"')
  String::from_array(out)
}

///|
/// 某 proto 类型是否为 64 位整型（JSON 表示为字符串）。
fn proto_is_64bit(t : ProtoType) -> Bool {
  match t {
    PInt64 | PUInt64 | PSInt64 | PFixed64 | PSFixed64 => true
    _ => false
  }
}

// ─────────────────────────────── JSON 编码 ─────────────────────────────────

///|
/// 将一个标量类型化取值编码为 JSON 文本片段。
fn encode_json_value(
  schema : ProtoSchema,
  t : ProtoType,
  v : TypedValue,
) -> Result[String, DecodeError] {
  match (t, v) {
    (PInt32, TInt(n)) | (PSInt32, TInt(n)) | (PSFixed32, TInt(n)) =>
      Ok(n.to_int().to_string())
    (PInt64, TInt(n)) | (PSInt64, TInt(n)) | (PSFixed64, TInt(n)) =>
      Ok(json_escape(n.to_string()))
    (PUInt32, TUInt(u)) | (PFixed32, TUInt(u)) =>
      Ok((u & 0xFFFFFFFFUL).to_string())
    (PUInt64, TUInt(u)) | (PFixed64, TUInt(u)) => Ok(json_escape(u.to_string()))
    (PBool, TBoolV(b)) => Ok(if b { "true" } else { "false" })
    (PEnum(_), TEnumV(e)) => Ok(e.to_string())
    (PFloat, TFloatV(f)) => Ok(f.to_double().to_string())
    (PDouble, TDoubleV(d)) => Ok(d.to_string())
    (PString, TStringV(s)) => Ok(json_escape(s))
    (PBytes, TBytesV(b)) => Ok(json_escape(base64_encode(b)))
    (PMessage(name), TMsg(inner)) => encode_json_message(schema, name, inner)
    _ => Err(InvalidWireType(offset=0, tag=0UL))
  }
}

///|
/// 将 map 键渲染为 JSON 对象的字符串键。
fn json_map_key_string(t : ProtoType, k : TypedValue) -> String {
  match (t, k) {
    (PString, TStringV(s)) => s
    (PBool, TBoolV(b)) => if b { "true" } else { "false" }
    (_, TInt(n)) => n.to_string()
    (_, TUInt(u)) => u.to_string()
    _ => ""
  }
}

///|
/// 将类型化消息编码为 proto3 JSON 对象文本（R5.1/5.3）。
fn encode_json_message(
  schema : ProtoSchema,
  msg_name : String,
  msg : TypedMessage,
) -> Result[String, DecodeError] {
  let pmsg = match schema.message(msg_name) {
    Some(m) => m
    None => return Err(InvalidFieldNumber(offset=0, number=0))
  }
  let parts : Array[String] = []
  for f in pmsg.fields {
    match msg.fields.get(f.number) {
      None => ()
      Some(v) =>
        match f.label {
          LRepeated(..) =>
            match v {
              TList(elems) =>
                if elems.length() > 0 {
                  let items : Array[String] = []
                  for e in elems {
                    match encode_json_value(schema, f.ptype, e) {
                      Ok(s) => items.push(s)
                      Err(er) => return Err(er)
                    }
                  }
                  parts.push(
                    json_escape(snake_to_camel(f.name)) +
                    ":[" +
                    json_join(items) +
                    "]",
                  )
                }
              _ =>
                return Err(InvalidWireType(offset=0, tag=f.number.to_uint64()))
            }
          _ =>
            if proto_is_scalar(f.ptype) && typed_is_default(v) {
              ()
            } else {
              match encode_json_value(schema, f.ptype, v) {
                Ok(s) =>
                  parts.push(json_escape(snake_to_camel(f.name)) + ":" + s)
                Err(er) => return Err(er)
              }
            }
        }
    }
  }
  for mp in pmsg.maps {
    match msg.fields.get(mp.number) {
      None => ()
      Some(TMap(mpairs)) =>
        if mpairs.length() > 0 {
          let entries : Array[String] = []
          for pair in mpairs {
            let (k, val) = pair
            let ks = json_escape(json_map_key_string(mp.key, k))
            match encode_json_value(schema, mp.value, val) {
              Ok(vs) => entries.push(ks + ":" + vs)
              Err(e) => return Err(e)
            }
          }
          parts.push(
            json_escape(snake_to_camel(mp.name)) +
            ":{" +
            json_join(entries) +
            "}",
          )
        }
      Some(_) =>
        return Err(InvalidWireType(offset=0, tag=mp.number.to_uint64()))
    }
  }
  Ok("{" + json_join(parts) + "}")
}

///|
/// 以逗号连接 JSON 片段。
///
/// 以共享高效缓冲 `@infra_text.TextBuilder` 顺序追加片段、最终一次性 `build`，
/// 消除原 `s = s + ...` 的循环内 O(n²) 字符串拼接（R1.5），对总输出长度线性。
/// 输出与逐次 `+` 拼接逐字符相等。
fn json_join(parts : Array[String]) -> String {
  let sb = @infra_text.TextBuilder::new()
  for i in 0..<parts.length() {
    if i > 0 {
      sb.push_str(",")
    }
    sb.push_str(parts[i])
  }
  sb.build()
}

///|
/// 将类型化消息编码为 proto3 JSON 文本（R5.1）。
pub fn encode_json(
  schema : ProtoSchema,
  msg_name : String,
  msg : TypedMessage,
) -> Result[String, DecodeError] {
  encode_json_message(schema, msg_name, msg)
}

// ─────────────────────────────── JSON 解码 ─────────────────────────────────

///|
/// 类型不符的 JSON 解码错误（无逐值定位，统一偏移 0）。
fn json_type_error() -> ParseError {
  ParseError::new(0, 0, 0, "JSON 值类型与 schema 不符")
}

///|
/// 由十进制字符串解析有符号 64 位整数。
fn json_parse_i64(s : String) -> Int64? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut idx = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    idx = 1
  } else if chars[0] == '+' {
    idx = 1
  }
  if idx >= chars.length() {
    return None
  }
  let mut v = 0L
  while idx < chars.length() {
    let c = chars[idx]
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
    idx = idx + 1
  }
  Some(if neg { -v } else { v })
}

///|
/// 由十进制字符串解析无符号 64 位整数。
fn json_parse_u64(s : String) -> UInt64? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut idx = 0
  if chars[0] == '+' {
    idx = 1
  }
  if idx >= chars.length() {
    return None
  }
  let mut v = 0UL
  while idx < chars.length() {
    let c = chars[idx]
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10UL + (c.to_int() - '0'.to_int()).to_uint().to_uint64()
    idx = idx + 1
  }
  Some(v)
}

///|
/// 从 JSON 值提取有符号 64 位整数（接受数值或字符串）。
fn json_to_i64(j : @parser_combinator.Json) -> Int64? {
  match j {
    @parser_combinator.JNumber(d) => Some(d.to_int64())
    @parser_combinator.JString(s) => json_parse_i64(s)
    _ => None
  }
}

///|
/// 从 JSON 值提取无符号 64 位整数（接受数值或字符串）。
fn json_to_u64(j : @parser_combinator.Json) -> UInt64? {
  match j {
    @parser_combinator.JNumber(d) => Some(d.to_int64().reinterpret_as_uint64())
    @parser_combinator.JString(s) => json_parse_u64(s)
    _ => None
  }
}

///|
/// 将一个 JSON 值按声明 `ProtoType` 反向解释为类型化取值。
fn decode_json_value(
  schema : ProtoSchema,
  t : ProtoType,
  j : @parser_combinator.Json,
) -> Result[TypedValue, ParseError] {
  match t {
    PInt32 | PSInt32 | PSFixed32 =>
      match json_to_i64(j) {
        Some(n) => Ok(TInt(n.to_int().to_int64()))
        None => Err(json_type_error())
      }
    PInt64 | PSInt64 | PSFixed64 =>
      match json_to_i64(j) {
        Some(n) => Ok(TInt(n))
        None => Err(json_type_error())
      }
    PUInt32 | PFixed32 =>
      match json_to_u64(j) {
        Some(u) => Ok(TUInt(u & 0xFFFFFFFFUL))
        None => Err(json_type_error())
      }
    PUInt64 | PFixed64 =>
      match json_to_u64(j) {
        Some(u) => Ok(TUInt(u))
        None => Err(json_type_error())
      }
    PBool =>
      match j {
        @parser_combinator.JBool(b) => Ok(TBoolV(b))
        _ => Err(json_type_error())
      }
    PEnum(_) =>
      match json_to_i64(j) {
        Some(n) => Ok(TEnumV(n.to_int()))
        None => Err(json_type_error())
      }
    PFloat =>
      match j {
        @parser_combinator.JNumber(d) => Ok(TFloatV(d.to_float()))
        _ => Err(json_type_error())
      }
    PDouble =>
      match j {
        @parser_combinator.JNumber(d) => Ok(TDoubleV(d))
        _ => Err(json_type_error())
      }
    PString =>
      match j {
        @parser_combinator.JString(s) => Ok(TStringV(s))
        _ => Err(json_type_error())
      }
    PBytes =>
      match j {
        @parser_combinator.JString(s) =>
          match base64_decode(s) {
            Some(b) => Ok(TBytesV(b))
            None => Err(json_type_error())
          }
        _ => Err(json_type_error())
      }
    PMessage(name) =>
      match j {
        @parser_combinator.JObject(_) =>
          match decode_json_message(schema, name, j) {
            Ok(m) => Ok(TMsg(m))
            Err(e) => Err(e)
          }
        _ => Err(json_type_error())
      }
  }
}

///|
/// 在 JSON 对象成员中按 camelCase 键或原名查找取值。
fn json_find_member(
  members : Array[(String, @parser_combinator.Json)],
  camel : String,
  orig : String,
) -> @parser_combinator.Json? {
  for m in members {
    let (k, v) = m
    if k == camel || k == orig {
      return Some(v)
    }
  }
  None
}

///|
/// 由 JSON 对象字符串键解析 map 键为类型化取值。
fn json_parse_map_key(t : ProtoType, ks : String) -> TypedValue? {
  match t {
    PString => Some(TStringV(ks))
    PBool =>
      if ks == "true" {
        Some(TBoolV(true))
      } else if ks == "false" {
        Some(TBoolV(false))
      } else {
        None
      }
    PInt32 | PSInt32 | PSFixed32 =>
      match json_parse_i64(ks) {
        Some(n) => Some(TInt(n.to_int().to_int64()))
        None => None
      }
    PInt64 | PSInt64 | PSFixed64 =>
      match json_parse_i64(ks) {
        Some(n) => Some(TInt(n))
        None => None
      }
    PUInt32 | PFixed32 =>
      match json_parse_u64(ks) {
        Some(u) => Some(TUInt(u & 0xFFFFFFFFUL))
        None => None
      }
    PUInt64 | PFixed64 =>
      match json_parse_u64(ks) {
        Some(u) => Some(TUInt(u))
        None => None
      }
    _ => None
  }
}

///|
/// 将一个 JSON 对象按 schema 解释为类型化消息。
fn decode_json_message(
  schema : ProtoSchema,
  msg_name : String,
  j : @parser_combinator.Json,
) -> Result[TypedMessage, ParseError] {
  let pmsg = match schema.message(msg_name) {
    Some(m) => m
    None =>
      return Err(ParseError::new(0, 0, 0, "schema 中无消息 " + msg_name))
  }
  match j {
    @parser_combinator.JObject(members) => {
      let fields : Map[Int, TypedValue] = {}
      for f in pmsg.fields {
        let camel = snake_to_camel(f.name)
        match json_find_member(members, camel, f.name) {
          None => ()
          Some(jv) =>
            match f.label {
              LRepeated(..) =>
                match jv {
                  @parser_combinator.JArray(elems) => {
                    let arr : Array[TypedValue] = []
                    for e in elems {
                      match decode_json_value(schema, f.ptype, e) {
                        Ok(tv) => arr.push(tv)
                        Err(er) => return Err(er)
                      }
                    }
                    if arr.length() > 0 {
                      fields[f.number] = TList(arr)
                    }
                  }
                  _ => return Err(json_type_error())
                }
              _ =>
                match decode_json_value(schema, f.ptype, jv) {
                  Ok(tv) =>
                    if not(proto_is_scalar(f.ptype) && typed_is_default(tv)) {
                      fields[f.number] = tv
                    }
                  Err(er) => return Err(er)
                }
            }
        }
      }
      for mp in pmsg.maps {
        let camel = snake_to_camel(mp.name)
        match json_find_member(members, camel, mp.name) {
          None => ()
          Some(@parser_combinator.JObject(entries)) => {
            let pairs : Array[(TypedValue, TypedValue)] = []
            for entry in entries {
              let (ks, vj) = entry
              let k = match json_parse_map_key(mp.key, ks) {
                Some(tv) => tv
                None => return Err(json_type_error())
              }
              let val = match decode_json_value(schema, mp.value, vj) {
                Ok(tv) => tv
                Err(e) => return Err(e)
              }
              pairs.push((k, val))
            }
            if pairs.length() > 0 {
              fields[mp.number] = TMap(pairs)
            }
          }
          Some(_) => return Err(json_type_error())
        }
      }
      Ok({ fields, unknown: [] })
    }
    _ => Err(ParseError::new(0, 0, 0, "JSON 消息期望对象"))
  }
}

///|
/// 从 proto3 JSON 文本解码类型化消息（R5.2/5.4）。
///
/// JSON 解析复用 `@parser_combinator.json_parser`（含行列定位）；结构非法返回
/// 携带定位的 `ParseError` 且不产生部分构造消息。
pub fn decode_json(
  schema : ProtoSchema,
  msg_name : String,
  json : String,
) -> Result[TypedMessage, ParseError] {
  match @parser_combinator.json_parser().parse_string(json) {
    Ok(j, _) => decode_json_message(schema, msg_name, j)
    Fail(pos, ..) => Err(ParseError::at(pos, "JSON 解析失败"))
  }
}
