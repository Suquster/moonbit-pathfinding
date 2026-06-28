// build_tool_textbuilder_equiv_test.mbt —— 任务 12.2 等价性测试。
//
// 目标：验证「将 build_tool 生产源文件中循环内字符串拼接（`out = out + ...`
// / `enc = enc + ...` / `s = s + c.to_string()` / `name = name + ...` 等
// O(n²) 反模式）替换为 `@infra_text.TextBuilder` 后，每个被改造函数的输出与
// 改造前**逐字符相等**」（production-hardening Requirement 1.5 / 1.6）。
//
// 覆盖的被改造函数（均经其公开入口直接或间接验证）：
//   * rule_grammar.mbt  `print_rules`        —— 黄金串精确比对 + 往返幂等；
//   * rule_grammar.mbt  `expand_vars`        —— 经 `parse_rules_full` 验证
//                        `$(name)` 变量名字符级累积与展开输出；
//   * rule_grammar.mbt  `subst_percent` / `subst_stem_var`
//                        —— 经 `PatternRule::instantiate` 验证 `%` / `$*`
//                        回填字符级累积；
//   * build_tool.mbt    `chars_to_string`    —— 经 `parse_rules_full` →
//                        `print_rules` 往返间接覆盖（切片字符序列物化）；
//   * cache.mbt         `serialize_cache`    —— 行式序列化黄金串精确比对；
//   * cache.mbt         `cache_key`          —— 长度前缀单射编码黄金串比对；
//   * cache.mbt         `action_fingerprint` —— 与手写 lp 编码经 `content_hash`
//                        的结果逐位相等；
//   * provenance.mbt    `derive_output_hash` —— 长度前缀单射编码黄金串比对。
//
// 这些函数内部已改为 `@infra_text.TextBuilder`，其 `build()` 与等价顺序 `+`
// 拼接逐字符相等（infra_text 设计 AC1/AC3 已由该包属性测试守护）；本文件以
// 确定性黄金值与往返幂等进一步固化「改造前后输出一致」这一行为契约。

///|
/// `print_rules`（规范化打印）输出与改造前逐字符相等（黄金值）。
///
/// 覆盖变量（按名升序）→ `.PHONY` → 模式规则 → 具体规则四段多重循环内
/// `out = out + ...` 改造为逐片段 `push_str` 后输出不变。
test "print_rules output is byte-identical to pre-refactor (golden)" {
  let rs : RuleSet = {
    rules: [
      {
        target: "app",
        deps: ["main.o", "util.o"],
        recipe: { lines: ["gcc -o app main.o util.o"] },
      },
    ],
    pattern_rules: [
      {
        target_pattern: "%.o",
        dep_patterns: ["%.c"],
        recipe: { lines: ["gcc -c $*.c"] },
      },
    ],
    variables: Map([("CC", "gcc")]),
    phony: ["clean", "all"],
  }
  let expected = "CC = gcc\n" +
    ".PHONY: clean all\n" +
    "%.o: %.c\n" +
    "\tgcc -c $*.c\n" +
    "app: main.o util.o\n" +
    "\tgcc -o app main.o util.o\n"
  @test.assert_eq(print_rules(rs), expected)
}

///|
/// `print_rules` → `parse_rules_full` → `print_rules` 往返幂等。
///
/// 一次打印后再解析、再打印应得到完全相同文本，间接覆盖 `chars_to_string`
/// （字符切片物化）与 `expand_vars`（无变量时恒等）的改造等价。
test "print_rules round-trip is idempotent" {
  let rs : RuleSet = {
    rules: [
      { target: "a.o", deps: ["a.c", "h.h"], recipe: { lines: ["cc -c a.c"] } },
      { target: "app", deps: ["a.o"], recipe: { lines: ["cc -o app a.o"] } },
    ],
    pattern_rules: [],
    variables: Map([]),
    phony: ["clean"],
  }
  let printed1 = print_rules(rs)
  let printed2 = match parse_rules_full(printed1) {
    Ok(rs2) => print_rules(rs2)
    Err(e) => {
      fail("打印结果应可再次解析：\{e}")
      return
    }
  }
  @test.assert_eq(printed1, printed2)
}

///|
/// `expand_vars` 经 `parse_rules_full` 验证变量名字符级累积与展开正确。
///
/// 长变量名 `LONGVARNAME` 验证内层 `name = name + cs[j].to_string()` →
/// `TextBuilder.push_char` 改造后逐字符还原，且 `$(LONGVARNAME)` 展开为多依赖。
test "expand_vars accumulates variable name and expands correctly" {
  match parse_rules_full("LONGVARNAME = x.o y.o\napp: $(LONGVARNAME)\n") {
    Ok(rs) => {
      assert_true(rs.variables.get("LONGVARNAME") == Some("x.o y.o"))
      let g = rs.to_graph()
      // 展开为两个依赖 x.o / y.o，加目标 app 共 3 个节点。
      @test.assert_eq(g.nodes.length(), 3)
    }
    Err(e) => fail("合法规则文本不应解析失败：\{e}")
  }
}

