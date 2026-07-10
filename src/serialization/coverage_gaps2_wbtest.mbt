// 白盒测试：覆盖率审计收口（INFRA 第四十六批）——
// codegen/schema_model 类型映射余支、JSON map 键边界、proto 文法
// option 值 EOF、块跳过嵌套深度、legacy 类型名、schema 校验 map 值引用。

///|
test "codegen / schema_model：类型名与 legacy 映射余支" {
  assert_eq(moonbit_type_name(TUInt64), "UInt64")
  assert_eq(moonbit_type_name(TEnum("Color")), "Color")
  assert_true(proto_type_to_legacy(PUInt32) == TUInt32)
  assert_true(proto_type_to_legacy(PMessage("M")) == TMessage("M"))
}

///|
test "json：map 键渲染缺省与无符号键解析拒绝" {
  // 非法组合（bytes 键 + 布尔值）落入缺省空串分支。
  assert_eq(json_map_key_string(PBytes, TBoolV(true)), "")
  assert_true(json_parse_map_key(PUInt32, "xx") is None)
}

///|
test "proto_grammar：option 值 EOF 边界" {
  let empty = @parser_combinator.Input::from_string("")
  assert_true(pg_parse_option_value(empty) is None)
  // 标识符延伸到输入末尾（EOF 终止扫描）。
  match pg_parse_option_value(@parser_combinator.Input::from_string("abc")) {
    Some((s, _)) => assert_eq(s, "abc")
    None => assert_true(false)
  }
}

///|
test "proto_parser：skip_block 嵌套深度与 legacy int64 类型名" {
  assert_true(
    skip_block(@parser_combinator.Input::from_string("a { b } }")) is Ok(_),
  )
  assert_true(field_type_of("int64") == TInt64)
}

///|
test "schema_validate：map 值类型引用不可解析报错" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [],
        maps: [{ name: "m", number: 1, key: PString, value: PMessage("Ghost") }],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
  match validate_schema(schema) {
    Err(errors) => {
      assert_eq(errors.length(), 1)
      assert_true(errors[0] is UnresolvedTypeRef(..))
    }
    Ok(_) => assert_true(false)
  }
}

///|
test "proto_service：顶层枚举打印与畸形枚举拒绝" {
  match parse_proto_file("syntax = \"proto3\"; enum E { E0 = 0; }") {
    Ok(file) => {
      let printed = print_proto_file(file)
      assert_true(printed.contains("enum E"))
    }
    Err(_) => assert_true(false)
  }
  assert_true(parse_proto_file("enum E {") is Err(_))
}
