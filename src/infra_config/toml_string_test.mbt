// toml_string_test.mbt —— TOML 字符串规范收口（INFRA 第五十二批）：
// 多行定界符紧邻引号内容、连续 6+ 引号拒绝、控制字符拒绝。

///|
fn tst_str(text : String, key : String) -> String? {
  match @infra_config.toml_parse(text) {
    Some(t) =>
      match @infra_config.toml_get(t, key) {
        Some(@infra_config.TomlString(s)) => Some(s)
        _ => None
      }
    None => None
  }
}

///|
test "toml 字符串：多行定界符紧邻引号内容（1–2 个）" {
  // """"内容"""" → 内容前后各带一个引号。
  assert_true(tst_str("a = \"\"\"\"x\"\"\"\"", "a") == Some("\"x\""))
  // 结尾两个内容引号（共 5 连引号收尾）。
  assert_true(tst_str("a = \"\"\"x\"\"\"\"\"", "a") == Some("x\"\""))
  // 字面量多行同理。
  assert_true(tst_str("a = ''''y''''", "a") == Some("'y'"))
  assert_true(tst_str("a = '''y'''''", "a") == Some("y''"))
  // 空多行字符串。
  assert_true(tst_str("a = \"\"\"\"\"\"", "a") == Some(""))
  assert_true(tst_str("a = ''''''", "a") == Some(""))
  // 中间的 1–2 连引号是普通内容。
  assert_true(tst_str("a = \"\"\"x\"\"y\"\"\"", "a") == Some("x\"\"y"))
  assert_true(tst_str("a = '''x''y'''", "a") == Some("x''y"))
}

///|
test "toml 字符串：连续 6+ 引号拒绝" {
  assert_true(@infra_config.toml_parse("a = \"\"\"x\"\"\"\"\"\"") is None)
  assert_true(@infra_config.toml_parse("a = '''x''''''") is None)
}

///|
test "toml 字符串：未转义控制字符拒绝" {
  // 基本字符串内的 U+0001 / DEL。
  assert_true(@infra_config.toml_parse("a = \"x\u0001y\"") is None)
  assert_true(@infra_config.toml_parse("a = \"x\u007Fy\"") is None)
  // 单行基本/字面量字符串内的裸 CR。
  assert_true(@infra_config.toml_parse("a = \"x\ry\"") is None)
  assert_true(@infra_config.toml_parse("a = 'x\ry'") is None)
  // 字面量字符串内的 U+0002。
  assert_true(@infra_config.toml_parse("a = 'x\u0002y'") is None)
  // 多行字符串禁控制符但放行换行与制表符。
  assert_true(@infra_config.toml_parse("a = \"\"\"x\u0003y\"\"\"") is None)
  assert_true(@infra_config.toml_parse("a = '''x\u001Fy'''") is None)
  assert_true(tst_str("a = \"\"\"x\ny\tz\"\"\"", "a") == Some("x\ny\tz"))
  assert_true(tst_str("a = '''x\ny\tz'''", "a") == Some("x\ny\tz"))
}
