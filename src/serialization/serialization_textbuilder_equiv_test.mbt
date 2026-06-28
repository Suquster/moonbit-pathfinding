// serialization_textbuilder_equiv_test.mbt —— 任务 12.1 等价性测试。
//
// 目标：验证「将 serialization 生产源文件中循环内字符串拼接（`out = out + ...`
// / `s = s + ...` / `name = name + ...` 等 O(n²) 反模式）替换为
// `@infra_text.TextBuilder` 后，每个被改造函数的输出与改造前**逐字符相等**」
// （production-hardening Requirement 1.5 / 1.6，AC：替换后输出逐字符等价）。
//
// 覆盖的被改造函数（均经其公开入口间接验证）：
//   * codegen.mbt        `gen_moonbit`            —— 黄金串精确比对；
//   * codegen_full.mbt   `gen_moonbit_full`       —— 黄金串精确比对；
//   * proto_grammar.mbt  `print_proto` / `pg_print_message` / `pg_print_enum` /
//                        `pg_print_field` / `pg_print_oneof_member` /
//                        `pg_join` / `pg_indent` —— 黄金串 + 复杂样例往返幂等；
//   * proto_grammar.mbt  `pg_parse_string_lit` / `pg_parse_option_value`
//                        —— 经 `parse_proto_full`（reserved 字符串字面量 / 字段
//                        选项裸记号）验证字符级累积正确；
//   * proto_parser.mbt   `parse_ident` / `parse_number`
//                        —— 经 `parse_proto` 验证标识符与字段号字符级累积；
//   * json.mbt           `json_join`              —— 经 `encode_json` 验证逗号
//                        连接逐字符相等。
//
// 这些函数的内部实现已改为 `@infra_text.TextBuilder`，其 `build()` 与等价顺序
// `+` 拼接逐字符相等（infra_text 设计 AC1/AC3 已由该包属性测试守护）；本文件
// 以确定性黄金值与往返幂等进一步固化「改造前后输出一致」这一行为契约。

///|
/// `gen_moonbit`（骨架代码生成）输出与改造前逐字符相等（黄金值）。
///
/// 验证 `out = out + ...` → `TextBuilder` 改造后输出不变（含 repeated →
/// `Array[元素类型]` 的映射与 `derive(Eq, Debug)` 收尾）。
test "gen_moonbit output is byte-identical to pre-refactor (golden)" {
  let schema : Schema = {
    messages: [
      {
        name: "M",
        fields: [
          { name: "i", number: 1, ftype: TInt32, repeated: false },
          { name: "tags", number: 2, ftype: TString, repeated: true },
        ],
      },
    ],
    enums: [],
  }
  let expected = "// 由 gen_moonbit 生成（骨架）—— 请勿手工编辑\n" +
    "\npub struct M {\n" +
    "  i : Int\n" +
    "  tags : Array[String]\n" +
    "} derive(Eq, Debug)\n"
  @test.assert_eq(gen_moonbit(schema), expected)
}

///|
/// `gen_moonbit_full`（完整代码生成）输出与改造前逐字符相等（黄金值）。
///
/// 验证多次循环内 `out = out + ...`（结构体、字段、委托编解码函数）改造为
/// 逐片段 `push_str` 后输出不变。
test "gen_moonbit_full output is byte-identical to pre-refactor (golden)" {
  let src =
    #|syntax = "proto3";
    #|message T {
    #|  int32 i = 1;
    #|  repeated string tags = 2;
    #|}
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("合法 .proto 不应解析失败：\{e}")
      return
    }
  }
  let expected = "// 由 gen_moonbit_full 生成 —— 请勿手工编辑\n" +
    "// 结构体提供类型化视图；编解码委托共享 encode_typed / decode_typed。\n" +
    "\npub struct T {\n" +
    "  i : Int\n" +
    "  tags : Array[String]\n" +
    "} derive(Eq, Debug)\n" +
    "\npub fn T_encode(schema : ProtoSchema, msg : TypedMessage) -> Result[Bytes, DecodeError] {\n" +
    "  encode_typed(schema, \"T\", msg)\n}\n" +
    "\npub fn T_decode(schema : ProtoSchema, bytes : Bytes) -> Result[TypedMessage, DecodeError] {\n" +
    "  decode_typed(schema, \"T\", bytes)\n}\n"
  @test.assert_eq(gen_moonbit_full(schema), expected)
}

