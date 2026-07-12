// 白盒测试：覆盖率审计收口（INFRA 第六十三批）——
// 进度令牌解析拒绝分支与进度生命周期百分比校验错误传播。

///|
test "parse_token：非整数数字与非法类型拒绝" {
  assert_true(parse_token(JNum("1.5")) is None)
  assert_true(parse_token(JBool(true)) is None)
}

///|
test "progress_of：令牌解析失败与 value 非对象拒绝" {
  let bad_token = JObj([("token", JBool(true)), ("value", JObj([]))])
  assert_true(progress_of(bad_token) is None)
  let bad_value = JObj([("token", JStr("t")), ("value", JStr("x"))])
  assert_true(progress_of(bad_value) is None)
}

///|
test "ProgressTracker：begin 百分比越界即报错" {
  let tr = ProgressTracker::new()
  let r = tr.observe(
    TokStr("t"),
    Begin(title="load", cancellable=None, message=None, percentage=Some(150)),
  )
  assert_true(r is Err(_))
}
