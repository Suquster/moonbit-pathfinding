// regex_engine_test.mbt —— Regex_Engine 任务 6.1 的单元测试。
//
// 在小型确定性夹具上校验解析（R2.2）成功形态、非法表达式的含位置错误
// （R2.3），以及 `print_regex` 的基本形态与"打印再解析"互逆自洽（为任务
// 6.3「Property 4：Regex 语法树往返」奠基）。
//
// 说明：对 `Regex` / `Result` 等复合类型的等值校验采用 `assert_true(x == y)`
// （走派生的 `Eq`），以避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警。

// ---------------------------------------------------------------------------
// 解析成功（R2.2）
// ---------------------------------------------------------------------------

///|
/// 单个字面字符解析为 `Char`。
test "parse single char" {
  assert_true(parse_regex("a") == Ok(Char('a')))
}

///|
/// 多字符串接解析为 `Concat`。
test "parse concatenation" {
  assert_true(parse_regex("ab") == Ok(Concat([Char('a'), Char('b')])))
}

///|
/// 择一解析为 `Alt`，且优先级低于串接（`ab|cd` → 两个串接分支）。
test "parse alternation binds looser than concat" {
  assert_true(
    parse_regex("ab|cd") ==
    Ok(Alt([Concat([Char('a'), Char('b')]), Concat([Char('c'), Char('d')])])),
  )
}

///|
/// 量词 `*` `+` `?` 作用于前一原子。
test "parse star plus opt quantifiers" {
  assert_true(parse_regex("a*") == Ok(Star(Char('a'))))
  assert_true(parse_regex("a+") == Ok(Plus(Char('a'))))
  assert_true(parse_regex("a?") == Ok(Opt(Char('a'))))
}

///|
/// 分组 `( ... )` 解析为 `Group`，量词可作用于整个分组。
test "parse group with quantifier" {
  assert_true(
    parse_regex("(ab)*") == Ok(Star(Group(Concat([Char('a'), Char('b')])))),
  )
}

///|
/// 字符类范围与否定。
test "parse char class range and negation" {
  assert_true(
    parse_regex("[a-z]") ==
    Ok(Class({ negated: false, items: [Range('a', 'z')] })),
  )
  assert_true(
    parse_regex("[^0-9]") ==
    Ok(Class({ negated: true, items: [Range('0', '9')] })),
  )
}

///|
/// 字符类内紧跟 `]` 的 `-` 作为字面字符；混合单字符与范围。
test "parse char class with literal dash and mixed items" {
  assert_true(
    parse_regex("[a-]") ==
    Ok(Class({ negated: false, items: [Single('a'), Single('-')] })),
  )
  assert_true(
    parse_regex("[ab-d]") ==
    Ok(Class({ negated: false, items: [Single('a'), Range('b', 'd')] })),
  )
}

///|
/// 计数量词 `{m}` / `{m,}` / `{m,n}`。
test "parse counted repeat" {
  assert_true(parse_regex("a{2}") == Ok(Repeat(Char('a'), 2, Some(2))))
  assert_true(parse_regex("a{2,}") == Ok(Repeat(Char('a'), 2, None)))
  assert_true(parse_regex("a{2,5}") == Ok(Repeat(Char('a'), 2, Some(5))))
}

///|
/// 锚点 `^` 与 `$` 解析为 `Anchor` 节点。
test "parse anchors" {
  assert_true(
    parse_regex("^a$") == Ok(Concat([Anchor(Start), Char('a'), Anchor(End)])),
  )
}

///|
/// 反斜杠转义使元字符成为字面字符。
test "parse escaped metacharacter" {
  assert_true(
    parse_regex("a\\+b") == Ok(Concat([Char('a'), Char('+'), Char('b')])),
  )
}

// ---------------------------------------------------------------------------
// 非法表达式：含位置的解析错误，不构造自动机（R2.3）
// ---------------------------------------------------------------------------

///|
/// 未闭合分组 → `Unbalanced("(")`，位置指向缺失 `)` 处。
test "illegal unbalanced group" {
  match parse_regex("(a") {
    Err(Unbalanced(pos~, what~)) => {
      @test.assert_eq(what, "(")
      @test.assert_eq(pos, 2)
    }
    _ => fail("expected Unbalanced error")
  }
}

///|
/// 未闭合字符类 → `Unbalanced("[")`，位置指向起始 `[`。
test "illegal unbalanced class" {
  match parse_regex("[a") {
    Err(Unbalanced(pos~, what~)) => {
      @test.assert_eq(what, "[")
      @test.assert_eq(pos, 0)
    }
    _ => fail("expected Unbalanced error")
  }
}

