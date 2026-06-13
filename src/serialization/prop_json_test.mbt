// prop_json_test.mbt —— Property 8：JSON↔二进制等价（任务 7.6）。
//
// Feature: serialization, Property 8: JSON↔二进制等价（JSON/binary equivalence）
//
// 对任意由生成器产出的（富模式, 类型化消息）对，经二进制往返（decode_typed ∘
// encode_typed）所得消息与经 JSON 往返（decode_json ∘ encode_json）所得消息内容
// 彼此相等。
//
// **Validates: Requirements 5.1, 5.2, 5.3, 5.5**

///|
/// 二进制往返结果。
fn pj_bin(schema : ProtoSchema, m : TypedMessage) -> TypedMessage? {
  match encode_typed(schema, "M", m) {
    Ok(b) =>
      match decode_typed(schema, "M", b) {
        Ok(x) => Some(x)
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
/// JSON 往返结果。
fn pj_json(schema : ProtoSchema, m : TypedMessage) -> TypedMessage? {
  match encode_json(schema, "M", m) {
    Ok(s) =>
      match decode_json(schema, "M", s) {
        Ok(x) => Some(x)
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
/// Feature: serialization, Property 8: JSON↔二进制等价（JSON/binary equivalence）
///
/// **Validates: Requirements 5.1, 5.2, 5.3, 5.5**
test "Feature: serialization, Property 8: JSON/binary equivalence" {
  let ok = @infra_pbt.holds_for_all(sg_gen_case(), fn(pair) {
    let (schema, m) = pair
    match (pj_bin(schema, m), pj_json(schema, m)) {
      (Some(a), Some(b)) => a == b
      _ => false
    }
  })
  assert_true(ok)
}
