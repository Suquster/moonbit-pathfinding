// 黑盒测试：覆盖率审计收口（INFRA 第七十八批）——
// 空分支择一的退化失败与非推进解析器的循环防护。

///|
test "alt：空分支列表在起点失败且无期望符号" {
  let p : Parser[Int] = alt([])
  match p.parse(Input::from_string("abc")) {
    Fail(pos, expected~) => {
      assert_eq(pos.offset, 0)
      assert_eq(expected.length(), 0)
    }
    Ok(_, _) => fail("空 alt 不应成功")
  }
}

///|
test "many1：不推进游标的成功解析器立即返回避免死循环" {
  let epsilon : Parser[Int] = Parser::new(fn(input) {
    ParseResult::Ok(7, input)
  })
  match many1(epsilon).parse(Input::from_string("xy")) {
    Ok(vs, rest) => {
      assert_true(vs == [7])
      assert_eq(rest.pos.offset, 0)
    }
    Fail(_, ..) => fail("不应失败")
  }
}

///|
test "many1：中途停止推进时保留已收集结果" {
  let mut calls = 0
  let stalling : Parser[Int] = Parser::new(fn(input) {
    calls = calls + 1
    if calls == 1 {
      ParseResult::Ok(1, input.advance())
    } else {
      ParseResult::Ok(2, input)
    }
  })
  match many1(stalling).parse(Input::from_string("xy")) {
    Ok(vs, _) => assert_true(vs == [1, 2])
    Fail(_, ..) => fail("不应失败")
  }
}
