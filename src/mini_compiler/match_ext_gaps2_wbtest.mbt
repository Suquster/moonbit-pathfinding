// match_ext_gaps2_wbtest.mbt —— 扩展匹配内部转换器收口
// （INFRA 第二十三批）：expr_span 各构造、ValX/TyX → Expr 转换、环境克隆。

///|
test "expr_span：各构造返回其 Span" {
  let sp : Span = { line: 3, col: 7 }
  assert_true(expr_span(EInt(1, sp)) == sp)
  assert_true(expr_span(ECmp(Lt, EInt(1, sp), EInt(2, sp), sp)) == sp)
  assert_true(expr_span(EBool(true, sp)) == sp)
}

///|
test "expr_span：EVar/ELogic/EArith 构造返回其 Span" {
  let sp : Span = { line: 5, col: 2 }
  assert_true(expr_span(EVar("x", sp)) == sp)
  assert_true(
    expr_span(ELogic(And, EBool(true, sp), EBool(false, sp), sp)) == sp,
  )
  assert_true(expr_span(EArith(Add, EInt(1, sp), EInt(2, sp), sp)) == sp)
}

///|
test "check_base：环境未命中变量回退闭式检查" {
  let sp : Span = { line: 1, col: 1 }
  let tenv : Map[String, TyX] = Map([])
  // EVar 未登记 → check_base_closed 路径（自由变量报错）。
  assert_true(check_base(EVar("free", sp), tenv) is Err(_))
  // 复合表达式内的未登记变量 → subst_var 查询 None 保留原样后报错。
  assert_true(
    check_base(EArith(Add, EVar("free", sp), EInt(1, sp), sp), tenv) is Err(_),
  )
}

///|
test "check_match：PBool 模式匹配布尔 scrutinee" {
  let sp : Span = { line: 1, col: 1 }
  let tenv : Map[String, TyX] = Map([])
  let scrut = XBase(EBool(true, sp))
  let arms : Array[(Pattern, ExprX)] = [
    (PBool(true), XBase(EInt(1, sp))),
    (PBool(false), XBase(EInt(0, sp))),
  ]
  assert_true(check_match(scrut, arms, sp, tenv) == Ok(TXInt))
  // PBool 对非布尔 scrutinee 拒绝。
  let bad = check_match(XBase(EInt(7, sp)), arms, sp, tenv)
  assert_true(bad is Err(_))
}

///|
test "valx_to_expr：元组递归转换与列表拒绝" {
  let sp : Span = { line: 1, col: 1 }
  match valx_to_expr(VXTuple([VXInt(1), VXBool(true)]), sp) {
    Some(ETuple(items, _)) => assert_eq(items.length(), 2)
    _ => assert_true(false)
  }
  // 元组内嵌列表 → 整体不可转换。
  assert_true(valx_to_expr(VXTuple([VXList([])]), sp) is None)
  assert_true(valx_to_expr(VXList([VXInt(1)]), sp) is None)
}

///|
test "tyx_to_expr：占位构造与不可表示类型拒绝" {
  let sp : Span = { line: 1, col: 1 }
  assert_true(tyx_to_expr(TXInt, sp) is Some(EInt(_, _)))
  match tyx_to_expr(TXTuple([TXInt, TXBool]), sp) {
    Some(ETuple(items, _)) => assert_eq(items.length(), 2)
    _ => assert_true(false)
  }
  assert_true(tyx_to_expr(TXFun(TXInt, TXInt), sp) is None)
  assert_true(tyx_to_expr(TXTuple([TXList(TXInt)]), sp) is None)
}

///|
test "clone_valx_env / clone_tyx_env：深拷贝独立" {
  let venv : Map[String, ValX] = Map([])
  venv["x"] = VXInt(42)
  let vc = clone_valx_env(venv)
  assert_eq(vc.length(), 1)
  vc["y"] = VXBool(true)
  assert_eq(venv.length(), 1)
  let tenv : Map[String, TyX] = Map([])
  tenv["x"] = TXBool
  let tc = clone_tyx_env(tenv)
  assert_eq(tc.length(), 1)
  tc["y"] = TXInt
  assert_eq(tenv.length(), 1)
}
