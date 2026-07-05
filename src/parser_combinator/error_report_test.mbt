// error_report_test.mbt —— T4.2 错误报告渲染的行为锁定测试。
//
// 对标 megaparsec `errorBundlePretty` 的输出结构：位置头、源码行摘录、
// caret 对齐、unexpected 实际字符、expecting 期望集合。

///|
test "T4.2: render_error 单行输入——caret 对齐失败列并列出期望" {
  let p = seq(
    ptoken("let "),
    many1(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")),
  )
  let src = "let x"
  let rendered = p.explain_failure(src)
  match rendered {
    Some(msg) =>
      assert_eq(
        msg,
        (
          #|1:5:
          #|  |
          #|1 | let x
          #|  |     ^
          #|unexpected 'x'
          #|expecting 数字
        ),
      )
    None => fail("应当解析失败")
  }
}

///|
test "T4.2: render_error 多行输入——摘录失败所在行且行号对齐" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  let line = seq(many1(digit), pchar('\n'))
  let p = seq(line, seq(line, line))
  let src = "12\n34\nxy\n"
  match p.explain_failure(src) {
    Some(msg) =>
      assert_eq(
        msg,
        (
          #|3:1:
          #|  |
          #|3 | xy
          #|  | ^
          #|unexpected 'x'
          #|expecting 数字
        ),
      )
    None => fail("应当解析失败")
  }
}

///|
test "T4.2: render_error EOF 失败——unexpected 输入末尾" {
  let p = seq(ptoken("ab"), any_char())
  match p.explain_failure("ab") {
    Some(msg) => {
      assert_true(msg.contains("unexpected 输入末尾"))
      assert_true(msg.contains("expecting 任意字符"))
    }
    None => fail("应当解析失败")
  }
}

///|
test "T4.2: render_error 期望集合去重且保持首现顺序" {
  let p = alt([pchar('a'), pchar('b'), pchar('a')])
  match p.explain_failure("z") {
    Some(msg) => assert_true(msg.contains("expecting 'a', 'b'"))
    None => fail("应当解析失败")
  }
}

///|
test "T4.2: render_error 成功解析返回 None" {
  let p = ptoken("ok")
  assert_true(p.explain_failure("ok") is None)
}