///|
/// `print_proto`（规范打印）输出与改造前逐字符相等（黄金值）。
///
/// 单数标量字段无 packed 默认歧义，黄金值稳定；验证 `pg_print_message` /
/// `pg_print_field` / `pg_join` / `pg_indent` 改造后输出不变。
test "print_proto output is byte-identical to pre-refactor (golden)" {
  let src =
    #|syntax = "proto3";
    #|message M {
    #|  string name = 1;
    #|  int32 id = 2;
    #|}
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("合法 .proto 不应解析失败：\{e}")
      return
    }
  }
  let expected = "syntax = \"proto3\";\n" +
    "message M {\n" +
    "  string name = 1;\n" +
    "  int32 id = 2;\n" +
    "}\n"
  @test.assert_eq(print_proto(schema), expected)
}

///|
/// `print_proto` 对含 oneof / map / 嵌套 / reserved / 字段选项的复杂模式幂等。
///
/// 一次打印后再解析、再打印应得到完全相同的文本（往返幂等），由此覆盖
/// `pg_print_message`（嵌套 / oneof / map / reserved 全分支）、`pg_print_enum`、
/// `pg_print_oneof_member`、`pg_join`、`pg_indent` 的改造等价；同时
/// `reserved "old"` 经 `pg_parse_string_lit` 解析、`[packed = false]` 经
/// `pg_parse_option_value` 解析，验证字符级累积正确。
test "print_proto round-trip is idempotent on complex schema" {
  let src =
    #|syntax = "proto3";
    #|enum Color { COLOR_NONE = 0; RED = 1; }
    #|message Outer {
    #|  reserved 2, 9 to 11;
    #|  reserved "old";
    #|  int32 id = 1;
    #|  repeated int64 nums = 3 [packed = false];
    #|  Color color = 4;
    #|  oneof choice {
    #|    string s = 5;
    #|    int32 n = 6;
    #|  }
    #|  map<string, int32> meta = 7;
    #|  message Inner {
    #|    bool flag = 1;
    #|  }
    #|}
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("合法 .proto 不应解析失败：\{e}")
      return
    }
  }
  // `reserved "old"` 走 pg_parse_string_lit：字符级累积必须精确还原 "old"。
  let outer = match schema.message("Outer") {
    Some(m) => m
    None => {
      fail("应登记消息 Outer")
      return
    }
  }
  assert_true(outer.reserved_names == ["old"])
  // 往返幂等：print → parse → print 得到完全相同文本。
  let printed1 = print_proto(schema)
  let schema2 = match parse_proto_full(printed1) {
    Ok(s) => s
    Err(e) => {
      fail("打印结果应可再次解析：\{e}")
      return
    }
  }
  let printed2 = print_proto(schema2)
  @test.assert_eq(printed1, printed2)
}

///|
/// `parse_proto` 的标识符与字段号字符级累积正确（覆盖 parse_ident / parse_number）。
///
/// 长标识符（含下划线、数字）与多位字段号验证 `name = name + ...` /
/// `digits = digits + ...` → `TextBuilder.push_char` 改造后结果逐字符一致。
test "parse_proto accumulates identifiers and numbers correctly" {
  let src =
    #|message LongMessageName123 {
    #|  int32 field_with_underscore = 42;
    #|}
  let schema = match parse_proto(src) {
    Ok(s) => s
    Err(e) => {
      fail("合法 .proto 不应解析失败：\{e}")
      return
    }
  }
  @test.assert_eq(schema.messages.length(), 1)
  @test.assert_eq(schema.messages[0].name, "LongMessageName123")
  @test.assert_eq(schema.messages[0].fields.length(), 1)
  @test.assert_eq(schema.messages[0].fields[0].name, "field_with_underscore")
  @test.assert_eq(schema.messages[0].fields[0].number, 42)
}

///|
/// `encode_json` 的逗号连接逐字符相等（覆盖 json_join）。
///
/// 两个已设置字段的对象，`json_join` 以单个逗号分隔片段；黄金值验证
/// `s = s + ","` / `s = s + parts[i]` → `TextBuilder` 改造后输出不变。
test "encode_json comma-join is byte-identical to pre-refactor (golden)" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [
          {
            name: "a",
            number: 1,
            ptype: PString,
            label: LSingular,
            options: [],
          },
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
  let msg = TypedMessage::new().set(1, TStringV("x")).set(2, TStringV("y"))
  match encode_json(schema, "M", msg) {
    Ok(s) => @test.assert_eq(s, "{\"a\":\"x\",\"b\":\"y\"}")
    Err(e) => fail("JSON 编码不应失败：\{e}")
  }
}
