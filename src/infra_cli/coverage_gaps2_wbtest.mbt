// 白盒测试：CLI 错误 Show 渲染与整数记号解析边界。

///|
test "cli：CliError 与 TypedError Show 全分支渲染" {
  let mv = CliError::MissingValue("--out")
  assert_true("\{mv}".contains("missing value"))
  let np = TypedError::NotPresent("name")
  let bi = TypedError::BadInt("n", "x")
  let bf = TypedError::BadFloat("f", "y")
  let bb = TypedError::BadBool("b", "z")
  let nc = TypedError::NotInChoices("c", "w")
  assert_true("\{np}".contains("missing required"))
  assert_true("\{bi}".contains("not an integer"))
  assert_true("\{bf}".contains("not a number"))
  assert_true("\{bb}".contains("not a boolean"))
  assert_true("\{nc}".contains("invalid choice"))
}

///|
test "cli：parse_int_text 空串与孤立符号拒绝" {
  assert_true(parse_int_text("") is None)
  assert_true(parse_int_text("-") is None)
  assert_true(parse_int_text("+") is None)
  assert_true(parse_int_text("+7") is Some(7L))
  assert_true(parse_int_text("-7") is Some(-7L))
}
