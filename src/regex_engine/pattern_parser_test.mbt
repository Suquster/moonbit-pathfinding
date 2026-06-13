// pattern_parser_test.mbt —— 新解析器 `parse_pattern` 单元测试（任务 3.3）。
//
// 覆盖编号顺序（嵌套 / 非捕获穿插）、命名组登记、惰性后缀、内联标志、各类
// 错误位置见证（R1.1/1.2/1.3/1.7/3.1）。

///|
/// 编号捕获组按左括号源顺序分配 1..n。
test "parse_pattern numbers capturing groups in source order" {
  assert_true(
    parse_pattern("(a)(b)") ==
    Ok(
      Concat([
        Group(body=Lit('a'), index=Some(1), name=None),
        Group(body=Lit('b'), index=Some(2), name=None),
      ]),
    ),
  )
}

///|
/// 嵌套与非捕获穿插：非捕获组不占编号，编号按左括号 DFS 前序。
test "parse_pattern nested numbering skips non-capturing groups" {
  assert_true(
    parse_pattern("(a(?:x)(b))") ==
    Ok(
      Group(
        body=Concat([
          Lit('a'),
          Group(body=Lit('x'), index=None, name=None),
          Group(body=Lit('b'), index=Some(2), name=None),
        ]),
        index=Some(1),
        name=None,
      ),
    ),
  )
}

///|
/// 命名捕获组既分配编号又登记名称（`(?<name>...)` 与 `(?P<name>...)`）。
test "parse_pattern named groups get index and name" {
  assert_true(
    parse_pattern("(?<y>a)") ==
    Ok(Group(body=Lit('a'), index=Some(1), name=Some("y"))),
  )
  assert_true(
    parse_pattern("(?P<z>b)") ==
    Ok(Group(body=Lit('b'), index=Some(1), name=Some("z"))),
  )
}

///|
/// 惰性后缀：量词末尾 `?` 置 `greedy=false`；无后缀为贪婪。
test "parse_pattern lazy quantifier suffix" {
  assert_true(
    parse_pattern("a*?") ==
    Ok(Repeat(node=Lit('a'), min=0, max=None, greedy=false)),
  )
  assert_true(
    parse_pattern("a+") ==
    Ok(Repeat(node=Lit('a'), min=1, max=None, greedy=true)),
  )
  assert_true(
    parse_pattern("a{2,3}?") ==
    Ok(Repeat(node=Lit('a'), min=2, max=Some(3), greedy=false)),
  )
}

///|
/// 预定义类与点号 lowering 为 `CharSet`（非 dotall 下点号不含 `\n`）。
test "parse_pattern lowers predefined classes and dot" {
  // \d → [0-9]
  assert_true(
    parse_pattern("\\d") ==
    Ok(Set({ intervals: [('0'.to_int(), '9'.to_int())] })),
  )
  // 非 dotall：'.' 不含 '\n'（码点 10）。
  assert_true(parse_pattern(".") == Ok(Set({ intervals: [(0, 9), (11, 0x10FFFF)] })))
}

///|
/// 内联标志 `(?i)`：后续字面按大小写折叠 lowering 为 `Set`。
test "parse_pattern inline case-insensitive flag" {
  // (?i)a → Set({A,a})
  assert_true(
    parse_pattern("(?i)a") ==
    Ok(Set({ intervals: [('A'.to_int(), 'A'.to_int()), ('a'.to_int(), 'a'.to_int())] })),
  )
}

///|
/// 锚点按多行 / 非多行选择断言类型。
test "parse_pattern anchors depend on multiline flag" {
  assert_true(parse_pattern("^") == Ok(Assert(TextStart)))
  assert_true(parse_pattern("^", flags=Flags::parse("m")) == Ok(Assert(LineStart)))
  assert_true(parse_pattern("$", flags=Flags::parse("m")) == Ok(Assert(LineEnd)))
}

///|
/// 词边界与文本锚转义解析为断言。
test "parse_pattern word boundary and text anchors" {
  assert_true(parse_pattern("\\b") == Ok(Assert(WordBoundary)))
  assert_true(parse_pattern("\\B") == Ok(Assert(NotWordBoundary)))
}

///|
/// 前瞻解析为 `Look`。
test "parse_pattern lookahead" {
  assert_true(
    parse_pattern("(?=a)") == Ok(Look(positive=true, body=Lit('a'))),
  )
  assert_true(
    parse_pattern("(?!a)") == Ok(Look(positive=false, body=Lit('a'))),
  )
}

///|
/// 重复组名 → 携带第二个左括号位置的 `Unexpected`，不构造任何程序。
test "parse_pattern duplicate group name errors with position" {
  match parse_pattern("(?<x>a)(?<x>b)") {
    Err(Unexpected(pos~, ..)) => assert_eq(pos, 7)
    _ => fail("expected Unexpected for duplicate group name")
  }
}

///|
/// 反向引用不支持 → `Unexpected`（携带反斜杠位置）。
test "parse_pattern backreference is unsupported" {
  match parse_pattern("(a)\\1") {
    Err(Unexpected(pos~, ..)) => assert_eq(pos, 3)
    _ => fail("expected Unexpected for backreference")
  }
}

///|
/// 后瞻不支持 → `Unexpected`。
test "parse_pattern lookbehind is unsupported" {
  match parse_pattern("(?<=a)") {
    Err(Unexpected(_)) => assert_true(true)
    _ => fail("expected Unexpected for lookbehind")
  }
}

///|
/// 各类结构错误的位置见证（与既有 ParseError 映射一致，枚举不扩容）。
test "parse_pattern structural errors map to existing ParseError" {
  match parse_pattern("(a") {
    Err(Unbalanced(pos~, what~)) => {
      assert_eq(what, "(")
      assert_eq(pos, 2)
    }
    _ => fail("expected Unbalanced")
  }
  match parse_pattern("[a") {
    Err(Unbalanced(pos~, what~)) => {
      assert_eq(what, "[")
      assert_eq(pos, 0)
    }
    _ => fail("expected Unbalanced")
  }
  match parse_pattern("*") {
    Err(DanglingQuantifier(pos~)) => assert_eq(pos, 0)
    _ => fail("expected DanglingQuantifier")
  }
  match parse_pattern("a)") {
    Err(TrailingInput(pos~)) => assert_eq(pos, 1)
    _ => fail("expected TrailingInput")
  }
  match parse_pattern("a{}") {
    Err(InvalidRepeat(pos~)) => assert_eq(pos, 1)
    _ => fail("expected InvalidRepeat")
  }
}
