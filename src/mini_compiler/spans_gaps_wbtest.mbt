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

///|
test "parse_ml：应用参数原子解析失败即报错（INFRA 第六十八批）" {
  guard lex_ml("f (") is Ok(tokens)
  assert_true(parse_ml(tokens) is Err(_))
}

///|
test "expr_span：ELam 提取（INFRA 第七十三批）" {
  let sp = Span::{ line: 4, col: 2 }
  let z = Span::{ line: 0, col: 0 }
  assert_true(expr_span(ELam("x", EInt(1, z), sp)) == sp)
}

///|
test "row_poly 辅助：RFun 归一化与出现检查余臂（INFRA 第七十三批）" {
  let s = RSubst::empty()
  assert_true(normalize_rty(s, RFun(RInt, RBool)) == RFun(RInt, RBool))
  assert_false(r_occurs_ty_row(0, REmpty))
  assert_false(r_occurs_ty_row(0, RowVar(1)))
  assert_true(r_occurs_ty_row(0, RExtend("a", RVar(0), REmpty)))
  assert_false(r_occurs_row_ty(0, RFun(RInt, RBool)))
  assert_true(r_occurs_row_ty(0, RRecord(RowVar(0))))
}

///|
test "try_run_demo/run_demo：词法/语法/类型错误传播与降级（INFRA 第七十三批）" {
  assert_true(try_run_demo("let x = \u0001") is Err(_))
  assert_true(try_run_demo("f (") is Err(_))
  assert_true(try_run_demo("x") is Err(_))
  let trace = run_demo("x")
  assert_true(trace.optimized_form.length() > 0)
}
