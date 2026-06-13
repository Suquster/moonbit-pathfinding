// prop_codegen_test.mbt —— Property 9：生成代码往返（任务 7.9）。
//
// Feature: serialization, Property 9: 生成代码往返（generated-code round-trip）
//
// 对任意由生成器产出的合法富模式与该模式下的类型化消息，`gen_moonbit_full` 所生成
// 结构体配套的编解码方法互逆。其行为由所委托的共享类型化编解码模型定义，故对该
// 模型断言 `decode_typed ∘ encode_typed == 恒等`（同时确保 `gen_moonbit_full` 对该
// 模式可成功生成）。
//
// **Validates: Requirements 6.3, 6.5**

///|
/// 校验生成可运行 + 委托模型往返自洽。
fn pcg_check(schema : ProtoSchema, m : TypedMessage) -> Bool {
  // 生成代码（委托 encode_typed / decode_typed），确保生成本身不崩溃且非空。
  let code = gen_moonbit_full(schema)
  if code.length() == 0 {
    return false
  }
  match encode_typed(schema, "M", m) {
    Ok(b) => decode_typed(schema, "M", b) == Ok(m)
    Err(_) => false
  }
}

///|
/// Feature: serialization, Property 9: 生成代码往返（generated-code round-trip）
///
/// **Validates: Requirements 6.3, 6.5**
test "Feature: serialization, Property 9: generated-code round-trip" {
  let ok = @infra_pbt.holds_for_all(sg_gen_case(), fn(pair) {
    let (schema, m) = pair
    pcg_check(schema, m)
  })
  assert_true(ok)
}
