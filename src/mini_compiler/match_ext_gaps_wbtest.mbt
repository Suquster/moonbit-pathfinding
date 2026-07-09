// match_ext_gaps_wbtest.mbt —— 扩展层（match / 元组 / 列表）桥接与拒绝分支
// 覆盖收口（INFRA 第十六批）：check_x / eval_x 的各错误传播路径、变量代入的
// 遮蔽语义、值 / 类型投影的边界回退。

///|
test "check_x error propagation through list / match" {
  let sp = Span::{ line: 0, col: 0 }
  let bad = XBase(
    EArith(Add, EInt(1, sp), EBool(true, sp), sp), // 基础层类型错误
  )
  // 列表首元素 / 后续元素错误传播。
  assert_true(check_x(XList([bad], sp)) is Err(_))
  assert_true(check_x(XList([XBase(EInt(1, sp)), bad], sp)) is Err(_))
  // 列表元素类型不一致。
  assert_true(
    check_x(XList([XBase(EInt(1, sp)), XBase(EBool(true, sp))], sp)) is Err(_),
  )
  // match：scrutinee 错误 / 零 arm / 模式不兼容 / body 错误 / body 类型不一致。
  assert_true(check_x(XMatch(bad, [(PWild, XBase(EInt(0, sp)))], sp)) is Err(_))
  assert_true(check_x(XMatch(XBase(EInt(1, sp)), [], sp)) is Err(_))
  assert_true(
    check_x(XMatch(XBase(EInt(1, sp)), [(PBool(true), XBase(EInt(0, sp)))], sp))
    is Err(_),
  )
  assert_true(check_x(XMatch(XBase(EInt(1, sp)), [(PWild, bad)], sp)) is Err(_))
  assert_true(
    check_x(
      XMatch(
        XBase(EInt(1, sp)),
        [(PInt(0), XBase(EInt(0, sp))), (PWild, XBase(EBool(true, sp)))],
        sp,
      ),
    )
    is Err(_),
  )
}

///|
test "check_pattern rejection shapes" {
  let sp = Span::{ line: 0, col: 0 }
  // 元组模式元数不符 / 分量错误传播 / scrutinee 非元组。
  let scrut_pair = XBase(ETuple([EInt(1, sp), EInt(2, sp)], sp))
  assert_true(
    check_x(XMatch(scrut_pair, [(PTuple([PWild]), XBase(EInt(0, sp)))], sp))
    is Err(_),
  )
  assert_true(
    check_x(
      XMatch(
        scrut_pair,
        [(PTuple([PBool(true), PWild]), XBase(EInt(0, sp)))],
        sp,
      ),
    )
    is Err(_),
  )
  assert_true(
    check_x(
      XMatch(XBase(EInt(1, sp)), [(PTuple([PWild]), XBase(EInt(0, sp)))], sp),
    )
    is Err(_),
  )
  // PNil / PCons 对非列表 scrutinee。
  assert_true(
    check_x(XMatch(XBase(EInt(1, sp)), [(PNil, XBase(EInt(0, sp)))], sp))
    is Err(_),
  )
  assert_true(
    check_x(
      XMatch(
        XBase(EInt(1, sp)),
        [(PCons(PWild, PWild), XBase(EInt(0, sp)))],
        sp,
      ),
    )
    is Err(_),
  )
  // PCons 头 / 尾子模式错误传播。
  let list_scrut = XList([XBase(EInt(1, sp))], sp)
  assert_true(
    check_x(
      XMatch(list_scrut, [(PCons(PBool(true), PWild), XBase(EInt(0, sp)))], sp),
    )
    is Err(_),
  )
  assert_true(
    check_x(
      XMatch(list_scrut, [(PCons(PWild, PTuple([])), XBase(EInt(0, sp)))], sp),
    )
    is Err(_),
  )
  // PInt 对非整数 scrutinee。
  assert_true(
    check_x(XMatch(XBase(EBool(true, sp)), [(PInt(1), XBase(EInt(0, sp)))], sp))
    is Err(_),
  )
}

