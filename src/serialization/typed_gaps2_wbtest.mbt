// typed_gaps2_wbtest.mbt —— typed 层余支防御测试（INFRA 第五十四批）：
// 标量解释类型错配拒绝、缺失 map 字段的编码跳过。

///|
test "typed：标量解释的类型/线型错配一律拒绝" {
  let empty = ProtoSchema::empty()
  // Varint 载荷喂给 Len 族类型。
  match typed_interpret_scalar(empty, PString, VVarint(1UL)) {
    Ok(_) => fail("PString 不应接受 VVarint")
    Err(_) => assert_true(true)
  }
  // I32 载荷喂给 Varint 族类型。
  match typed_interpret_scalar(empty, PBool, VI32(1U)) {
    Ok(_) => fail("PBool 不应接受 VI32")
    Err(_) => assert_true(true)
  }
  // I64 载荷喂给 I32 族类型。
  match typed_interpret_scalar(empty, PFloat, VI64(1UL)) {
    Ok(_) => fail("PFloat 不应接受 VI64")
    Err(_) => assert_true(true)
  }
}

///|
test "typed：schema 声明 map 而消息未设置 → 编码跳过" {
  let src =
    #|syntax = "proto3";
    #|message M {
    #|  map<string, int32> m = 3;
    #|}
  match parse_proto_full(src) {
    Ok(schema) =>
      match encode_typed(schema, "M", TypedMessage::new()) {
        Ok(bytes) => assert_eq(bytes.length(), 0)
        Err(e) => fail("空 map 编码不应失败：\{e}")
      }
    Err(e) => fail("proto 解析失败：\{e}")
  }
}
