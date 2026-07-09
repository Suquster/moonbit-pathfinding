// typed_gaps_test.mbt —— 类型化编解码错误分支覆盖收口（INFRA 第十七批）：
// 编码类型不符全谱、repeated/map 形态破坏、未知消息名、嵌套错误传播、
// 解码 wire 类别不符与 map 条目结构破坏的确定性反例。

///|
fn tg_schema(t : ProtoType, label : FieldLabel) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [{ name: "x", number: 1, ptype: t, label, options: [] }],
        maps: [],
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
fn tg_map_schema(key : ProtoType, value : ProtoType) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [],
        maps: [{ name: "m", number: 1, key, value }],
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
fn tg_enc(t : ProtoType, v : TypedValue) -> Bool {
  encode_typed(tg_schema(t, LSingular), "M", TypedMessage::new().set(1, v))
  is Err(_)
}

///|
test "encode_typed 类型不符全谱拒绝" {
  // 每个标量类型收到不符的 TypedValue → InvalidWireType。
  assert_true(tg_enc(PInt32, TBoolV(true)))
  assert_true(tg_enc(PInt64, TStringV("x")))
  assert_true(tg_enc(PUInt32, TInt(1L)))
  assert_true(tg_enc(PUInt64, TInt(1L)))
  assert_true(tg_enc(PSInt32, TUInt(1UL)))
  assert_true(tg_enc(PSInt64, TUInt(1UL)))
  assert_true(tg_enc(PBool, TInt(1L)))
  assert_true(tg_enc(PEnum("E"), TInt(1L)))
  assert_true(tg_enc(PFixed32, TInt(1L)))
  assert_true(tg_enc(PSFixed32, TUInt(1UL)))
  assert_true(tg_enc(PFloat, TDoubleV(1.0)))
  assert_true(tg_enc(PFixed64, TInt(1L)))
  assert_true(tg_enc(PSFixed64, TUInt(1UL)))
  assert_true(tg_enc(PDouble, TFloatV((1.0 : Float))))
  assert_true(tg_enc(PString, TBytesV(b"x")))
  assert_true(tg_enc(PBytes, TStringV("x")))
  assert_true(tg_enc(PMessage("Inner"), TInt(1L)))
}

///|
test "encode_typed repeated / map / 未知消息名拒绝" {
  // repeated 收到非 TList。
  let rp = tg_schema(PInt32, LRepeated(packed=true))
  assert_true(
    encode_typed(rp, "M", TypedMessage::new().set(1, TInt(1L))) is Err(_),
  )
  // packed 元素类型不符（写入 packed 缓冲时拒绝）。
  assert_true(
    encode_typed(rp, "M", TypedMessage::new().set(1, TList([TBoolV(true)])))
    is Err(_),
  )
  // 非 packed 元素类型不符。
  let rnp = tg_schema(PString, LRepeated(packed=false))
  assert_true(
    encode_typed(rnp, "M", TypedMessage::new().set(1, TList([TInt(1L)])))
    is Err(_),
  )
  // map 收到非 TMap / 键类型不符 / 值类型不符。
  let ms = tg_map_schema(PInt32, PString)
  assert_true(
    encode_typed(ms, "M", TypedMessage::new().set(1, TInt(1L))) is Err(_),
  )
  assert_true(
    encode_typed(
      ms,
      "M",
      TypedMessage::new().set(1, TMap([(TStringV("k"), TStringV("v"))])),
    )
    is Err(_),
  )
  assert_true(
    encode_typed(
      ms,
      "M",
      TypedMessage::new().set(1, TMap([(TInt(1L), TInt(2L))])),
    )
    is Err(_),
  )
  // 未知消息名。
  assert_true(encode_typed(ms, "Nope", TypedMessage::new()) is Err(_))
  // 嵌套消息编码错误传播：Inner 未在 schema 中定义。
  let ns = tg_schema(PMessage("Inner"), LSingular)
  assert_true(
    encode_typed(ns, "M", TypedMessage::new().set(1, TMsg(TypedMessage::new())))
    is Err(_),
  )
}

