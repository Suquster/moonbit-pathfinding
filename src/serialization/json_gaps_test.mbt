// json_gaps_test.mbt —— proto3 JSON 映射错误分支与 map 键解析覆盖收口
// （INFRA 第十六批）：编码/解码两侧类型不符、缺失消息、map 键各标量形态。

///|
/// 单字段富模式辅助（复用 js_schema 之外的 map 变体）。
fn jg_schema(t : ProtoType, label : FieldLabel) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [{ name: "f_v", number: 1, ptype: t, label, options: [] }],
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
/// 单 map 字段富模式辅助。
fn jg_map_schema(key : ProtoType, value : ProtoType) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [],
        maps: [{ name: "kv_m", number: 1, key, value }],
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
test "encode_json 错误分支：类型不符与缺失消息" {
  // repeated 字段收到非 TList。
  let rs = jg_schema(PInt32, LRepeated(packed=false))
  let bad = TypedMessage::new().set(1, TInt(1L))
  assert_true(encode_json(rs, "M", bad) is Err(_))
  // repeated 元素类型不符（TList 内 PInt32 遇 TBoolV）。
  let bad2 = TypedMessage::new().set(1, TList([TBoolV(true)]))
  assert_true(encode_json(rs, "M", bad2) is Err(_))
  // 单字段类型不符。
  let ss = jg_schema(PBool, LSingular)
  assert_true(
    encode_json(ss, "M", TypedMessage::new().set(1, TInt(1L))) is Err(_),
  )
  // map 字段收到非 TMap / 值类型不符。
  let ms = jg_map_schema(PString, PInt32)
  assert_true(
    encode_json(ms, "M", TypedMessage::new().set(1, TInt(1L))) is Err(_),
  )
  assert_true(
    encode_json(
      ms,
      "M",
      TypedMessage::new().set(1, TMap([(TStringV("k"), TBoolV(true))])),
    )
    is Err(_),
  )
  // schema 中无消息。
  assert_true(encode_json(ms, "Nope", TypedMessage::new()) is Err(_))
}

///|
test "encode_json map 键渲染各标量形态" {
  // bool / int / uint 键。
  let mb = jg_map_schema(PBool, PInt32)
  match
    encode_json(
      mb,
      "M",
      TypedMessage::new().set(1, TMap([(TBoolV(true), TInt(1L))])),
    ) {
    Ok(s) => assert_true(s.contains("true"))
    Err(_) => assert_true(false)
  }
  let mi = jg_map_schema(PInt64, PInt32)
  match
    encode_json(
      mi,
      "M",
      TypedMessage::new().set(1, TMap([(TInt(-7L), TInt(1L))])),
    ) {
    Ok(s) => assert_true(s.contains("-7"))
    Err(_) => assert_true(false)
  }
  let mu = jg_map_schema(PUInt64, PInt32)
  match
    encode_json(
      mu,
      "M",
      TypedMessage::new().set(1, TMap([(TUInt(9UL), TInt(1L))])),
    ) {
    Ok(s) => assert_true(s.contains("9"))
    Err(_) => assert_true(false)
  }
}

///|
test "decode_json 错误分支：类型不符全谱" {
  // 各标量类型收到不符 JSON 值。
  assert_true(
    decode_json(jg_schema(PInt32, LSingular), "M", "{\"fV\":true}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PInt64, LSingular), "M", "{\"fV\":true}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PUInt32, LSingular), "M", "{\"fV\":true}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PUInt64, LSingular), "M", "{\"fV\":true}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PBool, LSingular), "M", "{\"fV\":1}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PEnum("E"), LSingular), "M", "{\"fV\":true}")
    is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PFloat, LSingular), "M", "{\"fV\":\"x\"}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PDouble, LSingular), "M", "{\"fV\":\"x\"}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PString, LSingular), "M", "{\"fV\":1}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PBytes, LSingular), "M", "{\"fV\":\"@@\"}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PBytes, LSingular), "M", "{\"fV\":1}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PMessage("M"), LSingular), "M", "{\"fV\":1}")
    is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PMessage("Nope"), LSingular), "M", "{\"fV\":{}}")
    is Err(_),
  )
  // repeated 字段收到非数组 / 元素错误。
  let rs = jg_schema(PInt32, LRepeated(packed=false))
  assert_true(decode_json(rs, "M", "{\"fV\":1}") is Err(_))
  assert_true(decode_json(rs, "M", "{\"fV\":[true]}") is Err(_))
  // 顶层非对象。
  assert_true(decode_json(rs, "M", "[1]") is Err(_))
  // map：非对象成员 / 键不可解析 / 值错误。
  let ms = jg_map_schema(PInt32, PInt32)
  assert_true(decode_json(ms, "M", "{\"kvM\":1}") is Err(_))
  assert_true(decode_json(ms, "M", "{\"kvM\":{\"x\":1}}") is Err(_))
  assert_true(decode_json(ms, "M", "{\"kvM\":{\"1\":true}}") is Err(_))
}

///|
test "decode_json map 键解析各标量形态与拒绝" {
  // bool 键 true/false/非法。
  let mb = jg_map_schema(PBool, PInt32)
  assert_true(decode_json(mb, "M", "{\"kvM\":{\"true\":1}}") is Ok(_))
  assert_true(decode_json(mb, "M", "{\"kvM\":{\"false\":1}}") is Ok(_))
  assert_true(decode_json(mb, "M", "{\"kvM\":{\"maybe\":1}}") is Err(_))
  // int32 / int64 / uint32 / uint64 键（含 +/− 前缀与空/纯符号拒绝）。
  assert_true(
    decode_json(jg_map_schema(PInt32, PInt32), "M", "{\"kvM\":{\"-3\":1}}")
    is Ok(_),
  )
  assert_true(
    decode_json(jg_map_schema(PInt64, PInt32), "M", "{\"kvM\":{\"+4\":1}}")
    is Ok(_),
  )
  assert_true(
    decode_json(jg_map_schema(PInt64, PInt32), "M", "{\"kvM\":{\"+\":1}}")
    is Err(_),
  )
  assert_true(
    decode_json(jg_map_schema(PUInt32, PInt32), "M", "{\"kvM\":{\"12\":1}}")
    is Ok(_),
  )
  assert_true(
    decode_json(jg_map_schema(PUInt64, PInt32), "M", "{\"kvM\":{\"+7\":1}}")
    is Ok(_),
  )
  assert_true(
    decode_json(jg_map_schema(PUInt64, PInt32), "M", "{\"kvM\":{\"+\":1}}")
    is Err(_),
  )
  assert_true(
    decode_json(jg_map_schema(PUInt64, PInt32), "M", "{\"kvM\":{\"\":1}}")
    is Err(_),
  )
  // 不可作 map 键的类型（PDouble）→ 键解析拒绝。
  assert_true(
    decode_json(jg_map_schema(PDouble, PInt32), "M", "{\"kvM\":{\"1.5\":1}}")
    is Err(_),
  )
  // 64 位整数以字符串形态提供（json_to_i64/u64 的字符串路径）。
  assert_true(
    decode_json(jg_schema(PInt64, LSingular), "M", "{\"fV\":\"-5\"}") is Ok(_),
  )
  assert_true(
    decode_json(jg_schema(PUInt64, LSingular), "M", "{\"fV\":\"6\"}") is Ok(_),
  )
  assert_true(
    decode_json(jg_schema(PInt64, LSingular), "M", "{\"fV\":\"5x\"}") is Err(_),
  )
  assert_true(
    decode_json(jg_schema(PUInt64, LSingular), "M", "{\"fV\":\"6x\"}") is Err(_),
  )
}
