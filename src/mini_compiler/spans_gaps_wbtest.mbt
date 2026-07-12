// 白盒测试：覆盖率审计收口（INFRA 第六十六批）——
// span 提取余臂、空输入语法诊断兜底、行多态归一化与行重排错误传播。

///|
test "expr_span/ml_expr_span：EIf/ETuple 等余臂提取" {
  let sp = Span::{ line: 3, col: 7 }
  let z = Span::{ line: 0, col: 0 }
  let cond = EBool(true, z)
  let e_if = EIf(cond, EInt(1, z), EInt(2, z), sp)
  assert_true(expr_span(e_if) == sp)
  assert_true(ml_expr_span(e_if) == sp)
  assert_true(ml_expr_span(ETuple([EInt(1, z), EInt(2, z)], sp)) == sp)
}

///|
test "ml_token_span：TkBool/TkLParen 余臂" {
  let sp = Span::{ line: 2, col: 5 }
  assert_true(ml_token_span(TkBool(true, sp)) == sp)
  assert_true(ml_token_span(TkLParen(sp)) == sp)
}

///|
test "ml_syntax_err：空 token 流退化为 (0,0)" {
  let d = ml_syntax_err([], 0, "empty")
  assert_eq(d.line, 0)
  assert_eq(d.col, 0)
}

///|
test "normalize_rty：RVar 保持自身" {
  let s = RSubst::empty()
  assert_true(normalize_rty(s, RVar(3)) == RVar(3))
}

///|
test "rewrite_row：深层缺失标签的错误经外层字段传播" {
  let s = RSubst::empty()
  let fresh = RFresh::new(0)
  let row = RExtend("a", RInt, REmpty)
  assert_true(rewrite_row(s, fresh, row, "b") is Err(_))
}