///|
/// 量词无作用对象 → `DanglingQuantifier`，位置指向该量词。
test "illegal dangling quantifier" {
  match parse_regex("*") {
    Err(DanglingQuantifier(pos~)) => @test.assert_eq(pos, 0)
    _ => fail("expected DanglingQuantifier error")
  }
}

///|
/// 残余未消费输入（多余的 `)`）→ `TrailingInput`。
test "illegal trailing input" {
  match parse_regex("a)") {
    Err(TrailingInput(pos~)) => @test.assert_eq(pos, 1)
    _ => fail("expected TrailingInput error")
  }
}

///|
/// 计数量词缺少数字 → `InvalidRepeat`。
test "illegal counted repeat" {
  match parse_regex("a{}") {
    Err(InvalidRepeat(pos~)) => @test.assert_eq(pos, 1)
    _ => fail("expected InvalidRepeat error")
  }
}

///|
/// 输入末尾的悬空反斜杠 → `Unexpected`。
test "illegal dangling escape" {
  match parse_regex("\\") {
    Err(Unexpected(pos~, ..)) => @test.assert_eq(pos, 1)
    _ => fail("expected Unexpected error")
  }
}

///|
/// `ParseError::pos` 一致地提取各变体的偏移位置。
test "parse error pos accessor" {
  match parse_regex("(a") {
    Err(e) => @test.assert_eq(e.pos(), 2)
    Ok(_) => fail("expected error")
  }
}

// ---------------------------------------------------------------------------
// 打印器基本形态（print_regex）
// ---------------------------------------------------------------------------

///|
/// 各节点形态的基本打印。
test "print basic shapes" {
  inspect(print_regex(Char('a')), content="a")
  inspect(print_regex(Star(Char('a'))), content="a*")
  inspect(print_regex(Plus(Char('a'))), content="a+")
  inspect(print_regex(Opt(Char('a'))), content="a?")
  inspect(print_regex(Concat([Char('a'), Char('b')])), content="ab")
  inspect(print_regex(Alt([Char('a'), Char('b')])), content="a|b")
  inspect(print_regex(Anchor(Start)), content="^")
  inspect(print_regex(Anchor(End)), content="$")
  inspect(print_regex(Group(Char('a'))), content="(a)")
}

///|
/// 计数量词后缀打印形态。
test "print repeat suffix" {
  inspect(print_regex(Repeat(Char('a'), 2, Some(2))), content="a{2}")
  inspect(print_regex(Repeat(Char('a'), 2, None)), content="a{2,}")
  inspect(print_regex(Repeat(Char('a'), 2, Some(5))), content="a{2,5}")
}

///|
/// 字符类与元字符转义打印。
test "print class and escapes" {
  inspect(
    print_regex(Class({ negated: false, items: [Range('a', 'z')] })),
    content="[a-z]",
  )
  inspect(
    print_regex(Class({ negated: true, items: [Range('0', '9')] })),
    content="[^0-9]",
  )
  // 字面元字符在打印时被转义。
  inspect(print_regex(Char('+')), content="\\+")
  inspect(print_regex(Char('(')), content="\\(")
}

///|
/// 量词作用于非原子时以分组包裹，保证重新解析时绑定范围正确。
test "print wraps non-atomic operand in group" {
  inspect(print_regex(Star(Concat([Char('a'), Char('b')]))), content="(ab)*")
}

// ---------------------------------------------------------------------------
// 打印再解析互逆自洽（Property 4 的基础校验）
// ---------------------------------------------------------------------------

///|
/// 对若干手工语法树，`parse_regex(print_regex(r))` 应得到等价语法树。
test "round-trip parse of print" {
  let samples : Array[Regex] = [
    Char('a'),
    Star(Char('a')),
    Plus(Char('b')),
    Opt(Char('c')),
    Concat([Char('a'), Char('b'), Char('c')]),
    Alt([Char('a'), Concat([Char('b'), Char('c')])]),
    Group(Concat([Char('a'), Char('b')])),
    Repeat(Char('a'), 2, Some(5)),
    Repeat(Char('a'), 3, None),
    Class({ negated: false, items: [Range('a', 'z'), Single('_')] }),
    Class({ negated: true, items: [Range('0', '9')] }),
    Concat([Anchor(Start), Char('x'), Anchor(End)]),
    Char('+'),
    Star(Group(Concat([Char('a'), Char('b')]))),
  ]
  for r in samples {
    assert_true(parse_regex(print_regex(r)) == Ok(r))
  }
}
