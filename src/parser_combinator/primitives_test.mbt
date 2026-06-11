// primitives_test.mbt —— Parser_Combinator 核心类型与基础原语的单元测试。
//
// 在小型确定性夹具上校验任务 5.1 的实现自洽：`Input` 游标推进与行列计算、
// `pchar` / `satisfy` / `any_char` / `ptoken` 的成功与失败契约（R4.2 成功
// 返回产出值与剩余输入；R4.3 失败返回含位置与期望符号且不消费输入）。
// 解析器契约不变量与往返性质的属性测试由后续任务 5.3 / 5.4 单独承载。
//
// 说明：对 `Option` / `Array` 等复合类型的等值校验采用 `assert_true(x == y)`
// （走 `Eq`），以避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警。

///|
/// Input 从字符串构造后，游标位于起始位置且可逐字符查看。
test "input peek and start position" {
  let input = Input::from_string("ab")
  assert_false(input.is_eof())
  assert_true(input.peek() == Some('a'))
  inspect(input.pos, content="1:1")
  assert_eq(input.pos.offset, 0)
}

///|
/// advance 在普通字符上推进列号，在换行上推进行号并复位列号。
test "input advance tracks line and column" {
  let input = Input::from_string("a\nb")
  let after_a = input.advance()
  inspect(after_a.pos, content="1:2")
  assert_eq(after_a.pos.offset, 1)
  let after_nl = after_a.advance()
  inspect(after_nl.pos, content="2:1")
  assert_eq(after_nl.pos.offset, 2)
  assert_true(after_nl.peek() == Some('b'))
}

///|
/// advance 到达末尾后幂等地停在 EOF。
test "input advance is idempotent at eof" {
  let input = Input::from_string("x")
  let at_eof = input.advance()
  assert_true(at_eof.is_eof())
  assert_true(at_eof.advance().peek() is None)
}

///|
/// pchar 成功：产出匹配字符并把剩余输入推进一位。
test "pchar succeeds and consumes one char" {
  let result = pchar('a').parse_string("abc")
  assert_true(result.is_ok())
  assert_true(result.value() == Some('a'))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('b'))
    None => fail("expected remaining input")
  }
}

///|
/// pchar 失败：字符不匹配时返回失败位置与期望符号，且不消费输入。
test "pchar fails without consuming on mismatch" {
  let result = pchar('x').parse_string("abc")
  assert_false(result.is_ok())
  match result {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      assert_eq(pos.offset, 0)
      assert_true(expected == ["'x'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// pchar 在空输入（EOF）上失败。
test "pchar fails at end of input" {
  let result = pchar('a').parse_string("")
  assert_false(result.is_ok())
}

///|
/// satisfy 按谓词匹配字符。
test "satisfy matches by predicate" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  assert_true(digit.parse_string("7x").is_ok())
  assert_false(digit.parse_string("x7").is_ok())
}

///|
/// any_char 匹配任意非空首字符，在空输入上失败。
test "any_char matches any non-empty head" {
  assert_true(any_char().parse_string("z").value() == Some('z'))
  assert_false(any_char().parse_string("").is_ok())
}

///|
/// ptoken 成功消费整个字面词法单元，并把游标推进到其末尾之后。
test "ptoken consumes a literal token" {
  let result = ptoken("let").parse_string("let x")
  assert_true(result.value() == Some("let"))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some(' '))
    None => fail("expected remaining input")
  }
}

///|
/// ptoken 在前缀不完整匹配时失败，失败位置回到词法单元起点（不消费输入）。
test "ptoken fails at token start on mismatch" {
  let result = ptoken("let").parse_string("led")
  match result {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      assert_eq(pos.offset, 0)
      assert_true(expected == ["\"let\""])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// 空词法单元立即成功且不消费输入。
test "ptoken with empty literal succeeds without consuming" {
  let result = ptoken("").parse_string("abc")
  assert_true(result.value() == Some(""))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('a'))
    None => fail("expected remaining input")
  }
}
