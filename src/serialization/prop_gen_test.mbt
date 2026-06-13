// prop_gen_test.mbt —— 旗舰深化属性测试的共享生成器（黑盒测试，仅用公开 API）。
//
// 本文件集中承载跨多条属性复用的 `@infra_pbt` 生成器（schema + 匹配的类型化
// 消息、合法富模式、解析 round-trip 富模式等），供 prop_*_test.mbt 引用。所有
// 生成器仅使用本包**公开** API（`ProtoSchema`/`ProtoType`/`TypedValue`/
// `encode_typed` 等），符合黑盒测试可见性约束。
//
// 生成空间约束（generation constraints）：刻意把数值约束到可在二进制与 JSON
// 两条路径上**精确往返**的子空间——整数取小幅值（32 位落在 int32 范围、JSON
// number 精确；64 位经 JSON 字符串精确）；浮点取整数值（十进制文本精确往返）；
// 字符串取字母数字（无需 JSON 转义）；不生成默认值标量与空 repeated（与默认值
// 省略语义一致）。符号统一以 `sg_` 前缀，避免同包测试命名冲突。

// ─────────────────────────────── 基础值生成 ───────────────────────────────

///|
/// 小幅整数（含 0），落在可精确往返范围。
fn sg_small_int(rng : @infra_pbt.Rng) -> Int {
  rng.next_range(-100000, 100000)
}

///|
/// 小幅非零整数。
fn sg_nonzero_int(rng : @infra_pbt.Rng) -> Int {
  let v = sg_small_int(rng)
  if v == 0 {
    1
  } else {
    v
  }
}

///|
/// 由正整数构造 `UInt64`。
fn sg_u64_of(v : Int) -> UInt64 {
  v.to_int64().reinterpret_as_uint64()
}

///|
/// 长度 1~5 的字母数字字符串（JSON 无需转义）。
fn sg_alnum(rng : @infra_pbt.Rng) -> String {
  let alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".to_array()
  let n = rng.next_range(1, 5)
  let out : Array[Char] = []
  for _i in 0..<n {
    out.push(alpha[rng.next_below(alpha.length())])
  }
  String::from_array(out)
}

