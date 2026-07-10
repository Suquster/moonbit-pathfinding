// toml_gaps2_test.mbt —— TOML 余支防御测试（INFRA 第五十四批）：
// 日期形态判定、数值词法拒绝、空数组。

///|
test "toml 余支：日期/日期时间形态拒绝" {
  // 10 字符但分隔符不是 '-'。
  assert_true(@infra_config.toml_parse("a = 1979/05/27") is None)
  assert_true(@infra_config.toml_parse("a = 1979-05x27T00:00:00Z") is None)
  // 时间字段非两位数字。
  assert_true(@infra_config.toml_parse("a = 1979-05-27T0a:00:00Z") is None)
  // 月/日越界。
  assert_true(@infra_config.toml_parse("a = 1979-13-01") is None)
  assert_true(@infra_config.toml_parse("a = 1979-02-30") is None)
}

///|
test "toml 余支：数值词法拒绝与空数组" {
  // 整数中混入字母。
  assert_true(@infra_config.toml_parse("a = 12x4") is None)
  // 浮点尾部残留非法字符。
  assert_true(@infra_config.toml_parse("a = 1.5e2z") is None)
  // 小数点后无数字 / 指数无数字。
  assert_true(@infra_config.toml_parse("a = 1.e2") is None)
  assert_true(@infra_config.toml_parse("a = 1.5e") is None)
  // 空数组。
  match @infra_config.toml_parse("a = [ ]") {
    Some(t) =>
      assert_true(
        @infra_config.toml_get(t, "a") is Some(@infra_config.TomlArray([])),
      )
    None => fail("空数组应可解析")
  }
}
