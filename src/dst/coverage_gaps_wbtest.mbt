// 白盒测试：trace_codec 整数记号解析器的边界拒绝路径。

///|
test "trace_codec：parse_int/u64/i64 记号边界拒绝与负数往返" {
  assert_true(parse_int_token("") is None)
  assert_true(parse_int_token("-") is None)
  assert_true(parse_int_token("1a") is None)
  assert_true(parse_int_token("-42") is Some(-42))
  assert_true(parse_u64_token("") is None)
  assert_true(parse_u64_token("9x") is None)
  assert_true(parse_u64_token("7") is Some(7UL))
  assert_true(parse_i64_token("") is None)
  assert_true(parse_i64_token("-") is None)
  assert_true(parse_i64_token("5z") is None)
  assert_true(parse_i64_token("-9") is Some(-9L))
}

///|
test "trace_codec：deserialize_result 截断输入拒绝" {
  assert_true(deserialize_result("") is Err(_))
  assert_true(deserialize_result("DST1") is Err(_))
}
