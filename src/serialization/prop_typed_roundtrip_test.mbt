// prop_typed_roundtrip_test.mbt —— Property 2：类型化往返（旗舰深化，任务 5.3）。
//
// Feature: serialization, Property 2: 类型化往返（typed round-trip）
//
// 对任意由生成器产出的（富模式, 类型化消息）对，先 `encode_typed` 再
// `decode_typed` 得到与原消息内容相等的结果。统摄字段号→命名字段映射、sint
// zigzag、bool/enum、定长 float/double/fixed 位级解释、string/bytes 与嵌套消息
// 递归、repeated 聚合、proto3 默认值省略与未设置字段语义。
//
// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9**

///|
/// Feature: serialization, Property 2: 类型化往返（typed round-trip）
///
/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9**
test "Feature: serialization, Property 2: typed round-trip" {
  let ok = @infra_pbt.holds_for_all(sg_gen_case(), fn(pair) {
    let (schema, m) = pair
    match encode_typed(schema, "M", m) {
      Ok(bytes) =>
        match decode_typed(schema, "M", bytes) {
          Ok(out) => out == m
          Err(_) => false
        }
      Err(_) => false
    }
  })
  assert_true(ok)
}
