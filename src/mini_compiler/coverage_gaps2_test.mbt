// 黑盒测试：mini_compiler 未覆盖分支（JS/WAT 文本后端全算符、优化器
// 元组/遮蔽/除以 -1、ValX/TypeMismatch Show 渲染）。

///|
fn cg2_expr(src : String) -> Expr {
  guard lex_ml(src) is Ok(toks)
  guard parse_ml(toks) is Ok(e)
  e
}

///|
test "JS 文本后端：全部算术/比较/逻辑算符与 if/let/letrec/元组渲染" {
  let src = "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in " +
    "let a = f 4 in (a + 1, a - 1, a / 2, a < 5, a > 5, a >= 5, a == 24, a != 0, true && false, true || false)"
  guard infer(cg2_expr(src)) is Ok((te, _))
  let js = emit_js(te)
  assert_true(js.contains("&&") && js.contains("||"))
  assert_true(js.contains("===") && js.contains("!=="))
  assert_true(js.contains("<=") && js.contains(">="))
  assert_true(js.contains("function f"))
  assert_true(js.contains("?"))
}

///|
test "WAT 文本后端：全部算符/if/lambda 渲染" {
  let src = "let rec g = fun n -> if n >= 2 then g (n - 1) + n / 2 else n in " +
    "(g 5, 1 < 2, 3 > 2, 4 == 4, 5 != 6, 1 <= 2, true && true, false || true)"
  guard infer(cg2_expr(src)) is Ok((te, _))
  let wat = emit_wat(te)
  assert_true(wat.contains("i32.div_s") && wat.contains("i32.add"))
  assert_true(wat.contains("i32.ge_s") && wat.contains("i32.lt_s"))
  assert_true(wat.contains("i32.eq") && wat.contains("i32.ne"))
  assert_true(wat.contains("i32.and") && wat.contains("i32.or"))
  assert_true(wat.contains("(if (result i32)"))
  assert_true(wat.contains("lambda"))
}

///|
test "优化器：元组常量折叠、除以 -1 环绕语义、遮蔽与递归的自由变量分析" {
  // 元组内折叠。
  let t = const_fold(cg2_expr("(1 + 2, 2 * 3)"))
  assert_true(t is ETuple(_, _))
  guard t is ETuple(items, _)
  assert_true(items[0] is EInt(3, _) && items[1] is EInt(6, _))
  // 除以 -1：按 0 - a 环绕定义。
  assert_true(const_fold(cg2_expr("7 / (0 - 1)")) is EInt(-7, _))
  // lambda 参数遮蔽：外层 let 绑定死代码可消除。
  let e1 = dead_let_elim(cg2_expr("let x = 1 in fun x -> x"))
  assert_true(e1 is ELam(_, _, _))
  // letrec 自指与元组体中的自由变量：letrec 绑定名被自身遮蔽。
  let e2 = dead_let_elim(
    cg2_expr("let y = 2 in let rec y = fun n -> y n in (y, y)"),
  )
  assert_true(e2 is ELetRec(_, _, _, _))
}
