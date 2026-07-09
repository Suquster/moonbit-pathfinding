// row_poly_gaps_test.mbt —— 行多态合一错误分支覆盖收口（INFRA 第二十批）：
// 变量-变量合一、occurs 检查（类型/行两层）、缺字段拒绝、Show 打印各臂、
// 替换追链与归一化的确定性见证。

///|
test "row_poly 变量合一与 occurs 检查拒绝" {
  // RVar-RVar 别名绑定。
  let s1 = RSubst::empty()
  let f1 = RFresh::new(100)
  assert_true(unify_rty(s1, f1, RVar(1), RVar(2)) is Ok(_))
  assert_true(apply_rty(s1, RVar(1)) == RVar(2))
  assert_true(unify_rty(s1, f1, RVar(3), RVar(3)) is Ok(_))
  // 类型 occurs：t0 = t0 -> Int 无限类型。
  let s2 = RSubst::empty()
  assert_true(
    unify_rty(s2, RFresh::new(100), RVar(0), RFun(RVar(0), RInt)) is Err(_),
  )
  // RFun 参数/返回位递归合一与失败传播。
  let s3 = RSubst::empty()
  assert_true(
    unify_rty(s3, RFresh::new(100), RFun(RInt, RVar(1)), RFun(RInt, RBool))
    is Ok(_),
  )
  assert_true(
    unify_rty(s3, RFresh::new(100), RFun(RBool, RInt), RFun(RInt, RInt))
    is Err(_),
  )
  // 构造子不匹配。
  assert_true(
    unify_rty(RSubst::empty(), RFresh::new(100), RInt, RBool) is Err(_),
  )
}

///|
test "row_poly 行合一：缺字段/行变量/递归行拒绝" {
  // 行变量别名与自反。
  let s1 = RSubst::empty()
  let f1 = RFresh::new(100)
  assert_true(
    unify_rty(s1, f1, RRecord(RowVar(1)), RRecord(RowVar(2))) is Ok(_),
  )
  assert_true(
    unify_rty(s1, f1, RRecord(RowVar(3)), RRecord(RowVar(3))) is Ok(_),
  )
  // 封闭行缺字段。
  let s2 = RSubst::empty()
  assert_true(
    unify_rty(
      s2,
      RFresh::new(100),
      RRecord(RExtend("x", RInt, REmpty)),
      RRecord(REmpty),
    )
    is Err(_),
  )
  assert_true(
    unify_rty(
      RSubst::empty(),
      RFresh::new(100),
      RRecord(REmpty),
      RRecord(RExtend("y", RInt, REmpty)),
    )
    is Err(_),
  )
  // 行 occurs：r0 与含 r0 的行合一 → 无限行。
  let s3 = RSubst::empty()
  assert_true(
    unify_rty(
      s3,
      RFresh::new(100),
      RRecord(RowVar(0)),
      RRecord(RExtend("x", RInt, RowVar(0))),
    )
    is Err(_),
  )
  // 开放行扩展成功：{x:Int | r1} ~ {x:Int, y:Bool}。
  let s4 = RSubst::empty()
  assert_true(
    unify_rty(
      s4,
      RFresh::new(100),
      RRecord(RExtend("x", RInt, RowVar(1))),
      RRecord(RExtend("x", RInt, RExtend("y", RBool, REmpty))),
    )
    is Ok(_),
  )
  // 字段类型冲突传播。
  assert_true(
    unify_rty(
      RSubst::empty(),
      RFresh::new(100),
      RRecord(RExtend("x", RInt, REmpty)),
      RRecord(RExtend("x", RBool, REmpty)),
    )
    is Err(_),
  )
}

///|
test "row_poly 替换追链/归一化与 Show 各臂" {
  // 追链：t1 ↦ t2 ↦ Int。
  let s = RSubst::empty()
  s.tys[1] = RVar(2)
  s.tys[2] = RInt
  assert_true(apply_rty(s, RVar(1)) == RInt)
  assert_true(apply_rty(s, RFun(RVar(1), RVar(9))) == RFun(RInt, RVar(9)))
  // 行替换与嵌套记录。
  s.rows[5] = RExtend("z", RBool, REmpty)
  assert_true(
    apply_rty(s, RRecord(RExtend("a", RVar(1), RowVar(5)))) ==
    RRecord(RExtend("a", RInt, RExtend("z", RBool, REmpty))),
  )
  assert_true(normalize_rty(s, RVar(1)) == RInt)
  assert_true(normalize_row(s, RowVar(5)) == RExtend("z", RBool, REmpty))
  // Show 各构造臂打印。
  let shown = (RFun(RVar(1), RRecord(RExtend("x", RInt, RowVar(2)))) : RTy).to_string()
  assert_true(shown == "RFun(RVar(1), RRecord(RExtend(x: RInt | RowVar(2))))")
  assert_true((RBool : RTy).to_string() == "RBool")
  assert_true((REmpty : Row).to_string() == "REmpty")
}
