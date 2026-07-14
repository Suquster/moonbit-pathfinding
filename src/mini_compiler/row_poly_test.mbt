// row_poly_test.mbt —— T1.3 行多态记录合一：定向用例 + 属性测试。

///|
test "T1.3 row: open records absorb missing fields via row variables" {
  // {x: Int | ρ1} ~ {y: Bool | ρ2}：ρ1 吸收 y、ρ2 吸收 x。
  let s = RSubst::empty()
  let fresh = RFresh::new(100)
  let a = RTy::RRecord(Row::RExtend("x", RTy::RInt, Row::RowVar(0)))
  let b = RTy::RRecord(Row::RExtend("y", RTy::RBool, Row::RowVar(1)))
  assert_true(unify_rty(s, fresh, a, b) is Ok(_))
  // 合一后二者规范化相等。
  assert_true(normalize_rty(s, a) == normalize_rty(s, b))
}

///|
test "T1.3 row: field order is irrelevant, closed rows need exact labels" {
  // 封闭记录 {x: Int, y: Bool} ~ {y: Bool, x: Int}：顺序无关，可合一。
  let s = RSubst::empty()
  let fresh = RFresh::new(100)
  let a = RTy::RRecord(
    Row::RExtend("x", RTy::RInt, Row::RExtend("y", RTy::RBool, Row::REmpty)),
  )
  let b = RTy::RRecord(
    Row::RExtend("y", RTy::RBool, Row::RExtend("x", RTy::RInt, Row::REmpty)),
  )
  assert_true(unify_rty(s, fresh, a, b) is Ok(_))
  // 封闭记录缺字段 ⇒ 确定性报错。
  let s2 = RSubst::empty()
  let c = RTy::RRecord(Row::RExtend("x", RTy::RInt, Row::REmpty))
  match unify_rty(s2, RFresh::new(100), a, c) {
    Err(msg) => assert_true(msg.contains("lacks field 'y'"))
    Ok(_) => assert_true(false)
  }
}

///|
test "T1.3 row: field type conflict and occurs check are rejected" {
  // 同标签不同类型 ⇒ 失败。
  let s = RSubst::empty()
  let a = RTy::RRecord(Row::RExtend("x", RTy::RInt, Row::REmpty))
  let b = RTy::RRecord(Row::RExtend("x", RTy::RBool, Row::REmpty))
  assert_true(unify_rty(s, RFresh::new(100), a, b) is Err(_))
  // 类型变量 occurs：t0 ~ {x: t0} ⇒ 无限类型。
  let s2 = RSubst::empty()
  match
    unify_rty(
      s2,
      RFresh::new(100),
      RTy::RVar(0),
      RTy::RRecord(Row::RExtend("x", RTy::RVar(0), Row::REmpty)),
    ) {
    Err(msg) => assert_true(msg.contains("occurs check"))
    Ok(_) => assert_true(false)
  }
}

///|
test "T1.3 row: row-polymorphic function typing (field access)" {
  // 字段选择子 sel_x : {x: α | ρ} → α 施用于 {x: Int, y: Bool}：α ↦ Int。
  let s = RSubst::empty()
  let fresh = RFresh::new(100)
  let alpha = RTy::RVar(0)
  let selector_arg = RTy::RRecord(Row::RExtend("x", alpha, Row::RowVar(1)))
  let record = RTy::RRecord(
    Row::RExtend("x", RTy::RInt, Row::RExtend("y", RTy::RBool, Row::REmpty)),
  )
  assert_true(unify_rty(s, fresh, selector_arg, record) is Ok(_))
  assert_true(apply_rty(s, alpha) == RTy::RInt)
  // ρ 吸收了余下字段 y。
  assert_true(
    apply_row(s, Row::RowVar(1)) == Row::RExtend("y", RTy::RBool, Row::REmpty),
  )
}

///|
/// T1.3 属性：合一正确性——随机字段集组成的开放/封闭记录对，合一成功后对两侧
/// 施加所得替换**规范化相等**；同标签冲突类型必失败（100 迭代）。
test "T1.3 row property: unifier makes both sides equal (100 iters)" {
  let gen = @infra_pbt.gen_int_range(0, 1000000)
  let labels = ["a", "b", "c", "d"]
  let ok = @infra_pbt.holds_for_all(gen, fn(seed) {
    // 两侧各取 labels 的一个子集（位掩码），字段类型由种子决定；
    // 双开放行 ⇒ 总能吸收缺字段；仅当共有标签类型冲突时失败。
    let m1 = seed % 16
    let m2 = seed / 16 % 16
    let conflict = seed / 256 % 2 == 0
    fn ty_of(l : String, side : Int) -> RTy {
      // 冲突注入：标签 "a" 在两侧给不同基础类型。
      if conflict && l == "a" {
        if side == 0 {
          RTy::RInt
        } else {
          RTy::RBool
        }
      } else if l == "b" {
        RTy::RBool
      } else {
        RTy::RInt
      }
    }

    fn build(mask : Int, side : Int, tail : Row) -> Row {
      let mut r = tail
      for i in 0..<labels.length() {
        if (mask >> i) % 2 == 1 {
          r = Row::RExtend(labels[i], ty_of(labels[i], side), r)
        }
      }
      r
    }

    let s = RSubst::empty()
    let fresh = RFresh::new(100)
    let a = RTy::RRecord(build(m1, 0, Row::RowVar(0)))
    let b = RTy::RRecord(build(m2, 1, Row::RowVar(1)))
    let both_have_a = m1 % 2 == 1 && m2 % 2 == 1
    match unify_rty(s, fresh, a, b) {
      Ok(_) =>
        normalize_rty(s, a) == normalize_rty(s, b) && !(conflict && both_have_a)
      Err(_) => conflict && both_have_a
    }
  })
  assert_true(ok)
}
