// codegen_full_test.mbt —— 完整代码生成单元测试（任务 7.8）。
//
// 断言生成文本含 pub struct / 字段 / Array / 委托编解码函数；对 demo 模式做生成
// 冒烟（R6.1, 6.2, 6.3, 6.4）。

///|
/// 生成文本应含结构体、字段、Array、委托编解码函数及对共享模型的引用。
test "gen_moonbit_full emits struct, fields, methods delegating to typed model" {
  let schema = match parse_proto_full(demo_proto()) {
    Ok(s) => s
    Err(e) => {
      fail("demo .proto 不应解析失败：\{e}")
      return
    }
  }
  let code = gen_moonbit_full(schema)
  // 结构体与字段（R6.1）。
  assert_true(code.contains("pub struct UserProfile"))
  assert_true(code.contains("pub struct Address"))
  assert_true(code.contains("name : String"))
  assert_true(code.contains("score : Double"))
  // repeated → Array[元素类型]（R6.2）。
  assert_true(code.contains("tags : Array[String]"))
  // 配套编解码函数委托共享类型化模型（R6.3）。
  assert_true(code.contains("UserProfile_encode"))
  assert_true(code.contains("UserProfile_decode"))
  assert_true(code.contains("encode_typed"))
  assert_true(code.contains("decode_typed"))
}

///|
/// 简单模式的生成含正确的类型映射（int32→Int, uint64→UInt64, bool→Bool）。
test "gen_moonbit_full maps scalar types to MoonBit types" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "T",
        fields: [
          { name: "i", number: 1, ptype: PInt32, label: LSingular, options: [] },
          {
            name: "u",
            number: 2,
            ptype: PUInt64,
            label: LSingular,
            options: [],
          },
          { name: "f", number: 3, ptype: PBool, label: LSingular, options: [] },
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
  let code = gen_moonbit_full(schema)
  assert_true(code.contains("i : Int"))
  assert_true(code.contains("u : UInt64"))
  assert_true(code.contains("f : Bool"))
}
