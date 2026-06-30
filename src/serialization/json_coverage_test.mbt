// json_coverage_test.mbt —— proto3 JSON 映射（json.mbt）的错误/边界分支覆盖。
//
// 既有 json_test.mbt 覆盖了 happy-path（camelCase、64 位整数字符串化、bytes
// base64、非法 JSON）；本文件补齐 base64 非法输入、json_escape 转义、各标量
// 编解码类型不符、repeated/map 字段的错误与默认值省略、整数字符串解析的边界
// 等分支，作为 JSON 映射的负例/边界回归。

///|
/// 构造一个普通（singular）字段。
fn jc_field(
  name : String,
  number : Int,
  ptype : ProtoType,
  label : FieldLabel,
) -> ProtoField {
  { name, number, ptype, label, options: [] }
}

///|
/// 构造一个仅含给定字段与 map 条目的消息。
fn jc_msg(
  name : String,
  fields : Array[ProtoField],
  maps : Array[MapEntry],
) -> ProtoMessage {
  {
    name,
    fields,
    maps,
    oneofs: [],
    reserved_numbers: [],
    reserved_names: [],
    nested_messages: [],
    nested_enums: [],
  }
}

///|
/// 用一组消息构造模式。
fn jc_schema(messages : Array[ProtoMessage]) -> ProtoSchema {
  { messages, enums: [] }
}

///|
/// 断言：从 JSON 文本解码应失败。
fn jc_dec_err(schema : ProtoSchema, msg : String, json : String) -> Bool {
  match decode_json(schema, msg, json) {
    Ok(_) => false
    Err(_) => true
  }
}

///|
/// 断言：编码应失败。
fn jc_enc_err(schema : ProtoSchema, name : String, m : TypedMessage) -> Bool {
  match encode_json(schema, name, m) {
    Ok(_) => false
    Err(_) => true
  }
}

// ─────────────────────────────── base64 ───────────────────────────────────

///|
test "base64_decode handles '+'/'/'，whitespace，and rejects bad input" {
  // '+'(62) 与 '/'(63) 字母表分支 + 含空白字符（换行/空格/制表）被跳过。
  let with_ws = base64_encode(b"\xfb\xff\xbf") // 含 '+' 与 '/'
  let spaced = with_ws.to_array()
  // 在中间插入空白，验证 continue 分支仍解出原字节。
  let injected = "\n " + with_ws + "\t"
  match base64_decode(injected) {
    Some(b) => assert_true(b == b"\xfb\xff\xbf")
    None => fail("含空白的合法 base64 应解码成功")
  }
  ignore(spaced)
  // 非法字符 → None。
  assert_true(base64_decode("@@@@") is None)
  // 余数为 1 个有效字符 → 非法长度 → None。
  assert_true(base64_decode("A") is None)
}

// ─────────────────────────── 编码：转义与类型 ─────────────────────────────

///|
test "encode_json escapes control characters and quotes" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("s", 1, PString, LSingular)], []),
  ])
  let m = TypedMessage::new().set(1, TStringV("a\"b\\c\nd\re\tf"))
  match encode_json(schema, "M", m) {
    Ok(out) => {
      assert_true(out.contains("\\\""))
      assert_true(out.contains("\\\\"))
      assert_true(out.contains("\\n"))
      assert_true(out.contains("\\r"))
      assert_true(out.contains("\\t"))
    }
    Err(e) => fail("编码不应失败：\{e}")
  }
}

///|
test "encode_json maps snake_case field with digit after underscore" {
  // 字段名 "n_1" → snake_to_camel 命中下划线后非小写字符分支 → "n1"。
  let schema = jc_schema([
    jc_msg("M", [jc_field("n_1", 1, PInt32, LSingular)], []),
  ])
  let m = TypedMessage::new().set(1, TInt(5L))
  match encode_json(schema, "M", m) {
    Ok(out) => assert_true(out.contains("n1"))
    Err(e) => fail("编码不应失败：\{e}")
  }
}

///|
test "encode_json omits scalar default singular fields" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("x", 1, PInt32, LSingular)], []),
  ])
  let m = TypedMessage::new().set(1, TInt(0L)) // 默认值
  match encode_json(schema, "M", m) {
    Ok(out) => assert_eq(out, "{}")
    Err(e) => fail("编码不应失败：\{e}")
  }
}