///|
test "decode_typed wire 类别不符与结构破坏拒绝" {
  // 未知消息名。
  assert_true(decode_typed(tg_schema(PInt32, LSingular), "Nope", b"") is Err(_))
  // Len 字段（string）收到 varint：tag=0x08（field 1, wt 0）。
  assert_true(
    decode_typed(tg_schema(PString, LSingular), "M", b"\x08\x01") is Err(_),
  )
  // varint 字段（int32）收到 Len：tag=0x0A + 1 字节载荷。
  assert_true(
    decode_typed(tg_schema(PInt32, LSingular), "M", b"\x0a\x01\x00") is Err(_),
  )
  // 嵌套消息错误传播：child 载荷为截断 varint。
  let ns : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [
          {
            name: "c",
            number: 1,
            ptype: PMessage("Inner"),
            label: LSingular,
            options: [],
          },
        ],
        maps: [],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
      {
        name: "Inner",
        fields: [
          { name: "y", number: 1, ptype: PInt32, label: LSingular, options: [] },
        ],
        maps: [],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
  assert_true(decode_typed(ns, "M", b"\x0a\x02\x08\xff") is Err(_))
  // repeated 数值标量：packed 载荷截断拒绝；非 packed 单 varint 元素接受。
  let rp = tg_schema(PInt32, LRepeated(packed=true))
  assert_true(decode_typed(rp, "M", b"\x0a\x01\xff") is Err(_))
  match decode_typed(rp, "M", b"\x08\x05") {
    Ok(m) => assert_true(m.get(1) == Some(TList([TInt(5L)])))
    Err(_) => assert_true(false)
  }
  // repeated string：Len 元素逐条追加。
  let rs = tg_schema(PString, LRepeated(packed=false))
  match decode_typed(rs, "M", b"\x0a\x01a\x0a\x01b") {
    Ok(m) =>
      assert_true(m.get(1) == Some(TList([TStringV("a"), TStringV("b")])))
    Err(_) => assert_true(false)
  }
}

///|
test "decode_typed map 条目结构分支" {
  let ms = tg_map_schema(PInt32, PString)
  // map 字段收到 varint（非 VBytes）→ 拒绝。
  assert_true(decode_typed(ms, "M", b"\x08\x01") is Err(_))
  // 空条目 → 键值都取默认。
  match decode_typed(ms, "M", b"\x0a\x00") {
    Ok(m) => assert_true(m.get(1) == Some(TMap([(TInt(0L), TStringV(""))])))
    Err(_) => assert_true(false)
  }
  // 仅键（field 1 varint 7）→ 值取默认。
  match decode_typed(ms, "M", b"\x0a\x02\x08\x07") {
    Ok(m) => assert_true(m.get(1) == Some(TMap([(TInt(7L), TStringV(""))])))
    Err(_) => assert_true(false)
  }
  // 仅值（field 2 len "v"）→ 键取默认。
  match decode_typed(ms, "M", b"\x0a\x03\x12\x01v") {
    Ok(m) => assert_true(m.get(1) == Some(TMap([(TInt(0L), TStringV("v"))])))
    Err(_) => assert_true(false)
  }
  // 键 wire 类别不符（field 1 为 Len）→ 拒绝。
  assert_true(decode_typed(ms, "M", b"\x0a\x03\x0a\x01k") is Err(_))
  // 值 wire 类别不符（field 2 为 varint）→ 拒绝。
  assert_true(decode_typed(ms, "M", b"\x0a\x02\x10\x01") is Err(_))
  // 条目载荷本身破坏（截断 varint）→ 拒绝。
  assert_true(decode_typed(ms, "M", b"\x0a\x01\xff") is Err(_))
}
