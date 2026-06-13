// ast_test.mbt —— 富语法树 `Ast` 单元测试（任务 2.3）。
//
// 覆盖 `Ast::of_regex` 对既有节点的语义映射见证，以及 `print_ast` 对命名 /
// 非捕获 / 惰性 / 断言的可读输出（R1.2/3.1/5.1/12.6）。

///|
/// `Ast::of_regex` 把既有节点语义保真地提升为富语法树。
test "Ast::of_regex maps existing Regex nodes" {
  assert_true(Ast::of_regex(Char('a')) == Lit('a'))
  assert_true(
    Ast::of_regex(Star(Char('a'))) ==
    Repeat(node=Lit('a'), min=0, max=None, greedy=true),
  )
  assert_true(
    Ast::of_regex(Plus(Char('a'))) ==
    Repeat(node=Lit('a'), min=1, max=None, greedy=true),
  )
  assert_true(
    Ast::of_regex(Opt(Char('a'))) ==
    Repeat(node=Lit('a'), min=0, max=Some(1), greedy=true),
  )
  assert_true(
    Ast::of_regex(Repeat(Char('a'), 2, Some(5))) ==
    Repeat(node=Lit('a'), min=2, max=Some(5), greedy=true),
  )
  assert_true(Ast::of_regex(Anchor(Start)) == Assert(TextStart))
  assert_true(Ast::of_regex(Anchor(End)) == Assert(TextEnd))
  // 既有 Group 提升为非捕获组（index=None）。
  assert_true(
    Ast::of_regex(Group(Char('a'))) ==
    Group(body=Lit('a'), index=None, name=None),
  )
}

///|
/// `Ast::of_regex` 对串接 / 择一递归映射。
test "Ast::of_regex maps concat and alt recursively" {
  assert_true(
    Ast::of_regex(Concat([Char('a'), Char('b')])) ==
    (Concat([Lit('a'), Lit('b')]) : Ast),
  )
  assert_true(
    Ast::of_regex(Alt([Char('a'), Char('b')])) ==
    (Alt([Lit('a'), Lit('b')]) : Ast),
  )
}

///|
/// `print_ast` 对分组（捕获 / 非捕获 / 命名）的可读输出。
test "print_ast renders group variants" {
  inspect(
    print_ast(Group(body=Lit('a'), index=None, name=None)),
    content="(?:a)",
  )
  inspect(
    print_ast(Group(body=Lit('a'), index=Some(1), name=None)),
    content="(a)",
  )
  inspect(
    print_ast(Group(body=Lit('a'), index=Some(1), name=Some("year"))),
    content="(?<year>a)",
  )
}

///|
/// `print_ast` 对惰性 / 贪婪量词的可读输出。
test "print_ast renders lazy and greedy quantifiers" {
  inspect(
    print_ast(Repeat(node=Lit('a'), min=0, max=None, greedy=false)),
    content="a*?",
  )
  inspect(
    print_ast(Repeat(node=Lit('a'), min=0, max=None, greedy=true)),
    content="a*",
  )
  inspect(
    print_ast(Repeat(node=Lit('a'), min=1, max=None, greedy=false)),
    content="a+?",
  )
  inspect(
    print_ast(Repeat(node=Lit('a'), min=2, max=Some(5), greedy=true)),
    content="a{2,5}",
  )
}

///|
/// `print_ast` 对零宽断言与前瞻的可读输出。
test "print_ast renders asserts and lookarounds" {
  inspect(print_ast(Assert(WordBoundary)), content="\\b")
  inspect(print_ast(Assert(NotWordBoundary)), content="\\B")
  inspect(print_ast(Assert(TextStart)), content="\\A")
  inspect(print_ast(Assert(LineStart)), content="^")
  inspect(print_ast(Assert(LineEnd)), content="$")
  inspect(print_ast(Look(positive=true, body=Lit('a'))), content="(?=a)")
  inspect(print_ast(Look(positive=false, body=Lit('a'))), content="(?!a)")
}
