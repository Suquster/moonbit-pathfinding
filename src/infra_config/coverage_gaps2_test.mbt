// 黑盒测试：TOML 解析器转义序列 / 多行字符串 / Unicode 边界分支。

///|
test "toml：全量转义序列与 \\U 八位码点解析" {
  guard toml_parse("k = \"a\\b\\f\\t\\n\\r\\\"\\\\z\"") is Some(t1)
  guard toml_get(t1, "k") is Some(TomlString(s))
  assert_true(s.contains("z"))
  guard toml_parse("u = \"\\U0001D11E\"") is Some(t2)
  assert_true(toml_get(t2, "u") is Some(TomlString(_)))
  // 非法十六进制 / 代理区 / 越界码点拒绝。
  assert_true(toml_parse("x = \"\\u12G4\"") is None)
  assert_true(toml_parse("x = \"\\uD800\"") is None)
  assert_true(toml_parse("x = \"\\U00110000\"") is None)
  // 未知转义拒绝。
  assert_true(toml_parse("x = \"\\q\"") is None)
}

///|
test "toml：多行基本字符串的孤立引号 / 续行 / 未闭合" {
  // 孤立单引号照抄。
  guard toml_parse("m = \"\"\"a\"b\"\"\"") is Some(t1)
  guard toml_get(t1, "m") is Some(TomlString(s1))
  assert_true(s1.contains("\"") && s1.contains("a") && s1.contains("b"))
  // 行尾反斜杠续行吞掉空白。
  guard toml_parse("m = \"\"\"a\\\n   b\"\"\"") is Some(t2)
  guard toml_get(t2, "m") is Some(TomlString(s2))
  assert_eq(s2, "ab")
  // 未闭合多行字符串拒绝。
  assert_true(toml_parse("m = \"\"\"abc") is None)
  // CRLF 起始换行剥除。
  guard toml_parse("m = \"\"\"\r\nhi\"\"\"") is Some(t3)
  guard toml_get(t3, "m") is Some(TomlString(s3))
  assert_eq(s3, "hi")
}
