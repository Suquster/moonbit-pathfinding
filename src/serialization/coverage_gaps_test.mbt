// 黑盒测试：serialization 未覆盖分支（JSON 转义/畸形输入、Any 流式解码、
// wire 截断、canonical、schema 校验/投影、codegen 类型名、proto 解析器错误路径）

///|
/// 单消息富模式辅助（与 json_test.mbt 同构）。
fn cgs_schema(
  fields : Array[ProtoField],
  maps : Array[MapEntry],
) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields,
        maps,
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
}

///|
fn cgs_field(name : String, number : Int, t : ProtoType) -> ProtoField {
  { name, number, ptype: t, label: LSingular, options: [] }
}

///|
test "JSON：snake_to_camel 下划线后非小写字母原样、全量转义字符往返" {
  let schema = cgs_schema([cgs_field("a_1b_x", 1, PString)], [])
  let m = TypedMessage::new().set(1, TStringV("q\"w\\e\nr\rt\tu"))
  guard encode_json(schema, "M", m) is Ok(s)
  assert_true(s.contains("a1bX"))
  assert_true(s.contains("\\\"") && s.contains("\\\\"))
  assert_true(s.contains("\\n") && s.contains("\\r") && s.contains("\\t"))
}

///|
test "JSON：未知消息名与类型/值失配拒绝" {
  let schema = cgs_schema([cgs_field("b", 1, PBool)], [])
  assert_true(encode_json(schema, "M2", TypedMessage::new()) is Err(_))
  let bad = TypedMessage::new().set(1, TInt(1L))
  assert_true(encode_json(schema, "M", bad) is Err(_))
}

///|
test "JSON：bool map 键渲染为 true/false 字符串" {
  let schema = cgs_schema([], [
    { name: "flags", number: 1, key: PBool, value: PInt32 },
  ])
  let m = TypedMessage::new().set(
    1,
    TMap([(TBoolV(true), TInt(1L)), (TBoolV(false), TInt(2L))]),
  )
  guard encode_json(schema, "M", m) is Ok(s)
  assert_true(s.contains("\"true\"") && s.contains("\"false\""))
}

///|
test "decode_any：截断 tag / 非 Len wire / 未知字段号 / 截断负载均拒绝" {
  assert_true(decode_any(b"\x80") is Err(_)) // 截断 varint tag
  assert_true(decode_any(b"\x08\x01") is Err(_)) // field 1 Varint wire
  assert_true(decode_any(b"\x1a\x01\x41") is Err(_)) // field 3 非 Any 字段
  assert_true(decode_any(b"\x0a\x05\x41") is Err(_)) // 声明长度超出剩余
}

///|
test "streaming：ByteSink::len / ByteSource::position / 错误路径" {
  let sink = ByteSink::new()
  assert_eq(sink.len(), 0)
  let schema = cgs_schema([cgs_field("n", 1, PInt32)], [])
  // 未知消息名：encode_to 不写入并返回错误。
  assert_true(encode_to(sink, schema, "Nope", TypedMessage::new()) is Err(_))
  assert_eq(sink.len(), 0)
  guard encode_to(sink, schema, "M", TypedMessage::new().set(1, TInt(7L)))
    is Ok(_)
  assert_true(sink.len() > 0)
  let src = ByteSource::new(sink.to_bytes())
  assert_eq(src.position(), 0)
  guard decode_from(src, schema, "M") is Ok(out)
  assert_true(out.get(1) == Some(TInt(7L)))
  // 截断源：decode_from 传播错误。
  let bad = ByteSource::new(b"\x80")
  assert_true(decode_from(bad, schema, "M") is Err(_))
}

///|
test "wire.decode：tag 后缺值 / 续位截断的 varint 拒绝" {
  let schema = Schema::empty()
  assert_true(decode(b"\x08", schema) is Err(_)) // tag 后无值
  assert_true(decode(b"\x08\x80", schema) is Err(_)) // 值 varint 截断
}

