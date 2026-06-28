// json_test.mbt —— proto3 JSON 映射单元测试（任务 7.5）。
//
// 覆盖 camelCase 字段名、64 位整数为字符串、bytes base64、非法 JSON 的错误（R5.1, 5.4）。

///|
/// 单字段单消息富模式辅助。
fn js_schema(name : String, t : ProtoType) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [{ name, number: 1, ptype: t, label: LSingular, options: [] }],
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
/// 字段名 snake_case → camelCase（R5.1）。
test "encode_json renders field names in camelCase" {
  let schema = js_schema("user_name", PString)
  let m = TypedMessage::new().set(1, TStringV("bob"))
  match encode_json(schema, "M", m) {
    Ok(s) => {
      assert_true(s.contains("userName"))
      assert_false(s.contains("user_name"))
    }
    Err(e) => fail("JSON 编码不应失败：\{e}")
  }
}

///|
/// 64 位整数表示为 JSON 字符串（R5.1）。
test "encode_json renders 64-bit integers as JSON strings" {
  let schema = js_schema("big", PInt64)
  let m = TypedMessage::new().set(1, TInt(1234567890123L))
  match encode_json(schema, "M", m) {
    Ok(s) => {
      // 应含带引号的数值。
      assert_true(s.contains("\"1234567890123\""))
      // 解码回原值。
      match decode_json(schema, "M", s) {
        Ok(out) => assert_true(out.get(1) == Some(TInt(1234567890123L)))
        Err(e) => fail("JSON 解码不应失败：\{e}")
      }
    }
    Err(e) => fail("JSON 编码不应失败：\{e}")
  }
}

///|
/// bytes 以 base64 文本表示并往返（R5.1）。
test "encode_json renders bytes as base64 and round-trips" {
  let schema = js_schema("data", PBytes)
  let m = TypedMessage::new().set(1, TBytesV(b"\x00\x01\x02\xff"))
  match encode_json(schema, "M", m) {
    Ok(s) =>
      match decode_json(schema, "M", s) {
        Ok(out) => assert_true(out.get(1) == Some(TBytesV(b"\x00\x01\x02\xff")))
        Err(e) => fail("JSON 解码不应失败：\{e}")
      }
    Err(e) => fail("JSON 编码不应失败：\{e}")
  }
}

///|
/// base64 编解码自洽（具体见证）。
test "base64 encode/decode round-trips" {
  let cases : Array[Bytes] = [
    b"", b"f", b"fo", b"foo", b"foob", b"\x00\xff\x10",
  ]
  for c in cases {
    let enc = base64_encode(c)
    match base64_decode(enc) {
      Some(dec) => assert_true(dec == c)
      None => fail("base64 解码不应失败")
    }
  }
  // 经典向量。
  @test.assert_eq(base64_encode(b"foobar"), "Zm9vYmFy")
}

///|
/// 非法 JSON 返回携带定位的错误且不产生部分构造消息（R5.4）。
test "decode_json reports error on malformed JSON" {
  let schema = js_schema("name", PString)
  match decode_json(schema, "M", "{ this is not json") {
    Ok(_) => fail("非法 JSON 不应解码成功")
    Err(_) => assert_true(true)
  }
}