///|
test "encode_json fails on type-mismatched singular value" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("x", 1, PInt32, LSingular)], []),
  ])
  let m = TypedMessage::new().set(1, TStringV("not-an-int"))
  assert_true(jc_enc_err(schema, "M", m))
}

///|
test "encode_json fails when message name is unknown" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("x", 1, PInt32, LSingular)], []),
  ])
  let m = TypedMessage::new().set(1, TInt(1L))
  assert_true(jc_enc_err(schema, "NOPE", m))
}

///|
test "encode_json repeated field error and non-list rejection" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("r", 1, PInt32, LRepeated(packed=false))], []),
  ])
  // 元素类型不符。
  let bad_elem = TypedMessage::new().set(1, TList([TStringV("x")]))
  assert_true(jc_enc_err(schema, "M", bad_elem))
  // repeated 字段被赋非 TList 值。
  let non_list = TypedMessage::new().set(1, TInt(5L))
  assert_true(jc_enc_err(schema, "M", non_list))
}

///|
test "encode_json map: bool key, value error, missing, and non-map value" {
  let mb = MapEntry::{ name: "mb", number: 1, key: PBool, value: PInt32 }
  let schema_b = jc_schema([jc_msg("M", [], [mb])])
  // bool 键 → "true"/"false"。
  let okmap = TypedMessage::new().set(1, TMap([(TBoolV(true), TInt(1L))]))
  match encode_json(schema_b, "M", okmap) {
    Ok(out) => assert_true(out.contains("true"))
    Err(e) => fail("编码不应失败：\{e}")
  }
  // map 值类型不符。
  let ms = MapEntry::{ name: "ms", number: 1, key: PString, value: PInt32 }
  let schema_s = jc_schema([jc_msg("M", [], [ms])])
  let badval = TypedMessage::new().set(
    1,
    TMap([(TStringV("k"), TStringV("x"))]),
  )
  assert_true(jc_enc_err(schema_s, "M", badval))
  // map 字段缺省（未设置）→ 跳过，编码为 {}。
  let empty = TypedMessage::new()
  match encode_json(schema_s, "M", empty) {
    Ok(out) => assert_eq(out, "{}")
    Err(e) => fail("编码不应失败：\{e}")
  }
  // map 字段被赋非 TMap 值。
  let nonmap = TypedMessage::new().set(1, TInt(9L))
  assert_true(jc_enc_err(schema_s, "M", nonmap))
  // 整数键 → 直接 to_string。
  let mi = MapEntry::{ name: "mi", number: 1, key: PInt32, value: PInt32 }
  let schema_i = jc_schema([jc_msg("M", [], [mi])])
  let intkey = TypedMessage::new().set(1, TMap([(TInt(7L), TInt(1L))]))
  match encode_json(schema_i, "M", intkey) {
    Ok(out) => assert_true(out.contains("7"))
    Err(e) => fail("编码不应失败：\{e}")
  }
  // 无符号整数键 → 直接 to_string。
  let mu = MapEntry::{ name: "mu", number: 1, key: PUInt32, value: PInt32 }
  let schema_u = jc_schema([jc_msg("M", [], [mu])])
  let ukey = TypedMessage::new().set(1, TMap([(TUInt(11UL), TInt(1L))]))
  match encode_json(schema_u, "M", ukey) {
    Ok(out) => assert_true(out.contains("11"))
    Err(e) => fail("编码不应失败：\{e}")
  }
  // 键类型与取值不匹配 → 回退为空字符串键（防御分支）。
  let mismatch = TypedMessage::new().set(1, TMap([(TStringV("x"), TInt(1L))]))
  match encode_json(schema_i, "M", mismatch) {
    Ok(_) => assert_true(true)
    Err(e) => fail("编码不应失败：\{e}")
  }
}

// ─────────────────────────── 错误类型 Show 委托 ───────────────────────────

///|
test "DecodeError and ParseError render via Show (debug delegation)" {
  let de : DecodeError = UnexpectedEof(offset=5)
  assert_true("\{de}".length() > 0)
  let de2 : DecodeError = InvalidWireType(offset=1, tag=2UL)
  assert_true(de2.to_string().contains("InvalidWireType"))
  let pe = ParseError::new(1, 2, 3, "boom")
  assert_true("\{pe}".contains("boom"))
}

