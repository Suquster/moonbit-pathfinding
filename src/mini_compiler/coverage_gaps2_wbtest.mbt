// 白盒测试：match_ext ValX/TypeMismatch Show 渲染（需包内构造 ExprX）。

///|
fn wb2_expr(src : String) -> Expr {
  guard lex_ml(src) is Ok(toks)
  guard parse_ml(toks) is Ok(e)
  e
}

///|
test "match_ext：ValX 嵌套 Show 渲染与 TypeMismatch Show" {
  let sp : Span = { line: 1, col: 1 }
  let v = XList(
    [XBase(wb2_expr("(1, true)")), XBase(wb2_expr("(2, false)"))],
    sp,
  )
  let out = eval_x(v)
  let rendered = "\{out}"
  assert_true(rendered.contains("VXList") && rendered.contains("VXTuple"))
  assert_true(
    rendered.contains("VXInt(1)") && rendered.contains("VXBool(true)"),
  )
  // 列表元素类型不一致 → TypeMismatch，其 Show 可渲染。
  let bad = XList([XBase(wb2_expr("1")), XBase(wb2_expr("true"))], sp)
  guard check_x(bad) is Err(tm)
  let s = "\{tm}"
  assert_true(s.contains("TypeMismatch"))
}
