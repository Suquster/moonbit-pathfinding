// 白盒测试：覆盖率审计收口（INFRA 第七十二批）——
// logfmt 值解析失败与分隔符校验、traceparent 十六进制辅助、
// OTLP SpanKind 数值码。

///|
test "parse_logfmt：坏值 / 粘连分隔 / 缺失必备键均拒绝" {
  // 未闭合引号 → parse_value 失败。
  assert_true(parse_logfmt("ts=1 level=info k=\"unclosed") is None)
  // 值后紧跟非空白字符 → 分隔符校验失败。
  assert_true(parse_logfmt("ts=1 level=info k=\"v\"x") is None)
  // 缺 level → 必备键校验失败。
  assert_true(parse_logfmt("ts=1 k=2") is None)
}

///|
test "hex_char_val/hex_to_int：大写十六进制与非法字符" {
  assert_eq(hex_char_val('A'), 10)
  assert_eq(hex_char_val('F'), 15)
  assert_eq(hex_char_val('g'), -1)
  assert_true(hex_to_int("aB") is Some(0xAB))
  assert_true(hex_to_int("zz") is None)
}

///|
test "otlp_kind_code：Producer/Consumer 数值码" {
  assert_eq(otlp_kind_code(Producer), 4)
  assert_eq(otlp_kind_code(Consumer), 5)
}
