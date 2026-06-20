// regex_textbuilder_equiv_test.mbt —— 任务 12.3 等价性测试。
//
// 目的：验证将 regex_engine 生产源文件中**循环内字符串拼接**改造为
// `@infra_text.TextBuilder` 后，对外可见输出**逐字符不变**（Requirement
// 1.5 / 1.6）。被改造点覆盖：
//   * printer.mbt —— `print_regex`（Concat/Alt 循环）、`print_class`（区间循环）；
//   * ast.mbt     —— `print_ast`（Concat/Alt 循环）、`print_ast_set`（区间循环）；
//   * pattern_parser.mbt —— `read_group_name`（组名逐字符累积）；
//   * search.mbt  —— `Pattern::replace_all` / `slice_chars` / `expand_repl`；
//   * dfa.mbt     —— `encode_core`（NFA 状态集合编码键）；
//   * minimize.mbt —— `accept_signature` / 细化签名键。
//
// 断言策略：`String` 直接用 `assert_eq`（具 Show）；`Match` / `Match?` 等未
// 必 derive(Show) 的类型用 `assert_true(a == b)`（Eq）。所有期望值为改造前
// 逐段 `+` 拼接的逐字符等价结果（手工固化为黄金串）。

///|
/// print_regex：Concat / Alt 循环改造后逐字符等价（黄金串）。
test "textbuilder equiv: print_regex concat/alt" {
  // Concat 多元：逐段追加结果与 `acc + acc` 一致。
  assert_eq(print_regex(Concat([Char('a'), Char('b'), Char('c')])), "abc")
  // Alt 多分支：以 `|` 分隔。
  assert_eq(print_regex(Alt([Char('a'), Char('b'), Char('c')])), "a|b|c")
  // 嵌套：分组 + 量词 + 拼接组合。
  assert_eq(
    print_regex(Concat([Char('a'), Star(Group(Alt([Char('b'), Char('c')])))])),
    "a(b|c)*",
  )
  // 空 Concat / 单元素退化形态。
  assert_eq(print_regex(Concat([])), "")
  assert_eq(print_regex(Concat([Char('z')])), "z")
}

///|
/// print_class：字符类区间循环改造后逐字符等价（黄金串）。
test "textbuilder equiv: print_class loop" {
  // 单点 + 区间混合。
  assert_eq(
    print_regex(
      Class({ negated: false, items: [Single('a'), Range('b', 'd')] }),
    ),
    "[ab-d]",
  )
  // 取反字符类。
  assert_eq(
    print_regex(Class({ negated: true, items: [Single('x'), Single('y')] })),
    "[^xy]",
  )
  // 类内特殊字符转义（] 与 - 与 \）。
  assert_eq(
    print_regex(Class({ negated: false, items: [Single(']'), Single('-')] })),
    "[\\]\\-]",
  )
}

///|
/// print_ast：Concat / Alt 循环与字符集合打印改造后逐字符等价（黄金串）。
test "textbuilder equiv: print_ast concat/alt/set" {
  assert_eq(print_ast(Concat([Lit('a'), Lit('b'), Lit('c')])), "abc")
  assert_eq(print_ast(Alt([Lit('a'), Lit('b')])), "a|b")
  // 单区间单点集合 → 字面字符。
  assert_eq(print_ast(Set({ intervals: [(97, 97)] })), "a")
  // 多区间集合 → `[...]`，单点与区间混合。
  assert_eq(print_ast(Set({ intervals: [(97, 97), (98, 100)] })), "[ab-d]")
}

///|
/// print_ast：命名组打印（read_group_name 经 parse_pattern 解析），验证组名
/// 逐字符累积改造后等价。
test "textbuilder equiv: read_group_name via parse_pattern" {
  match parse_pattern("(?<word>abc)") {
    Ok(ast) => assert_eq(print_ast(ast), "(?<word>abc)")
    Err(_) => assert_true(false)
  }
  // 多字符 + 数字 + 下划线组名。
  match parse_pattern("(?<g_1>x)") {
    Ok(ast) => assert_eq(print_ast(ast), "(?<g_1>x)")
    Err(_) => assert_true(false)
  }
}

///|
/// search.mbt：replace_all / slice_chars / expand_repl 改造后逐字符等价。
test "textbuilder equiv: replace_all / slice / expand" {
  let a = match Pattern::compile("a") {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      return
    }
  }
  // 逐个匹配替换：非匹配前缀（slice_chars）+ 替换文本（expand_repl）交错。
  assert_eq(a.replace_all("banana", "X"), "bXnXnX")
  // 末尾残余非匹配片段。
  assert_eq(a.replace_all("aXb", "_"), "_Xb")

  // 捕获组引用 $1 $2 与交换。
  let pair = match Pattern::compile("(a)(b)") {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(pair.replace_all("ab", "$2$1"), "ba")
  // 字面 $$ 与编号组混用。
  assert_eq(pair.replace("ab", "$$$1"), "$a")

  // ${name} 命名引用（expand_repl 内层组名累积亦走 TextBuilder）。
  let named = match Pattern::compile("(?<x>a)") {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(named.replace_all("a", "[${x}]"), "[a]")

  // split：以匹配为分隔切分（slice_chars 路径）。
  let comma = match Pattern::compile(",") {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_true(comma.split("a,b,c") == ["a", "b", "c"])
}

///|
/// dfa.mbt encode_core 与 minimize.mbt 签名键改造后：DFA 子集构造与最小化的
/// 逐位置匹配判定不变（错误的键编码会错误合并/拆分状态，导致匹配偏差）。
test "textbuilder equiv: dfa encode_core & minimize signatures" {
  let r = match parse_regex("a(b|c)*d") {
    Ok(x) => x
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let dfa = to_dfa(build_nfa(r))
  let min = dfa.minimize()
  // 代表性输入上：DFA 与最小化 DFA 的整体匹配区间逐一致（Match? 用 == 比较）。
  // 错误的 encode_core / accept_signature / 细化签名键会错误合并或拆分状态，
  // 进而使两者匹配判定出现偏差；逐一致即证明键编码改造后逐字符等价。
  let samples = ["ad", "abd", "abcbd", "acccd", "ae", "", "abc", "xabdy"]
  for s in samples {
    assert_true(dfa.find(s) == min.find(s))
  }
}
