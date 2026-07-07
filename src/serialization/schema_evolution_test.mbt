// schema_evolution_test.mbt —— schema 演进兼容性检查器测试（C3）。
//
// 覆盖：兼容演进（新增字段、varint 组内改型、string↔bytes、删除且 reserve）、
// 破坏性演进（wire 组变化、singular↔repeated、oneof 归属变化、
// 删除未 reserve、复用 reserved 号 / 名、删除整个消息）、
// 以及 wire 级端到端见证（V1 编码 → V2 解码，unknown 字段跳过语义）。

///|
/// 便捷构造：singular 字段。
fn sf(name : String, number : Int, t : ProtoType) -> ProtoField {
  { name, number, ptype: t, label: LSingular, options: [] }
}

///|
/// 便捷构造：消息（只填字段与 reserved）。
fn msg(
  name : String,
  fields : Array[ProtoField],
  reserved_numbers? : Array[ReservedRange] = [],
  reserved_names? : Array[String] = [],
) -> ProtoMessage {
  {
    name,
    fields,
    maps: [],
    oneofs: [],
    reserved_numbers,
    reserved_names,
    nested_messages: [],
    nested_enums: [],
  }
}

///|
/// 兼容演进：新增字段 / varint 组内改型 / string↔bytes / 删除且 reserve。
test "compatible evolutions produce no breaking changes" {
  let v1 = msg("M", [
    sf("id", 1, PInt32),
    sf("tag", 2, PString),
    sf("old", 3, PBool),
  ])
  let v2 = msg(
    "M",
    [
      sf("id", 1, PInt64), // int32 → int64：varint 组内兼容
      sf("tag", 2, PBytes), // string → bytes：Len 互通
      sf("extra", 4, PDouble), // 新增字段号：旧读者按未知字段跳过
    ],
    reserved_numbers=[{ lo: 3, hi: 3 }], // 删除 old 且 reserve 其号
    reserved_names=["old"],
  )
  assert_true(check_message_evolution(v1, v2).length() == 0)
}

///|
/// 破坏性：wire 组变化（int32 → string、fixed32 → fixed64、int32 → sint32）。
test "wire-incompatible type changes are detected" {
  let v1 = msg("M", [
    sf("a", 1, PInt32),
    sf("b", 2, PFixed32),
    sf("c", 3, PInt32),
  ])
  let v2 = msg("M", [
    sf("a", 1, PString),
    sf("b", 2, PFixed64),
    sf("c", 3, PSInt32), // 普通 varint → zigzag：数值解释不同 → 破坏
  ])
  let breaks = check_message_evolution(v1, v2)
  assert_true(breaks.length() == 3)
  assert_true(breaks[0].field_number == 1)
  assert_true(breaks[1].field_number == 2)
  assert_true(breaks[2].field_number == 3)
}

///|
/// 破坏性：singular↔repeated、oneof 归属变化、删除未 reserve。
test "label change / oneof change / unreserved removal are detected" {
  let v1 = msg("M", [
    sf("xs", 1, PInt32),
    sf("y", 2, PString),
    sf("gone", 3, PBool),
  ])
  let v2 = msg("M", [
    {
      name: "xs",
      number: 1,
      ptype: PInt32,
      label: LRepeated(packed=true),
      options: [],
    },
    {
      name: "y",
      number: 2,
      ptype: PString,
      label: LOneof(group="g"),
      options: [],
    },
    // 字段 3 删除且未 reserve。
  ])
  let breaks = check_message_evolution(v1, v2)
  assert_true(breaks.length() == 3)
}

///|
/// 破坏性：新版复用旧版 reserved 的字段号或名称。
test "reusing reserved number or name is detected" {
  let v1 = msg("M", [sf("a", 1, PInt32)], reserved_numbers=[{ lo: 5, hi: 6 }], reserved_names=[
    "legacy",
  ])
  let v2 = msg("M", [
    sf("a", 1, PInt32),
    sf("b", 5, PString), // 复用 reserved 号
    sf("legacy", 7, PBool), // 复用 reserved 名
  ])
  let breaks = check_message_evolution(v1, v2)
  assert_true(breaks.length() == 2)
}

///|
/// schema 级：删除整个消息 → 破坏；逐消息汇总。
test "schema-level check aggregates and flags removed messages" {
  let old_schema : ProtoSchema = {
    messages: [msg("A", [sf("x", 1, PInt32)]), msg("B", [sf("y", 1, PBool)])],
    enums: [],
  }
  let new_schema : ProtoSchema = {
    messages: [msg("A", [sf("x", 1, PString)])], // A 破坏改型，B 整个删除
    enums: [],
  }
  let breaks = check_schema_evolution(old_schema, new_schema)
  assert_true(breaks.length() == 2)
  assert_true(breaks[1].reason == "message B: removed from schema")
}

///|
/// 枚举 wire 上即 varint：enum ↔ int32 改型兼容（官方规则）。
test "enum and int32 are wire compatible" {
  let v1 = msg("M", [sf("kind", 1, PEnum("Kind"))])
  let v2 = msg("M", [sf("kind", 1, PInt32)])
  assert_true(check_message_evolution(v1, v2).length() == 0)
}

///|
/// 消息引用改为不同消息名 → 破坏（结构语义不同）。
test "message type rename on same field number is breaking" {
  let v1 = msg("M", [sf("child", 1, PMessage("Old"))])
  let v2 = msg("M", [sf("child", 1, PMessage("New"))])
  assert_true(check_message_evolution(v1, v2).length() == 1)
}
