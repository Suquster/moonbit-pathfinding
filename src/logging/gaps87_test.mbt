// gaps87_test.mbt —— parse_logfmt 余下拒绝臂（第八十七批）。

///|
/// parse_logfmt：未知 level 标签 → None。
test "parse_logfmt：未知 level 标签拒绝" {
  assert_true(parse_logfmt("ts=1 level=blah msg=\"m\"") is None)
}

///|
/// parse_logfmt：字段取值无法还原（整数溢出 Int64）→ None。
test "parse_logfmt：字段整数溢出拒绝" {
  assert_true(parse_logfmt("a=99999999999999999999999") is None)
}

///|
/// parse_logfmt：字段取值缺失（键后即行尾）→ None。
test "parse_logfmt：字段取值缺失拒绝" {
  assert_true(parse_logfmt("a=") is None)
}

///|
/// parse_logfmt：取值后紧跟非空白字符 → None。
test "parse_logfmt：取值后粘连字符拒绝" {
  assert_true(parse_logfmt("a=\"v\"x") is None)
}