///|
test "eval_x pattern rejection and fallthrough" {
  let sp = Span::{ line: 0, col: 0 }
  // 各模式失配后落到后续 arm。
  let m = XMatch(
    XBase(EInt(7, sp)),
    [(PInt(1), XBase(EInt(10, sp))), (PVar("x"), XBase(EVar("x", sp)))],
    sp,
  )
  assert_true(eval_x(m) == VXInt(7))
  // PBool 失配 / 非布尔值。
  let mb = XMatch(
    XBase(EBool(false, sp)),
    [(PBool(true), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mb) == VXInt(2))
  let mbi = XMatch(
    XBase(EInt(3, sp)),
    [(PBool(true), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mbi) == VXInt(2))
  // PInt 对非整数值。
  let mib = XMatch(
    XBase(EBool(true, sp)),
    [(PInt(1), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mib) == VXInt(2))
  // PTuple：元数不符 / 非元组值 / 分量失配。
  let pair = XBase(ETuple([EInt(1, sp), EInt(2, sp)], sp))
  let mt = XMatch(
    pair,
    [(PTuple([PWild]), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mt) == VXInt(2))
  let mtv = XMatch(
    XBase(EInt(1, sp)),
    [(PTuple([PWild]), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mtv) == VXInt(2))
  let mtc = XMatch(
    pair,
    [
      (PTuple([PInt(9), PWild]), XBase(EInt(1, sp))),
      (PWild, XBase(EInt(2, sp))),
    ],
    sp,
  )
  assert_true(eval_x(mtc) == VXInt(2))
  // PNil：非空列表 / 非列表值；PCons：空列表 / 非列表 / 头失配 / 尾失配。
  let one = XList([XBase(EInt(1, sp))], sp)
  let nil = XList([], sp)
  let mn = XMatch(
    one,
    [(PNil, XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mn) == VXInt(2))
  let mnv = XMatch(
    XBase(EInt(1, sp)),
    [(PNil, XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mnv) == VXInt(2))
  let mc = XMatch(
    nil,
    [(PCons(PWild, PWild), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mc) == VXInt(2))
  let mcv = XMatch(
    XBase(EInt(1, sp)),
    [(PCons(PWild, PWild), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mcv) == VXInt(2))
  let mch = XMatch(
    one,
    [(PCons(PInt(9), PWild), XBase(EInt(1, sp))), (PWild, XBase(EInt(2, sp)))],
    sp,
  )
  assert_true(eval_x(mch) == VXInt(2))
  let mct = XMatch(
    one,
    [
      (PCons(PWild, PCons(PWild, PWild)), XBase(EInt(1, sp))),
      (PWild, XBase(EInt(2, sp))),
    ],
    sp,
  )
  assert_true(eval_x(mct) == VXInt(2))
  // 无 arm 命中 → 占位回退。
  let m0 = XMatch(XBase(EInt(1, sp)), [(PInt(2), XBase(EInt(9, sp)))], sp)
  assert_true(eval_x(m0) == VXInt(0))
}

///|
test "subst_var shadowing across binders" {
  let sp = Span::{ line: 0, col: 0 }
  // let / lambda / let rec 遮蔽：绑定名不被代入，外层名被代入。
  let body = XBase(
    ELet("x", EInt(1, sp), EArith(Add, EVar("x", sp), EVar("y", sp), sp), sp),
  )
  let m = XMatch(XBase(EInt(10, sp)), [(PVar("y"), body)], sp)
  assert_true(eval_x(m) == VXInt(11))
  let lam = XBase(
    EApp(
      ELam("x", EArith(Add, EVar("x", sp), EVar("y", sp), sp), sp),
      EInt(2, sp),
      sp,
    ),
  )
  let ml = XMatch(XBase(EInt(30, sp)), [(PVar("y"), lam)], sp)
  assert_true(eval_x(ml) == VXInt(32))
  let rec_expr = XBase(
    ELetRec(
      "f",
      ELam(
        "n",
        EIf(
          ECmp(Lt, EVar("n", sp), EInt(1, sp), sp),
          EVar("y", sp),
          EApp(EVar("f", sp), EArith(Sub, EVar("n", sp), EInt(1, sp), sp), sp),
          sp,
        ),
        sp,
      ),
      EApp(EVar("f", sp), EInt(3, sp), sp),
      sp,
    ),
  )
  let mr = XMatch(XBase(EInt(5, sp)), [(PVar("y"), rec_expr)], sp)
  assert_true(eval_x(mr) == VXInt(5))
  // 比较 / 逻辑 / if / 元组内的代入。
  let cmp = XBase(ECmp(Lt, EVar("y", sp), EInt(9, sp), sp))
  assert_true(
    eval_x(XMatch(XBase(EInt(1, sp)), [(PVar("y"), cmp)], sp)) == VXBool(true),
  )
  let lg = XBase(ELogic(And, EVar("b", sp), EBool(true, sp), sp))
  assert_true(
    eval_x(XMatch(XBase(EBool(true, sp)), [(PVar("b"), lg)], sp)) ==
    VXBool(true),
  )
  let ife = XBase(EIf(EVar("b", sp), EInt(1, sp), EInt(2, sp), sp))
  assert_true(
    eval_x(XMatch(XBase(EBool(false, sp)), [(PVar("b"), ife)], sp)) == VXInt(2),
  )
  let tup = XBase(ETuple([EVar("y", sp), EInt(2, sp)], sp))
  assert_true(
    eval_x(XMatch(XBase(EInt(1, sp)), [(PVar("y"), tup)], sp)) ==
    VXTuple([VXInt(1), VXInt(2)]),
  )
}

///|
test "projection boundaries: lists, functions, closures" {
  let sp = Span::{ line: 0, col: 0 }
  // 列表绑定顶层引用可用；对列表做复合算术 → check 报错。
  let lref = XMatch(
    XList([XBase(EInt(1, sp))], sp),
    [(PVar("xs"), XBase(EVar("xs", sp)))],
    sp,
  )
  assert_true(eval_x(lref) == VXList([VXInt(1)]))
  assert_true(check_x(lref) == Ok(TXList(TXInt)))
  let lbad = XMatch(
    XList([XBase(EInt(1, sp))], sp),
    [(PVar("xs"), XBase(EArith(Add, EVar("xs", sp), EInt(1, sp), sp)))],
    sp,
  )
  assert_true(check_x(lbad) is Err(_))
  // 函数型 XBase 可类型检查（TXFun 桥接），闭包值投影回退占位整数。
  let lam = XBase(ELam("x", EVar("x", sp), sp))
  match check_x(lam) {
    Ok(TXFun(_, _)) => assert_true(true)
    _ => assert_true(false)
  }
  assert_true(eval_x(lam) == VXInt(0))
  // 元组内含元组的类型投影（tyx_to_expr 递归）与列表类型投影失败回退。
  let nested = XMatch(
    XBase(ETuple([EInt(1, sp), ETuple([EInt(2, sp)], sp)], sp)),
    [(PVar("t"), XBase(EArith(Add, EInt(0, sp), EInt(1, sp), sp)))],
    sp,
  )
  assert_true(eval_x(nested) == VXInt(1))
}
