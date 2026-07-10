// arith_gaps_test.mbt —— 算术解析/求值小数与幂运算分支收口
// （INFRA 第三十四批）。

///|
test "parse_and_eval：小数字面量与小数打印" {
  match @parser_combinator.parse_and_eval("1.5 + 0.25") {
    Ok(v) => assert_true(v == 1.75)
    Err(_) => assert_true(false)
  }
}

///|
test "parse_and_eval：负指数与非整数指数幂" {
  // 负整数指数：2^(0-1) = 0.5。
  match @parser_combinator.parse_and_eval("2 ^ (0 - 1)") {
    Ok(v) => assert_true(v == 0.5)
    Err(_) => assert_true(false)
  }
  // 非整数指数：回退为底数本身。
  match @parser_combinator.parse_and_eval("3 ^ 0.5") {
    Ok(v) => assert_true(v == 3.0)
    Err(_) => assert_true(false)
  }
}

///|
test "print_expr：非整数常量以小数形式打印" {
  let p = @parser_combinator.print_expr(@parser_combinator.Num(2.5))
  assert_true(p.contains("2.5"))
}