// ─────────────────────────── 解码：标量类型不符 ───────────────────────────

///|
test "decode_json rejects type-mismatched scalars" {
  let s_i32 = jc_schema([jc_msg("M", [jc_field("f", 1, PInt32, LSingular)], [])])
  assert_true(jc_dec_err(s_i32, "M", "{\"f\":true}")) // PInt32 from bool
  let s_i64 = jc_schema([jc_msg("M", [jc_field("f", 1, PInt64, LSingular)], [])])
  assert_true(jc_dec_err(s_i64, "M", "{\"f\":\"\"}")) // PInt64 from empty string
  let s_u32 = jc_schema([
    jc_msg("M", [jc_field("f", 1, PUInt32, LSingular)], []),
  ])
  assert_true(jc_dec_err(s_u32, "M", "{\"f\":true}")) // PUInt32 from bool
  let s_u64 = jc_schema([
    jc_msg("M", [jc_field("f", 1, PUInt64, LSingular)], []),
  ])
  assert_true(jc_dec_err(s_u64, "M", "{\"f\":\"x\"}")) // PUInt64 from non-numeric
  let s_b = jc_schema([jc_msg("M", [jc_field("f", 1, PBool, LSingular)], [])])
  assert_true(jc_dec_err(s_b, "M", "{\"f\":1}")) // PBool from number
  let s_e = jc_schema([
    jc_msg("M", [jc_field("f", 1, PEnum("E"), LSingular)], []),
  ])
  assert_true(jc_dec_err(s_e, "M", "{\"f\":true}")) // PEnum from bool
  let s_fl = jc_schema([jc_msg("M", [jc_field("f", 1, PFloat, LSingular)], [])])
  assert_true(jc_dec_err(s_fl, "M", "{\"f\":\"x\"}")) // PFloat from string
  let s_d = jc_schema([jc_msg("M", [jc_field("f", 1, PDouble, LSingular)], [])])
  assert_true(jc_dec_err(s_d, "M", "{\"f\":true}")) // PDouble from bool
  let s_s = jc_schema([jc_msg("M", [jc_field("f", 1, PString, LSingular)], [])])
  assert_true(jc_dec_err(s_s, "M", "{\"f\":1}")) // PString from number
  let s_by = jc_schema([jc_msg("M", [jc_field("f", 1, PBytes, LSingular)], [])])
  assert_true(jc_dec_err(s_by, "M", "{\"f\":\"@@@\"}")) // PBytes from bad base64
  assert_true(jc_dec_err(s_by, "M", "{\"f\":1}")) // PBytes from number
}

///|
test "decode_json parses signed/unsigned integers from strings with edges" {
  let s_i64 = jc_schema([jc_msg("M", [jc_field("f", 1, PInt64, LSingular)], [])])
  // 前导 '+'。
  match decode_json(s_i64, "M", "{\"f\":\"+5\"}") {
    Ok(m) => assert_true(m.get(1) == Some(TInt(5L)))
    Err(e) => fail("应解析成功：\{e}")
  }
  // 仅符号、含非数字 → 失败。
  assert_true(jc_dec_err(s_i64, "M", "{\"f\":\"+\"}"))
  assert_true(jc_dec_err(s_i64, "M", "{\"f\":\"1a\"}"))
  let s_u64 = jc_schema([
    jc_msg("M", [jc_field("f", 1, PUInt64, LSingular)], []),
  ])
  match decode_json(s_u64, "M", "{\"f\":\"+5\"}") {
    Ok(m) => assert_true(m.get(1) == Some(TUInt(5UL)))
    Err(e) => fail("应解析成功：\{e}")
  }
  assert_true(jc_dec_err(s_u64, "M", "{\"f\":\"\"}"))
  assert_true(jc_dec_err(s_u64, "M", "{\"f\":\"+\"}"))
  assert_true(jc_dec_err(s_u64, "M", "{\"f\":\"1a\"}"))
}

// ─────────────────────────── 解码：复合与结构 ─────────────────────────────