///|
/// 未定义变量经 `expand_vars` 展开为空串（覆盖 `out = out + "$"` 分支邻域）。
test "expand_vars expands undefined variable to empty string" {
  match parse_rules_full("app: pre$(MISSING)post\n") {
    Ok(rs) => {
      let g = rs.to_graph()
      // 依赖为 "prepost"（中间空串），加目标 app 共 2 个节点。
      @test.assert_eq(g.nodes.length(), 2)
      let mut found = false
      for n in g.nodes {
        if n.name == "prepost" {
          found = true
        }
      }
      assert_true(found)
    }
    Err(e) => fail("合法规则文本不应解析失败：\{e}")
  }
}

///|
/// `subst_percent` / `subst_stem_var` 经 `PatternRule::instantiate` 验证。
///
/// `%` 回填目标 / 依赖（`subst_percent`）、`$*` 回填命令（`subst_stem_var`）
/// 的循环内 `out = out + ...` 改造为逐片段 / 逐字符累积后输出不变。
test "PatternRule::instantiate substitutes stem byte-identically" {
  let pr : PatternRule = {
    target_pattern: "%.o",
    dep_patterns: ["%.c", "common.h"],
    recipe: { lines: ["gcc -c $*.c -o $*.o"] },
  }
  let r = pr.instantiate("foo")
  @test.assert_eq(r.target, "foo.o")
  assert_true(r.deps == ["foo.c", "common.h"])
  assert_true(r.recipe.lines == ["gcc -c foo.c -o foo.o"])
}

///|
/// `serialize_cache`（行式序列化）输出与改造前逐字符相等（黄金值）。
///
/// 覆盖四张指纹映射的四段循环内 `out = out + ...` 改造为逐片段 `push_str`
/// 后输出不变（含键升序与 `# section` 标记行）。
test "serialize_cache output is byte-identical to pre-refactor (golden)" {
  let c = BuildCache::new()
  c.observe("app", 100L, "h1")
  c.mark_built("app") // 固化基线：recorded == 当前
  c.observe("lib", 50L, "h0") // 仅当前侧新增
  let expected = "# recorded_mtimes\n" +
    "M app 100\n" +
    "# recorded_hashes\n" +
    "H app h1\n" +
    "# current_mtimes\n" +
    "m app 100\n" +
    "m lib 50\n" +
    "# current_hashes\n" +
    "h app h1\n" +
    "h lib h0\n"
  @test.assert_eq(serialize_cache(c), expected)
}

///|
/// `cache_key`（长度前缀单射编码）输出与改造前逐字符相等（黄金值）。
///
/// 验证循环内 `out = out + lp(h)` → 逐片段 `push_str` 改造后，目标 / 输入数 /
/// 各输入哈希 / 动作指纹的编码顺序与内容逐字符不变（`lp(s) = len|s`）。
test "cache_key output is byte-identical to pre-refactor (golden)" {
  // lp("app")="3|app", lp("2")="1|2", lp("h1")="2|h1", lp("h2")="2|h2",
  // lp("fp")="2|fp"，顺序拼接得：
  @test.assert_eq(cache_key("app", ["h1", "h2"], "fp"), "3|app1|22|h12|h22|fp")
}

///|
/// `derive_output_hash`（长度前缀单射编码）输出与改造前逐字符相等（黄金值）。
///
/// 验证循环内 `out = out + lp(h)` → 逐片段 `push_str` 改造后，动作指纹 /
/// 输入数 / 各输入哈希的编码顺序与内容逐字符不变。
test "derive_output_hash output is byte-identical to pre-refactor (golden)" {
  // lp("fp")="2|fp", lp("2")="1|2", lp("h1")="2|h1", lp("h2")="2|h2"。
  @test.assert_eq(derive_output_hash(["h1", "h2"], "fp"), "2|fp1|22|h12|h2")
}

///|
/// `action_fingerprint` 与手写 lp 编码经 `content_hash` 的结果逐位相等。
///
/// 验证循环内 `enc = enc + lp(line)` → `TextBuilder` 改造后，喂入 `content_hash`
/// 的长度前缀编码逐字符不变（"cc -c a" 长 7、"ld a" 长 4）。
test "action_fingerprint feeds identical length-prefixed encoding" {
  let recipe : Recipe = { lines: ["cc -c a", "ld a"] }
  // lp("cc -c a")="7|cc -c a", lp("ld a")="4|ld a"。
  let expected_enc = "7|cc -c a" + "4|ld a"
  @test.assert_eq(action_fingerprint(recipe), content_hash(expected_enc))
}
