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
test "float_of：科学计数法指数形态" {
  let p = ctg_args([
    ("e1", "1.5e3"),
    ("e2", "2E-2"),
    ("e3", "-1.25e2"),
    ("bigpos", "1e999"),
    ("bigneg", "1e-999"),
    ("emptyexp", "1e"),
    ("twoexp", "1e2e3"),
    ("badexp", "1e+x"),
    ("badmant", "e5"),
  ])
  assert_true(p.float_of("e1") == Ok(1500.0))
  assert_true(p.float_of("e2") == Ok(0.02))
  assert_true(p.float_of("e3") == Ok(-125.0))
  match p.float_of("bigpos") {
    Ok(d) => assert_true(d > 1.0e308)
    Err(_) => assert_true(false)
  }
  assert_true(p.float_of("bigneg") == Ok(0.0))
  assert_true(p.float_of("emptyexp") == Err(BadFloat("emptyexp", "1e")))
  assert_true(p.float_of("twoexp") == Err(BadFloat("twoexp", "1e2e3")))
  assert_true(p.float_of("badexp") == Err(BadFloat("badexp", "1e+x")))
  assert_true(p.float_of("badmant") == Err(BadFloat("badmant", "e5")))
}

///|
test "validate_rules：VFloat 规则畸形值上报" {
  let p = ctg_args([("ratio", "1.x")])
  let errs = validate_rules(p, [rule("ratio", vtype=VFloat, required=true)])
  assert_eq(errs.length(), 1)
}
