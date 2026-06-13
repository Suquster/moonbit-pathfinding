// prop_rule_grammar_roundtrip_test.mbt —— Property 1：规则解析 round-trip。
//
// 复用 @infra_pbt 的 holds_for_all（默认 ≥100 迭代）与 prop_support_test.mbt
// 的 gen_ruleset（随机含变量 / phony / 模式 / 具体规则的合法 RuleSet）。

///|
/// Feature: build-tool, Property 1: 规则解析 round-trip
///
/// 对任意由生成器产出的合法 `RuleSet` `rs`，先规范打印再解析应得到等价模型：
/// `parse_rules_full(print_rules(rs)) == Ok(rs)`。统摄目标 / 依赖登记与去重、
/// recipe 原文保留、变量定义、模式规则保留与注释 / 空行忽略的结构保真性。
///
/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.7**
test "Feature: build-tool, Property 1: rule parse round-trip" {
  let ok = @infra_pbt.holds_for_all(gen_ruleset(), fn(rs) {
    match parse_rules_full(print_rules(rs)) {
      Ok(rs2) => rs2 == rs
      Err(_) => false
    }
  })
  assert_true(ok)
}
