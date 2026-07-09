// logfmt_gaps_test.mbt —— logfmt 解析畸形行各位置拒绝收口
// （INFRA 第二十六批）。

///|
test "parse_logfmt：键后无 = 与空键拒绝" {
  assert_true(parse_logfmt("key value") is None)
  assert_true(parse_logfmt("=v") is None)
}

///|
test "parse_logfmt：ts/level 字段非法值拒绝" {
  assert_true(parse_logfmt("ts=abc level=info msg=\"m\"") is None)
  assert_true(parse_logfmt("ts=1 level=weird msg=\"m\"") is None)
}

///|
test "parse_logfmt：普通字段值非法与粘连拒绝" {
  assert_true(parse_logfmt("ts=1 level=info k=\"unterminated") is None)
  assert_true(parse_logfmt("ts=1 level=info k=\"v\"x") is None)
}
