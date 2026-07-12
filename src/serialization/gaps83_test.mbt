// gaps83_test.mbt —— 向下投影 uint64/enum 类型臂（第八十三批）。

///|
fn g83_field(name : String, number : Int, t : ProtoType) -> ProtoField {
  { name, number, ptype: t, label: LSingular, options: [] }
}

///|
/// proto_type_to_legacy：PUInt64 → TUInt64、PBool → TBool、PEnum → TEnum 投影臂。
test "to_legacy：uint64/bool/enum 类型投影" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "T",
        fields: [
          g83_field("u", 1, PUInt64),
          g83_field("e", 2, PEnum("Color")),
          g83_field("b", 3, PBool),
        ],
        oneofs: [],
        maps: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [{ name: "Color", values: [("RED", 0)] }],
  }
  let legacy = schema.to_legacy()
  let m = legacy.messages[0]
  assert_true(m.fields[0].ftype is TUInt64)
  assert_true(m.fields[1].ftype is TEnum(_))
  assert_true(m.fields[2].ftype is TBool)
}
