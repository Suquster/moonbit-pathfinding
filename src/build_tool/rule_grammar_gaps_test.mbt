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

///|
test "parse_rules_full：游离 TAB recipe 行忽略与空变量名拒绝" {
  // 游离 recipe 行（TAB 起始且无所属规则）被忽略。
  match @build_tool.parse_rules_full("\techo x\napp: a.o\n") {
    Ok(rs) => assert_eq(rs.rules.length(), 1)
    Err(_) => assert_true(false)
  }
  // 空变量名拒绝。
  assert_true(@build_tool.parse_rules_full("= v\n") is Err(_))
}

///|
test "parse_rules_full_with_includes：模式规则/phony/变量合并去重" {
  let resolve = fn(path : String) -> String? {
    if path == "sub.mk" {
      Some(
        "%.o: %.c\n\techo cc\n.PHONY: clean\nCC = gcc\nCC = clang\nclean:\n\techo rm\n",
      )
    } else {
      None
    }
  }
  match
    @build_tool.parse_rules_full_with_includes(
      "include sub.mk\nCC = tcc\napp: a.o\n", resolve,
    ) {
    Ok(rs) => {
      assert_eq(rs.pattern_rules.length(), 1)
      assert_true(rs.is_phony("clean"))
      // 主文件变量优先于 include 内定义。
      assert_true(rs.variables.get("CC") == Some("tcc"))
    }
    Err(_) => assert_true(false)
  }
}
