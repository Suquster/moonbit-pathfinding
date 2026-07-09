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
