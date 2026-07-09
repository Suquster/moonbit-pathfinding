// rule_grammar_gaps_test.mbt —— 模式规则匹配边角收口
// （INFRA 第二十七批）。

///|
test "match_pattern：后缀不匹配与多模式顺延" {
  match parse_rules_full("%.o: %.c\n\tcc\n%.a: %.b\n\tab\n") {
    Ok(rs) => {
      // 后缀 .o 不匹配 → 顺延到 %.a 也不匹配 → None。
      assert_true(rs.match_pattern("x.z") is None)
      // 首模式后缀失配、次模式命中（None 分支顺延后成功）。
      match rs.match_pattern("y.a") {
        Some(r) => assert_eq(r.target, "y.a")
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}