///|
test "decode_json nested message error and non-object" {
  let inner = jc_msg("Inner", [jc_field("g", 1, PInt32, LSingular)], [])
  let outer = jc_msg(
    "M",
    [jc_field("inner", 1, PMessage("Inner"), LSingular)],
    [],
  )
  let schema = jc_schema([outer, inner])
  // 内层字段类型不符 → 错误向上传播。
  assert_true(jc_dec_err(schema, "M", "{\"inner\":{\"g\":true}}"))
  // PMessage 字段被赋非对象。
  assert_true(jc_dec_err(schema, "M", "{\"inner\":5}"))
}

///|
test "decode_json repeated field error and non-array" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("r", 1, PInt32, LRepeated(packed=false))], []),
  ])
  // 合法 repeated 往返。
  match decode_json(schema, "M", "{\"r\":[1,2]}") {
    Ok(m) => assert_true(m.get(1) == Some(TList([TInt(1L), TInt(2L)])))
    Err(e) => fail("应解析成功：\{e}")
  }
  // 元素类型不符。
  assert_true(jc_dec_err(schema, "M", "{\"r\":[true]}"))
  // repeated 字段被赋非数组。
  assert_true(jc_dec_err(schema, "M", "{\"r\":5}"))
}

///|
test "decode_json singular type error and unknown message and non-object root" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("f", 1, PInt32, LSingular)], []),
  ])
  assert_true(jc_dec_err(schema, "M", "{\"f\":true}")) // 单值类型不符
  assert_true(jc_dec_err(schema, "NOPE", "{}")) // 未知消息
  assert_true(jc_dec_err(schema, "M", "5")) // 顶层非对象
}

///|
test "decode_json map keys across key types and map errors" {
  let mk = fn(key : ProtoType) -> ProtoSchema {
    jc_schema([
      jc_msg("M", [], [MapEntry::{ name: "m", number: 1, key, value: PInt32 }]),
    ])
  }
  // 各键类型解析。
  match decode_json(mk(PBool), "M", "{\"m\":{\"true\":1,\"false\":2}}") {
    Ok(_) => assert_true(true)
    Err(e) => fail("bool 键应解析：\{e}")
  }
  match decode_json(mk(PInt32), "M", "{\"m\":{\"7\":1}}") {
    Ok(_) => assert_true(true)
    Err(e) => fail("int32 键应解析：\{e}")
  }
  match decode_json(mk(PInt64), "M", "{\"m\":{\"8\":1}}") {
    Ok(_) => assert_true(true)
    Err(e) => fail("int64 键应解析：\{e}")
  }
  match decode_json(mk(PUInt32), "M", "{\"m\":{\"9\":1}}") {
    Ok(_) => assert_true(true)
    Err(e) => fail("uint32 键应解析：\{e}")
  }
  match decode_json(mk(PUInt64), "M", "{\"m\":{\"10\":1}}") {
    Ok(_) => assert_true(true)
    Err(e) => fail("uint64 键应解析：\{e}")
  }
  // 非法 bool 键、非法整数键、不支持的键类型（bytes）→ 失败。
  assert_true(jc_dec_err(mk(PBool), "M", "{\"m\":{\"xyz\":1}}"))
  assert_true(jc_dec_err(mk(PInt32), "M", "{\"m\":{\"x\":1}}"))
  assert_true(jc_dec_err(mk(PInt64), "M", "{\"m\":{\"x\":1}}"))
  assert_true(jc_dec_err(mk(PUInt32), "M", "{\"m\":{\"x\":1}}"))
  assert_true(jc_dec_err(mk(PUInt64), "M", "{\"m\":{\"x\":1}}"))
  assert_true(jc_dec_err(mk(PBytes), "M", "{\"m\":{\"AA==\":1}}"))
  // map 值类型不符。
  assert_true(jc_dec_err(mk(PInt32), "M", "{\"m\":{\"7\":true}}"))
  // map 字段被赋非对象。
  assert_true(jc_dec_err(mk(PInt32), "M", "{\"m\":5}"))
  // map 字段缺省 → 成功，无该键。
  match decode_json(mk(PInt32), "M", "{}") {
    Ok(_) => assert_true(true)
    Err(e) => fail("缺省 map 应解析：\{e}")
  }
}