///|
test "canonical：canonicalize_wire 稳定排序、encode_canonical 未知消息拒绝" {
  let msg = Message::from_fields([
    FieldEntry::new(2, FieldValue::varint(5UL)),
    FieldEntry::new(1, FieldValue::varint(9UL)),
  ])
  let a = canonicalize_wire(msg)
  let b = canonicalize_wire(msg)
  assert_eq(a, b)
  let schema = ProtoSchema::empty()
  assert_true(encode_canonical(schema, "M", TypedMessage::new()) is Err(_))
}

///|
test "schema 校验：保留名冲突 / 枚举引用未解析 / map 字段号异常均报错" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [
          cgs_field("ghost", 1, PEnum("NoSuchEnum")),
          cgs_field("legacy", 2, PInt32),
        ],
        maps: [
          { name: "dup", number: 2, key: PString, value: PInt32 },
          { name: "oob", number: 0, key: PString, value: PInt32 },
          { name: "rsv", number: 9, key: PString, value: PInt32 },
        ],
        oneofs: [],
        reserved_numbers: [{ lo: 9, hi: 9 }],
        reserved_names: ["legacy"],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
  guard validate_schema(schema) is Err(errors)
  assert_true(errors.length() >= 4)
  // Show for SchemaError 可渲染。
  let rendered = "\{errors[0]}"
  assert_true(rendered.length() > 0)
}

///|
test "ProtoSchema::to_legacy：字段与 map 展平投影" {
  let schema = cgs_schema(
    [
      cgs_field("a", 1, PFloat),
      cgs_field("b", 2, PBytes),
      {
        name: "xs",
        number: 3,
        ptype: PInt64,
        label: LRepeated(packed=true),
        options: [],
      },
    ],
    [{ name: "meta", number: 4, key: PString, value: PInt32 }],
  )
  let legacy = schema.to_legacy()
  assert_eq(legacy.messages.length(), 1)
  let m = legacy.messages[0]
  assert_eq(m.fields.length(), 4)
  assert_true(m.fields[2].repeated)
  assert_true(m.fields[3].ftype is TMessage(_) && m.fields[3].repeated)
}

///|
test "schema 演进：float 与 double wire 分组不同视为破坏性变更" {
  let old = cgs_schema([cgs_field("v", 1, PFloat)], [])
  let new_ = cgs_schema([cgs_field("v", 1, PDouble)], [])
  let changes = check_schema_evolution(old, new_)
  assert_true(changes.length() > 0)
}

///|
test "codegen：Int64 与 Bytes 类型名进入生成代码" {
  let schema : Schema = {
    messages: [
      {
        name: "T",
        fields: [
          { name: "big", number: 1, ftype: TInt64, repeated: false },
          { name: "raw", number: 2, ftype: TBytes, repeated: false },
        ],
      },
    ],
    enums: [],
  }
  let code = gen_moonbit(schema)
  assert_true(code.contains("Int64") && code.contains("Bytes"))
}

///|
test "gen_moonbit_ast：map 字段渲染为键值对数组" {
  let schema = cgs_schema([], [
    { name: "meta", number: 1, key: PString, value: PInt32 },
  ])
  let code = render_code(gen_moonbit_ast(schema))
  assert_true(code.contains("meta : Array[(String, Int)]"))
}

///|
test "get_or_default：命中值 / repeated 缺省 / map 缺省 / 各标量缺省" {
  let schema = cgs_schema(
    [
      cgs_field("s32", 1, PSInt32),
      cgs_field("raw", 2, PBytes),
      {
        name: "xs",
        number: 3,
        ptype: PInt32,
        label: LRepeated(packed=true),
        options: [],
      },
    ],
    [{ name: "kv", number: 4, key: PString, value: PInt32 }],
  )
  guard schema.message("M") is Some(pm)
  let m = TypedMessage::new().set(1, TInt(42L))
  assert_true(m.get_or_default(pm, 1) == TInt(42L)) // 命中已有值
  assert_true(m.get_or_default(pm, 1) != TInt(0L))
  let empty = TypedMessage::new()
  assert_true(empty.get_or_default(pm, 1) == TInt(0L)) // sint 缺省
  assert_true(empty.get_or_default(pm, 2) == TBytesV(b"")) // bytes 缺省
  assert_true(empty.get_or_default(pm, 3) == TList([])) // repeated 缺省
  assert_true(empty.get_or_default(pm, 4) == TMap([])) // map 缺省
}

