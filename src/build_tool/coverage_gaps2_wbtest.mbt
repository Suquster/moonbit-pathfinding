// 白盒测试：规则文法内部辅助函数边界分支。

///|
test "rule_grammar：变量展开未闭合 / 模式匹配边界 / GrammarError Show" {
  // 未闭合 $( → 按字面 $ 输出。
  let vars : Map[String, String] = Map([("X", "v")])
  assert_eq(expand_vars("a$(X)b$(unclosed", vars), "avb$(unclosed")
  // 无 % 的模式：全等才匹配。
  assert_true(pattern_stem("abc", "abc") == Some(""))
  assert_true(pattern_stem("abc", "abd") is None)
  // 目标短于前后缀。
  assert_true(pattern_stem("lib%.o", "a.o") is None)
  // 前缀失配。
  assert_true(pattern_stem("lib%.o", "xib_a.o") is None)
  // GrammarError Show 渲染。
  guard parse_rules_full("a: b\n\techo\n  bad indent") is Err(e)
  assert_true("\{e}".length() > 0)
}

///|
test "rule_grammar：行首空白计数" {
  assert_eq(leading_ws_count([' ', ' ', 'x']), 2)
  assert_eq(leading_ws_count(['x']), 0)
}
