// typed_test.mbt —— 类型化编解码单元测试（任务 5.2）。
//
// 覆盖默认值标量不写入字节、未设置字段读取取默认值、嵌套消息递归、map 的 wire
// 等价编码（R1.7, 1.8, 3.3）。

///|
/// 单字段单消息富模式辅助。
fn tt_scalar_schema(t : ProtoType) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [
          { name: "x", number: 1, ptype: t, label: LSingular, options: [] },
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
}

///|
/// proto3 默认值标量不写入 wire 字节（R1.7）。
test "encode_typed omits default-valued scalar" {
  let schema = tt_scalar_schema(PInt32)
  let m = TypedMessage::new().set(1, TInt(0L))
  match encode_typed(schema, "M", m) {
    Ok(bytes) => @test.assert_eq(bytes.length(), 0)
    Err(e) => fail("编码不应失败：\{e}")
  }
  // 非默认值则写入。
  let m2 = TypedMessage::new().set(1, TInt(5L))
  match encode_typed(schema, "M", m2) {
    Ok(bytes) => assert_true(bytes.length() > 0)
    Err(e) => fail("编码不应失败：\{e}")
  }
}

///|
/// 未设置标量字段经 get_or_default 取其类型默认值（R1.8）。
test "get_or_default returns type default for unset scalar" {
  let schema = tt_scalar_schema(PString)
  let pmsg = schema.message("M").unwrap()
  let m = TypedMessage::new()
  assert_true(m.get_or_default(pmsg, 1) == TStringV(""))
  assert_true(m.get(1) is None)
}

///|
/// 嵌套消息递归编解码往返（R1.5）。
test "encode_typed/decode_typed handle nested messages recursively" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [
          {
            name: "child",
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
          { name: "a", number: 1, ptype: PInt32, label: LSingular, options: [] },
          {
            name: "b",
            number: 2,
            ptype: PString,
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
    ],
    enums: [],
  }
  let inner = TypedMessage::new().set(1, TInt(7L)).set(2, TStringV("hi"))
  let m = TypedMessage::new().set(1, TMsg(inner))
  match encode_typed(schema, "M", m) {
    Ok(bytes) =>
      match decode_typed(schema, "M", bytes) {
        Ok(out) => assert_true(out == m)
        Err(e) => fail("嵌套解码不应失败：\{e}")
      }
    Err(e) => fail("嵌套编码不应失败：\{e}")
  }
}

///|
/// map 字段以 `{1:key, 2:value}` 条目消息的 wire 形态编码并往返（R3.3）。
test "map field round-trips via wire-equivalent entry messages" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [],
        maps: [{ name: "meta", number: 1, key: PString, value: PInt32 }],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
  let m = TypedMessage::new().set(
    1,
    TMap([(TStringV("level"), TInt(7L)), (TStringV("rank"), TInt(3L))]),
  )
  match encode_typed(schema, "M", m) {
    Ok(bytes) =>
      match decode_typed(schema, "M", bytes) {
        Ok(out) => assert_true(out == m)
        Err(e) => fail("map 解码不应失败：\{e}")
      }
    Err(e) => fail("map 编码不应失败：\{e}")
  }
}