///|
/// 长度 1~4 的随机字节序列。
fn sg_bytes(rng : @infra_pbt.Rng) -> Bytes {
  let n = rng.next_range(1, 4)
  let arr : Array[Byte] = []
  for _i in 0..<n {
    arr.push(rng.next_below(256).to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 全部标量 proto 类型（不含消息/枚举引用）。
fn sg_scalar_types() -> Array[ProtoType] {
  [
    PInt32,
    PInt64,
    PUInt32,
    PUInt64,
    PSInt32,
    PSInt64,
    PFixed32,
    PFixed64,
    PSFixed32,
    PSFixed64,
    PFloat,
    PDouble,
    PBool,
    PString,
    PBytes,
  ]
}

///|
/// 可 packed 的数值标量 proto 类型。
fn sg_numeric_types() -> Array[ProtoType] {
  [
    PInt32,
    PInt64,
    PUInt32,
    PUInt64,
    PSInt32,
    PSInt64,
    PFixed32,
    PFixed64,
    PSFixed32,
    PSFixed64,
    PFloat,
    PDouble,
    PBool,
  ]
}

///|
/// 为某标量 proto 类型生成一个**非默认**取值（保证编码非省略、可精确往返）。
fn sg_value_for(rng : @infra_pbt.Rng, t : ProtoType) -> TypedValue {
  match t {
    PInt32 | PSInt32 | PSFixed32 => TInt(sg_nonzero_int(rng).to_int64())
    PInt64 | PSInt64 | PSFixed64 => TInt(sg_nonzero_int(rng).to_int64())
    PUInt32 | PFixed32 => TUInt(sg_u64_of(rng.next_range(1, 100000)))
    PUInt64 | PFixed64 => TUInt(sg_u64_of(rng.next_range(1, 100000)))
    PBool => TBoolV(true)
    PEnum(_) => TEnumV(rng.next_range(1, 2))
    PFloat => TFloatV(sg_nonzero_int(rng).to_float())
    PDouble => TDoubleV(sg_nonzero_int(rng).to_double())
    PString => TStringV(sg_alnum(rng))
    PBytes => TBytesV(sg_bytes(rng))
    PMessage(_) => TMsg(TypedMessage::new())
  }
}

// ─────────────────────── 模式 + 匹配消息生成（P2/4/8/9）──────────────────

///|
/// 随机富模式：枚举 E、嵌套叶子消息 Inner、根消息 M（1~4 个字段，
/// 类型涵盖标量 / repeated 数值（packed 随机）/ 枚举 / 嵌套消息）。
fn sg_random_schema(rng : @infra_pbt.Rng) -> ProtoSchema {
  let enum_e : EnumDef = {
    name: "E",
    values: [("E0", 0), ("E1", 1), ("E2", 2)],
  }
  let inner : ProtoMessage = {
    name: "Inner",
    fields: [
      { name: "a", number: 1, ptype: PInt32, label: LSingular, options: [] },
      { name: "b", number: 2, ptype: PString, label: LSingular, options: [] },
    ],
    maps: [],
    oneofs: [],
    reserved_numbers: [],
    reserved_names: [],
    nested_messages: [],
    nested_enums: [],
  }
  let scalars = sg_scalar_types()
  let numerics = sg_numeric_types()
  let nfields = rng.next_range(1, 4)
  let fields : Array[ProtoField] = []
  for i in 0..<nfields {
    let number = i + 1
    let name = "f" + number.to_string()
    let f : ProtoField = match rng.next_below(4) {
      0 => {
        let t = scalars[rng.next_below(scalars.length())]
        { name, number, ptype: t, label: LSingular, options: [] }
      }
      1 => {
        let t = numerics[rng.next_below(numerics.length())]
        {
          name,
          number,
          ptype: t,
          label: LRepeated(packed=rng.next_bool()),
          options: [],
        }
      }
      2 => { name, number, ptype: PEnum("E"), label: LSingular, options: [] }
      _ =>
        {
          name,
          number,
          ptype: PMessage("Inner"),
          label: LSingular,
          options: [],
        }
    }
    fields.push(f)
  }
  let root : ProtoMessage = {
    name: "M",
    fields,
    maps: [],
    oneofs: [],
    reserved_numbers: [],
    reserved_names: [],
    nested_messages: [],
    nested_enums: [],
  }
  { messages: [root, inner], enums: [enum_e] }
}

///|
/// 为某消息生成一个匹配的类型化消息（字段随机设置/留空；设置项均为非默认）。
fn sg_random_message_for(
  rng : @infra_pbt.Rng,
  schema : ProtoSchema,
  name : String,
) -> TypedMessage {
  let pmsg = match schema.message(name) {
    Some(m) => m
    None => return TypedMessage::new()
  }
  let fields : Map[Int, TypedValue] = {}
  for f in pmsg.fields {
    if rng.next_bool() {
      let v : TypedValue = match f.label {
        LRepeated(..) => {
          let n = rng.next_range(1, 4)
          let arr : Array[TypedValue] = []
          for _i in 0..<n {
            arr.push(sg_value_for(rng, f.ptype))
          }
          TList(arr)
        }
        _ =>
          match f.ptype {
            PMessage(inner_name) =>
              TMsg(sg_random_message_for(rng, schema, inner_name))
            _ => sg_value_for(rng, f.ptype)
          }
      }
      fields[f.number] = v
    }
  }
  { fields, unknown: [] }
}

///|
/// （富模式, 类型化消息）对生成器；根消息恒为 "M"。
fn sg_gen_case() -> @infra_pbt.Gen[(ProtoSchema, TypedMessage)] {
  @infra_pbt.Gen::new(fn(rng) {
    let schema = sg_random_schema(rng)
    let m = sg_random_message_for(rng, schema, "M")
    (schema, m)
  })
}

// ─────────────────────── 含未知字段消息生成（P5）─────────────────────────

///|
/// （富模式, 含未知字段的类型化消息, 未知字段集）生成器。
///
/// 未知字段号取自高位区间（≥1000，必不与 M 的定义字段号 1..4 冲突），故解码后
/// 必落入 `unknown` 原样保留。
fn sg_gen_unknown_case() -> @infra_pbt.Gen[(ProtoSchema, TypedMessage)] {
  @infra_pbt.Gen::new(fn(rng) {
    let schema = sg_random_schema(rng)
    let base = sg_random_message_for(rng, schema, "M")
    let unknown : Array[FieldEntry] = []
    let k = rng.next_range(1, 3)
    for i in 0..<k {
      let number = 1000 + i
      let value : FieldValue = match rng.next_below(4) {
        0 => FieldValue::VVarint(rng.next())
        1 => FieldValue::VI64(rng.next())
        2 => FieldValue::VI32(rng.next().to_uint())
        _ => FieldValue::VBytes(sg_bytes(rng))
      }
      unknown.push(FieldEntry::new(number, value))
    }
    let with_unknown : TypedMessage = { fields: base.fields, unknown }
    (schema, with_unknown)
  })
}

// ─────────────────────────── 合法富模式生成（P7）─────────────────────────

///|
/// 合法富模式生成器：含枚举（首值 0）、scalar/repeated/enum/嵌套字段、一个 oneof、
/// 一个 map 与不冲突的 reserved；字段号唯一且在合法范围、引用可解析。
fn sg_gen_valid_schema() -> @infra_pbt.Gen[ProtoSchema] {
  @infra_pbt.Gen::new(fn(rng) {
    let enum_e : EnumDef = {
      name: "E",
      values: [("E0", 0), ("E1", 1), ("E2", 2)],
    }
    let inner : ProtoMessage = {
      name: "Inner",
      fields: [
        { name: "a", number: 1, ptype: PInt32, label: LSingular, options: [] },
      ],
      maps: [],
      oneofs: [],
      reserved_numbers: [],
      reserved_names: [],
      nested_messages: [],
      nested_enums: [],
    }
    let scalars = sg_scalar_types()
    let fields : Array[ProtoField] = []
    let mut num = 1
    let nscalar = rng.next_range(1, 3)
    for _i in 0..<nscalar {
      let t = scalars[rng.next_below(scalars.length())]
      fields.push({
        name: "f" + num.to_string(),
        number: num,
        ptype: t,
        label: LSingular,
        options: [],
      })
      num = num + 1
    }
    // 嵌套消息引用字段。
    fields.push({
      name: "child",
      number: num,
      ptype: PMessage("Inner"),
      label: LSingular,
      options: [],
    })
    num = num + 1
    // 枚举引用字段。
    fields.push({
      name: "st",
      number: num,
      ptype: PEnum("E"),
      label: LSingular,
      options: [],
    })
    num = num + 1
    // oneof 两成员。
    let o_a = num
    fields.push({
      name: "ca",
      number: o_a,
      ptype: PString,
      label: LOneof(group="c"),
      options: [],
    })
    num = num + 1
    let o_b = num
    fields.push({
      name: "cb",
      number: o_b,
      ptype: PInt32,
      label: LOneof(group="c"),
      options: [],
    })
    num = num + 1
    let oneofs : Array[OneofDef] = [{ name: "c", members: [o_a, o_b] }]
    // map 字段。
    let maps : Array[MapEntry] = [
      { name: "meta", number: num, key: PString, value: PInt32 },
    ]
    // 不冲突的 reserved（高位区间）。
    let reserved_numbers : Array[ReservedRange] = [{ lo: 500, hi: 510 }]
    let reserved_names : Array[String] = ["legacy"]
    let root : ProtoMessage = {
      name: "M",
      fields,
      maps,
      oneofs,
      reserved_numbers,
      reserved_names,
      nested_messages: [],
      nested_enums: [],
    }
    { messages: [root, inner], enums: [enum_e] }
  })
}

// ──────────────────── 解析 round-trip 富模式生成（P11）────────────────────

///|
/// 解析 round-trip 富模式生成器（扁平结构，与 `print_proto` 输出布局严格对齐）。
///
/// 结构：顶层枚举 E + 顶层消息 M。M 的 `fields` 数组布局为
/// [非 oneof 字段（升序）..., oneof 成员...]，与 print 先打印非 oneof 字段、再打印
/// oneof 块的顺序一致，从而 `parse_proto_full(print_proto(s)) == Ok(s)`。覆盖
/// oneof / map / reserved / 字段选项（packed）/ 全部标量类型 / repeated。
fn sg_gen_roundtrip_schema() -> @infra_pbt.Gen[ProtoSchema] {
  @infra_pbt.Gen::new(fn(rng) {
    let enum_e : EnumDef = {
      name: "E",
      values: [("E0", 0), ("E1", 1), ("E2", 2)],
    }
    let scalars = sg_scalar_types()
    let numerics = sg_numeric_types()
    let fields : Array[ProtoField] = []
    let mut num = 1
    // 非 oneof 字段：scalar / repeated 数值（packed 随机）/ 枚举引用。
    let nfields = rng.next_range(1, 4)
    for _i in 0..<nfields {
      let kind = rng.next_below(3)
      let f : ProtoField = if kind == 0 {
        let t = scalars[rng.next_below(scalars.length())]
        {
          name: "f" + num.to_string(),
          number: num,
          ptype: t,
          label: LSingular,
          options: [],
        }
      } else if kind == 1 {
        let t = numerics[rng.next_below(numerics.length())]
        {
          name: "f" + num.to_string(),
          number: num,
          ptype: t,
          label: LRepeated(packed=rng.next_bool()),
          options: [],
        }
      } else {
        {
          name: "f" + num.to_string(),
          number: num,
          ptype: PEnum("E"),
          label: LSingular,
          options: [],
        }
      }
      fields.push(f)
      num = num + 1
    }
    // 可选 oneof（两成员），成员追加到 fields 尾部（与 print 布局一致）。
    let oneofs : Array[OneofDef] = []
    if rng.next_bool() {
      let o_a = num
      fields.push({
        name: "ca",
        number: o_a,
        ptype: PString,
        label: LOneof(group="choice"),
        options: [],
      })
      num = num + 1
      let o_b = num
      fields.push({
        name: "cb",
        number: o_b,
        ptype: PInt32,
        label: LOneof(group="choice"),
        options: [],
      })
      num = num + 1
      oneofs.push({ name: "choice", members: [o_a, o_b] })
    }
    // 可选 map。
    let maps : Array[MapEntry] = []
    if rng.next_bool() {
      maps.push({ name: "meta", number: num, key: PString, value: PInt32 })
      num = num + 1
    }
    // 可选 reserved（高位区间，避免与字段号冲突；不影响 round-trip）。
    let reserved_numbers : Array[ReservedRange] = []
    let reserved_names : Array[String] = []
    if rng.next_bool() {
      reserved_numbers.push({ lo: 800, hi: 800 })
      reserved_numbers.push({ lo: 900, hi: 910 })
      reserved_names.push("old_a")
    }
    let root : ProtoMessage = {
      name: "M",
      fields,
      maps,
      oneofs,
      reserved_numbers,
      reserved_names,
      nested_messages: [],
      nested_enums: [],
    }
    { messages: [root], enums: [enum_e] }
  })
}
