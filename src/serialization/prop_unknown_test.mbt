// prop_unknown_test.mbt —— Property 5：未知字段保留（任务 7.3）。
//
// Feature: serialization, Property 5: 未知字段保留（unknown-field preservation）
//
// 对任意由生成器产出的含未知字段消息，类型化解码再编码后，未知字段的字段号与
// 原始取值集合保持不变（解码保留、重编码写回）。
//
// **Validates: Requirements 2.1, 2.2, 2.7**

///|
/// 校验单个含未知字段消息的解码-再编码后未知字段不变。
fn pu_check(schema : ProtoSchema, m : TypedMessage) -> Bool {
  let bytes = match encode_typed(schema, "M", m) {
    Ok(b) => b
    Err(_) => return false
  }
  let out = match decode_typed(schema, "M", bytes) {
    Ok(x) => x
    Err(_) => return false
  }
  out.unknown == m.unknown
}

///|
/// Feature: serialization, Property 5: 未知字段保留（unknown-field preservation）
///
/// **Validates: Requirements 2.1, 2.2, 2.7**
test "Feature: serialization, Property 5: unknown-field preservation" {
  let ok = @infra_pbt.holds_for_all(sg_gen_unknown_case(), fn(pair) {
    let (schema, m) = pair
    pu_check(schema, m)
  })
  assert_true(ok)
}
