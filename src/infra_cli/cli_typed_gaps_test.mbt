// cli_typed_gaps_test.mbt —— 类型化取值缺席/畸形浮点分支收口
// （INFRA 第二十五批）。

///|
fn ctg_args(values : Array[(String, String)]) -> ParsedArgs {
  { command_path: [], flags: [], values, positionals: [] }
}

///|
test "bool_of / float_of：值缺席与假值形态" {
  let p = ctg_args([("off1", "off"), ("no1", "NO")])
  assert_true(p.bool_of("absent") == Err(NotPresent("absent")))
  assert_true(p.float_of("absent") == Err(NotPresent("absent")))
  assert_true(p.bool_of("off1") == Ok(false))
  assert_true(p.bool_of("no1") == Ok(false))
}

///|
test "float_of：畸形浮点各位置拒绝" {
  let p = ctg_args([
    ("nodot", "abc"), // 无小数点且非整数
    ("emptyfrac", "1."), // 小数部分为空
    ("badint", "x.5"), // 整数部分非法
    ("badfrac", "1.x"), // 小数部分非法
  ])
  assert_true(p.float_of("nodot") == Err(BadFloat("nodot", "abc")))
  assert_true(p.float_of("emptyfrac") == Err(BadFloat("emptyfrac", "1.")))
  assert_true(p.float_of("badint") == Err(BadFloat("badint", "x.5")))
  assert_true(p.float_of("badfrac") == Err(BadFloat("badfrac", "1.x")))
}

///|
test "validate_rules：VFloat 规则畸形值上报" {
  let p = ctg_args([("ratio", "1.x")])
  let errs = validate_rules(p, [rule("ratio", vtype=VFloat, required=true)])
  assert_eq(errs.length(), 1)
}
