// prop_canonical_test.mbt —— Property 4：规范编码幂等（任务 7.2）。
//
// Feature: serialization, Property 4: 规范编码幂等（canonical-encoding idempotence）
//
// 对任意由生成器产出的（富模式, 类型化消息）对，对消息先确定性编码、再解码、再
// 确定性编码所得字节，与首次确定性编码逐字节相等：
//   `encode_canonical(decode_typed(encode_canonical(m))) == encode_canonical(m)`
// （字段号升序 + packed 数值标量）。
//
// **Validates: Requirements 2.3, 2.4, 2.6**

///|
/// 校验单个（schema, 消息）的规范编码幂等。
fn pc_check(schema : ProtoSchema, m : TypedMessage) -> Bool {
  let b1 = match encode_canonical(schema, "M", m) {
    Ok(b) => b
    Err(_) => return false
  }
  let m2 = match decode_typed(schema, "M", b1) {
    Ok(x) => x
    Err(_) => return false
  }
  let b2 = match encode_canonical(schema, "M", m2) {
    Ok(b) => b
    Err(_) => return false
  }
  b1 == b2
}

///|
/// Feature: serialization, Property 4: 规范编码幂等（canonical-encoding idempotence）
///
/// **Validates: Requirements 2.3, 2.4, 2.6**
test "Feature: serialization, Property 4: canonical-encoding idempotence" {
  let ok = @infra_pbt.holds_for_all(sg_gen_case(), fn(pair) {
    let (schema, m) = pair
    pc_check(schema, m)
  })
  assert_true(ok)
}

///|
/// 具体见证：字段号升序输出（确定性）。
test "encode_canonical orders fields by ascending number" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "M",
        fields: [
          { name: "a", number: 3, ptype: PInt32, label: LSingular, options: [] },
          { name: "b", number: 1, ptype: PInt32, label: LSingular, options: [] },
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
  let m = TypedMessage::new().set(3, TInt(7L)).set(1, TInt(9L))
  let bytes = match encode_canonical(schema, "M", m) {
    Ok(b) => b
    Err(e) => {
      fail("规范编码不应失败：\{e}")
      return
    }
  }
  // 解码回 wire，校验字段号升序（号 1 先于号 3）。
  match decode(bytes, Schema::empty()) {
    Ok(msg) => {
      @test.assert_eq(msg.fields[0].number, 1)
      @test.assert_eq(msg.fields[1].number, 3)
    }
    Err(e) => fail("解码不应失败：\{e}")
  }
}
