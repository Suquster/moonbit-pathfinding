// prop_validate_test.mbt —— Property 7：合法模式校验通过（任务 3.6）。
//
// Feature: serialization, Property 7: 合法模式校验通过（valid-schema acceptance）
//
// 对任意由生成器产出的合法富模式（字段号合法且唯一、不触保留、类型引用可解析、
// proto3 枚举首值为 0），`validate_schema` 返回成功且不报告任何诊断。
//
// **Validates: Requirements 4.1, 4.6, 4.7**

///|
/// Feature: serialization, Property 7: 合法模式校验通过（valid-schema acceptance）
///
/// **Validates: Requirements 4.1, 4.6, 4.7**
test "Feature: serialization, Property 7: valid-schema acceptance" {
  let ok = @infra_pbt.holds_for_all(sg_gen_valid_schema(), fn(s) {
    match validate_schema(s) {
      Ok(_) => true
      Err(_) => false
    }
  })
  assert_true(ok)
}