///|
test "typed：嵌套消息字段编码（typed_is_default 非标量兜底）与 UTF-8 宽字符往返" {
  let inner : ProtoMessage = {
    name: "Inner",
    fields: [cgs_field("t", 1, PString)],
    maps: [],
    oneofs: [],
    reserved_numbers: [],
    reserved_names: [],
    nested_messages: [],
    nested_enums: [],
  }
  let outer : ProtoMessage = {
    name: "Outer",
    fields: [cgs_field("kid", 1, PMessage("Inner"))],
    maps: [],
    oneofs: [],
    reserved_numbers: [],
    reserved_names: [],
    nested_messages: ["Inner"],
    nested_enums: [],
  }
  let schema : ProtoSchema = { messages: [outer, inner], enums: [] }
  // "中" 为三字节 UTF-8，"𝄞" 为四字节（代理对）。
  let kid = TypedMessage::new().set(1, TStringV("中𝄞"))
  let msg = TypedMessage::new().set(1, TMsg(kid))
  guard encode_typed(schema, "Outer", msg) is Ok(bytes)
  guard decode_typed(schema, "Outer", bytes) is Ok(out)
  guard out.get(1) is Some(TMsg(k2))
  assert_true(k2.get(1) == Some(TStringV("中𝄞")))
}

///|
test "JSON：整型 map 键 / 解码类型不符 / 畸形数字串拒绝" {
  let schema = cgs_schema([], [
    { name: "byid", number: 1, key: PInt32, value: PString },
  ])
  let m = TypedMessage::new().set(1, TMap([(TInt(7L), TStringV("seven"))]))
  guard encode_json(schema, "M", m) is Ok(s)
  assert_true(s.contains("\"7\""))
  // 解码：数值处放 JSON 字符串以外的类型 → 类型不符。
  let s64 = cgs_schema([cgs_field("big", 1, PInt64)], [])
  assert_true(decode_json(s64, "M", "{\"big\":true}") is Err(_))
  // 64 位整数字符串里混入非数字。
  assert_true(decode_json(s64, "M", "{\"big\":\"12a\"}") is Err(_))
  assert_true(decode_json(s64, "M", "{\"big\":\"\"}") is Err(_))
  let u64 = cgs_schema([cgs_field("u", 1, PUInt64)], [])
  assert_true(decode_json(u64, "M", "{\"u\":\"9x\"}") is Err(_))
  assert_true(decode_json(u64, "M", "{\"u\":\"\"}") is Err(_))
}

///|
test "typed：uint/message 缺省值、标量类型失配与嵌套编码错误传播" {
  let schema = cgs_schema(
    [cgs_field("u", 1, PUInt32), cgs_field("kid", 2, PMessage("M"))],
    [],
  )
  guard schema.message("M") is Some(pm)
  let empty = TypedMessage::new()
  assert_true(empty.get_or_default(pm, 1) == TUInt(0UL))
  assert_true(empty.get_or_default(pm, 2) is TMsg(_))
  // 标量类型失配拒绝。
  let bad = TypedMessage::new().set(1, TStringV("oops"))
  assert_true(encode_typed(schema, "M", bad) is Err(_))
  // 嵌套消息指向不存在定义 → 错误自内层传播。
  let ghost = cgs_schema([cgs_field("kid", 1, PMessage("Ghost"))], [])
  let m = TypedMessage::new().set(1, TMsg(TypedMessage::new().set(1, TInt(1L))))
  assert_true(encode_typed(ghost, "M", m) is Err(_))
}

///|
test "typed：非法 UTF-8 字节解码为替换字符" {
  let schema = cgs_schema([cgs_field("t", 1, PString)], [])
  // 手工构造 wire：field 1 Len，负载为孤立的 0xFF 字节。
  guard decode_typed(schema, "M", b"\x0a\x01\xff") is Ok(out)
  guard out.get(1) is Some(TStringV(s))
  assert_eq(s, "\u{FFFD}")
}

