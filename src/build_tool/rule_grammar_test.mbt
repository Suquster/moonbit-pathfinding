// rule_grammar_test.mbt —— 完整规则文法单元测试（任务 1.3）。
//
// 覆盖 recipe 捕获 / 变量展开 / 模式规则实例化 / phony / include 合并的具体见证，
// 以及缺 `:`、目标名为空、未解析 include 的 GrammarError 行列号（R1 / R2）。

///|
/// recipe 行原文保留（R1.2）。
test "parse_rules_full captures recipe lines" {
  match parse_rules_full("app: main.o\n\tgcc -o app main.o\n") {
    Ok(rs) =>
      match rs.recipe_of("app") {
        Some(r) => {
          assert_eq(r.lines.length(), 1)
          assert_true(r.lines[0] == "gcc -o app main.o")
        }
        None => fail("应有 app 的 recipe")
      }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// 变量定义与 `$(name)` 展开（R1.3）。
test "parse_rules_full expands defined variable" {
  match parse_rules_full("CC = gcc\napp: main.o\n\t$(CC) -o app main.o\n") {
    Ok(rs) => {
      assert_true(rs.variables.get("CC") == Some("gcc"))
      match rs.recipe_of("app") {
        Some(r) => assert_true(r.lines[0] == "gcc -o app main.o")
        None => fail("应有 recipe")
      }
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// 未定义变量展开为空串（R1.3）。
test "parse_rules_full expands undefined variable to empty" {
  match parse_rules_full("app: $(MISSING)\n") {
    Ok(rs) => {
      let g = rs.to_graph()
      assert_eq(g.nodes.length(), 1)
      assert_true(g.nodes[0] == Target::new("app"))
      assert_eq(g.edges.length(), 0)
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// 变量展开为多个依赖（R1.3）。
test "parse_rules_full expands variable into multiple deps" {
  match parse_rules_full("OBJS = a.o b.o\napp: $(OBJS)\n") {
    Ok(rs) => {
      let g = rs.to_graph()
      assert_eq(g.nodes.length(), 3)
      assert_eq(g.edges.length(), 2)
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// 模式规则保留并按词干 stem 实例化（R1.4）。
test "parse_rules_full stores pattern rule and instantiates stem" {
  match parse_rules_full("%.o: %.c\n\tgcc -c $*.c\n") {
    Ok(rs) => {
      assert_eq(rs.pattern_rules.length(), 1)
      match rs.match_pattern("foo.o") {
        Some(rule) => {
          assert_true(rule.target == "foo.o")
          assert_eq(rule.deps.length(), 1)
          assert_true(rule.deps[0] == "foo.c")
          assert_true(rule.recipe.lines[0] == "gcc -c foo.c")
        }
        None => fail("应匹配 foo.o")
      }
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// `.PHONY` 标记目标（R1.5）。
test "parse_rules_full marks phony targets" {
  match parse_rules_full(".PHONY: clean all\nclean:\n\trm -f app\n") {
    Ok(rs) => {
      assert_true(rs.is_phony("clean"))
      assert_true(rs.is_phony("all"))
      assert_false(rs.is_phony("app"))
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// include 合并入同一规则集（R1.6）。
test "parse_rules_full_with_includes merges included source" {
  let resolve = fn(path : String) -> String? {
    if path == "common.mk" {
      Some("util.o: util.c\n")
    } else {
      None
    }
  }
  match
    parse_rules_full_with_includes("include common.mk\napp: util.o\n", resolve) {
    Ok(rs) => {
      let g = rs.to_graph()
      assert_eq(g.nodes.length(), 3)
      assert_eq(g.edges.length(), 2)
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// 无解析器时 include 视作不可解析，报带位置的 GrammarError（R1.6 / R2.3）。
test "parse_rules_full reports unresolved include with position" {
  match parse_rules_full("include missing.mk\n") {
    Ok(_) => fail("无解析器的 include 应报错")
    Err(e) => assert_eq(e.pos.line, 1)
  }
}

///|
/// 缺 `:` 分隔符报带行号的 GrammarError（R2.1 / R2.3）。
test "parse_rules_full reports missing colon with position" {
  match parse_rules_full("app: a.o\nbroken line\n") {
    Ok(_) => fail("缺冒号应报错")
    Err(e) => assert_eq(e.pos.line, 2)
  }
}

///|
/// 目标名为空报带行号的 GrammarError（R2.2）。
test "parse_rules_full reports empty target name" {
  match parse_rules_full(": dep\n") {
    Ok(_) => fail("空目标名应报错")
    Err(e) => assert_eq(e.pos.line, 1)
  }
}

///|
/// GrammarError 投影回既有 ParseError（line 取 pos.line，R2.3）。
test "GrammarError to_legacy projects line" {
  match parse_rules_full("broken\n") {
    Ok(_) => fail("应报错")
    Err(e) => {
      let legacy = e.to_legacy()
      assert_eq(legacy.line, e.pos.line)
    }
  }
}
