// gaps91_test.mbt —— proto 打印嵌套枚举余臂（第九十一批）。

///|
/// print_proto：消息内嵌套枚举按缩进渲染。
test "print_proto：嵌套枚举渲染" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [],
        maps: [],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: ["Color"],
      },
    ],
    enums: [{ name: "Color", values: [("RED", 0), ("BLUE", 1)] }],
  }
  let out = print_proto(schema)
  assert_true(out.contains("enum Color"))
  assert_true(out.contains("RED = 0;"))
}