///|
test "codegen：UInt 与消息类型名进入生成代码" {
  let schema : Schema = {
    messages: [
      {
        name: "T",
        fields: [
          { name: "cnt", number: 1, ftype: TUInt32, repeated: false },
          { name: "kid", number: 2, ftype: TMessage("Other"), repeated: false },
        ],
      },
      { name: "Other", fields: [] },
    ],
    enums: [],
  }
  let code = gen_moonbit(schema)
  assert_true(code.contains("UInt") && code.contains("Other"))
}

///|
test "types：ParseError::new 构造与 Show 渲染" {
  let pe = ParseError::new(3, 7, 42, "boom")
  assert_eq(pe.line, 3)
  assert_eq(pe.col, 7)
  assert_true("\{pe}".length() > 0)
  guard decode(b"\x08", Schema::empty()) is Err(de)
  assert_true("\{de}".length() > 0)
}

///|
test "proto 解析器：EOF 处行注释 / 块注释中孤立 '*' / 负枚举值" {
  // 行注释在 EOF 结束（无换行）。
  assert_true(parse_proto("message M { int32 a = 1; } // tail") is Ok(_))
  // 块注释内出现非结束的 '*'。
  assert_true(parse_proto("/* *x* */ message M { int32 a = 1; }") is Ok(_))
  // 负枚举值走 parse_number 的 '-' 分支。
  guard parse_proto("enum E { NEG = -5; ZERO = 0; }") is Ok(s)
  assert_true(s.enums[0].values[0] == ("NEG", -5))
}

///|
test "proto_grammar：未闭合字符串字面量 / 空选项值 / 字段选项残缺拒绝" {
  // option 字符串未闭合。
  assert_true(parse_proto_full("option java_package = \"abc") is Err(_))
  // 字段选项字符串值在 EOF 处未闭合。
  assert_true(
    parse_proto_full("message M { int32 a = 1 [json_name = \"x") is Err(_),
  )
  // 字段选项缺名称 / 缺 '=' / 缺取值。
  assert_true(
    parse_proto_full("message M { int32 a = 1 [ = true]; }") is Err(_),
  )
  assert_true(
    parse_proto_full("message M { int32 a = 1 [deprecated true]; }") is Err(_),
  )
  assert_true(
    parse_proto_full("message M { int32 a = 1 [deprecated = ]; }") is Err(_),
  )
}

///|
test "proto_service：rpc 结构残缺各分支拒绝、选项块整体跳过" {
  // 缺方法名。
  assert_true(parse_proto_file("service S { rpc ; }") is Err(_))
  // 缺 '('。
  assert_true(parse_proto_file("service S { rpc F ; }") is Err(_))
  // 缺输入类型。
  assert_true(parse_proto_file("service S { rpc F(); }") is Err(_))
  // 缺输入侧 ')'。
  assert_true(parse_proto_file("service S { rpc F(A; }") is Err(_))
  // returns 关键字错误。
  assert_true(parse_proto_file("service S { rpc F(A) sends (B); }") is Err(_))
  // 'returns' 后缺 '('。
  assert_true(parse_proto_file("service S { rpc F(A) returns B; }") is Err(_))
  // 缺输出类型。
  assert_true(parse_proto_file("service S { rpc F(A) returns (); }") is Err(_))
  // 缺输出侧 ')'。
  assert_true(parse_proto_file("service S { rpc F(A) returns (B; }") is Err(_))
  // 缺 ';' 或 '{'。
  assert_true(parse_proto_file("service S { rpc F(A) returns (B) }") is Err(_))
  // 带选项块整体跳过。
  guard parse_proto_file(
      "message A { int32 x = 1; } message B { int32 y = 1; } service S { rpc F(A) returns (B) { option idempotency_level = NO_SIDE_EFFECTS; } }",
    )
    is Ok(f)
  assert_eq(f.services.length(), 1)
  assert_eq(f.services[0].rpcs[0].name, "F")
}
