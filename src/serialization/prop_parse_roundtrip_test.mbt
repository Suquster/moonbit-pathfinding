// prop_parse_roundtrip_test.mbt —— Property 11：proto 模式解析 round-trip（任务 3.3）。
//
// Feature: serialization, Property 11: proto 模式解析 round-trip（schema parse round-trip）
//
// 对任意由生成器产出的合法富模式 `s`，先规范打印再解析应得到等价模式：
//   `parse_proto_full(print_proto(s)) == Ok(s)`
// 验证完整 proto3 文法解析（含 oneof / map / reserved / 字段选项(packed) / 全部
// 标量类型 / repeated）的结构保真性。
//
// 说明（生成空间）：生成器产出**扁平**富模式（顶层 message + enum，无嵌套），其
// `fields` 数组布局与 `print_proto` 输出顺序严格对齐，从而 round-trip 逐字段相等。
// 嵌套类型解析由 `proto_grammar_test.mbt` 的具体样例单独验证。
//
// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

///|
/// Feature: serialization, Property 11: proto 模式解析 round-trip
///
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**
test "Feature: serialization, Property 11: schema parse round-trip" {
  let ok = @infra_pbt.holds_for_all(sg_gen_roundtrip_schema(), fn(s) {
    match parse_proto_full(print_proto(s)) {
      Ok(s2) => s2 == s
      Err(_) => false
    }
  })
  assert_true(ok)
}
