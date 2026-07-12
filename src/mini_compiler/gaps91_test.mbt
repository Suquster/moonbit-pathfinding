// gaps91_test.mbt —— 类型推断错误传播余臂（第九十一批）。

///|
fn g91_expr(src : String) -> Expr {
  guard lex_ml(src) is Ok(toks)
  guard parse_ml(toks) is Ok(e)
  e
}

///|
/// ELetRec：递归绑定与自身类型 unify 失败（occurs check）带跨度上报。
test "infer：letrec 自引用 occurs 失败" {
  assert_true(infer(g91_expr("let rec f = fun x -> f in f")) is Err(_))
}

///|
/// ETuple：元组元素推断失败即时短路传播。
test "infer：元组元素类型错误传播" {
  assert_true(infer(g91_expr("(1 true, 2)")) is Err(_))
}
