// demo_test.mbt —— 端到端实战 demo 单元测试（任务 9.2）。
//
// 串联 parse_proto_full → validate_schema → gen_moonbit_full → encode_typed →
// decode_typed → JSON 往返，断言二进制往返与 JSON 往返所得消息内容相等
// （R9.2, 9.3）。

///|
/// demo 端到端流程：解析 → 校验 → 生成 → 二进制往返 → JSON 往返 → 一致。
test "demo end-to-end: parse, validate, codegen, binary and JSON round-trip agree" {
  // 1. 解析实战 .proto。
  let schema = match parse_proto_full(demo_proto()) {
    Ok(s) => s
    Err(e) => {
      fail("demo .proto 不应解析失败：\{e}")
      return
    }
  }
  // 覆盖六类构造：标量 / repeated / 嵌套消息 / enum / oneof / map。
  let up = match schema.message(demo_message_name) {
    Some(m) => m
    None => {
      fail("应登记消息 UserProfile")
      return
    }
  }
  assert_true(up.oneofs.length() == 1) // oneof
  assert_true(up.maps.length() == 1) // map
  assert_true(schema.message("Address") is Some(_)) // 嵌套消息（顶层登记）

  // 2. 模式校验通过。
  match validate_schema(schema) {
    Ok(_) => assert_true(true)
    Err(errs) => fail("demo 模式应通过校验：\{@debug.to_string(errs)}")
  }

  // 3. 代码生成冒烟。
  let code = gen_moonbit_full(schema)
  assert_true(code.contains("pub struct UserProfile"))

  // 4. 二进制往返。
  let msg = demo_message()
  let bin_rt = match encode_typed(schema, demo_message_name, msg) {
    Ok(bytes) =>
      match decode_typed(schema, demo_message_name, bytes) {
        Ok(out) => out
        Err(e) => {
          fail("二进制解码不应失败：\{e}")
          return
        }
      }
    Err(e) => {
      fail("二进制编码不应失败：\{e}")
      return
    }
  }
  assert_true(bin_rt == msg)

  // 5. JSON 往返。
  let json_rt = match encode_json(schema, demo_message_name, msg) {
    Ok(text) =>
      match decode_json(schema, demo_message_name, text) {
        Ok(out) => out
        Err(e) => {
          fail("JSON 解码不应失败：\{e}")
          return
        }
      }
    Err(e) => {
      fail("JSON 编码不应失败：\{e}")
      return
    }
  }
  assert_true(json_rt == msg)

  // 6. 二进制往返与 JSON 往返一致（R9.3）。
  assert_true(bin_rt == json_rt)
}
