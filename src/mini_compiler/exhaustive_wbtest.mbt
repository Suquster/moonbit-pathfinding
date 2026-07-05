// exhaustive_wbtest.mbt —— T1.3 穷尽性 / 冗余检查的定向用例与属性测试
// （白盒：需访问私有 match_pattern 验证语义一致性）。

///|
/// 由模式见证实例化一个具体值（通配/变量取该类型默认值）。
fn instantiate_witness(p : Pattern, ty : TyX) -> ValX {
  match (p, ty) {
    (PInt(v), _) => VXInt(v)
    (PBool(b), _) => VXBool(b)
    (PTuple(ps), TXTuple(ts)) => {
      let vs : Array[ValX] = []
      for i in 0..<ps.length() {
        vs.push(instantiate_witness(ps[i], ts[i]))
      }
      VXTuple(vs)
    }
    (PNil, _) => VXList([])
    (PCons(h, t), TXList(et)) => {
      let head = instantiate_witness(h, et)
      match instantiate_witness(t, TXList(et)) {
        VXList(rest) => {
          let out : Array[ValX] = [head]
          for v in rest {
            out.push(v)
          }
          VXList(out)
        }
        other => other
      }
    }
    (_, t) => default_value_of(t)
  }
}

///|
/// 类型默认值（通配位置的实例化）。
fn default_value_of(ty : TyX) -> ValX {
  match ty {
    TXInt => VXInt(0)
    TXBool => VXBool(false)
    TXTuple(ts) => {
      let vs : Array[ValX] = []
      for t in ts {
        vs.push(default_value_of(t))
      }
      VXTuple(vs)
    }
    TXList(_) => VXList([])
    TXFun(_, _) => VXInt(0) // 函数无 ValX 表示：占位（模式只能是通配）
  }
}

///|
/// 值是否被任一 arm 覆盖。
fn covered(pats : Array[Pattern], v : ValX) -> Bool {
  for p in pats {
    if match_pattern(p, v) is Some(_) {
      return true
    }
  }
  false
}

///|
test "T1.3: exhaustiveness on bool / list / tuple" {
  // bool：true/false 齐 ⇒ 穷尽；缺 false ⇒ 见证 PBool(false)。
  assert_true(check_exhaustive([PBool(true), PBool(false)], TXBool) is None)
  match check_exhaustive([PBool(true)], TXBool) {
    Some(w) => assert_true(w == PBool(false))
    None => assert_true(false)
  }
  // list：Nil + Cons(_, _) ⇒ 穷尽；只有 Nil ⇒ 缺 Cons。
  let full : Array[Pattern] = [PNil, PCons(PWild, PWild)]
  assert_true(check_exhaustive(full, TXList(TXInt)) is None)
  match check_exhaustive([PNil], TXList(TXInt)) {
    Some(w) => assert_true(w is PCons(_, _))
    None => assert_true(false)
  }
  // int：字面量永不穷尽，通配才穷尽。
  assert_true(check_exhaustive([PInt(0), PInt(1)], TXInt) is Some(_))
  assert_true(check_exhaustive([PWild], TXInt) is None)
  // tuple：嵌套 bool 分量需要四种组合或通配。
  let pair = TXTuple([TXBool, TXBool])
  let three : Array[Pattern] = [
    PTuple([PBool(true), PBool(true)]),
    PTuple([PBool(true), PBool(false)]),
    PTuple([PBool(false), PBool(true)]),
  ]
  match check_exhaustive(three, pair) {
    Some(w) => assert_true(w == PTuple([PBool(false), PBool(false)]))
    None => assert_true(false)
  }
}

///|
test "T1.3: redundant arm detection" {
  // 通配之后的 arm 一律冗余。
  let pats : Array[Pattern] = [PWild, PInt(1), PBool(true)]
  assert_true(redundant_arms(pats, TXInt) == [1, 2])
  // 重复字面量冗余。
  assert_true(redundant_arms([PInt(1), PInt(1), PWild], TXInt) == [1])
  // bool 两值齐后再来任何 arm 冗余。
  assert_true(redundant_arms([PBool(true), PBool(false), PWild], TXBool) == [2])
  // 无冗余情形。
  assert_true(redundant_arms([PNil, PCons(PWild, PWild)], TXList(TXInt)) == [])
}

///|
/// T1.3 属性：见证语义正确——check_exhaustive 返回的缺失见证实例化后
/// **不被任何 arm 覆盖**；返回 None 时随机值恒被覆盖（100 迭代）。
test "T1.3 property: exhaustiveness witness is sound (100 iters)" {
  let gen = @infra_pbt.gen_int_range(0, 1000000)
  let ok = @infra_pbt.holds_for_all(gen, fn(seed) {
    // 由种子构造随机类型（bool / int / list / 2-tuple）与随机模式集。
    let ty : TyX = match seed % 4 {
      0 => TXBool
      1 => TXInt
      2 => TXList(TXBool)
      _ => TXTuple([TXBool, TXInt])
    }
    let n = seed / 4 % 4 + 1
    let pats : Array[Pattern] = []
    for i in 0..<n {
      let k = (seed / 16 + i * 7) % 8
      let p : Pattern = match ty {
        TXBool => if k % 2 == 0 { PBool(true) } else { PBool(false) }
        TXInt => if k == 7 { PWild } else { PInt(k) }
        TXList(_) =>
          if k % 3 == 0 {
            PNil
          } else if k % 3 == 1 {
            PCons(PWild, PWild)
          } else {
            PCons(PBool(true), PNil)
          }
        _ =>
          if k % 2 == 0 {
            PTuple([PBool(true), PWild])
          } else {
            PTuple([PWild, PInt(k)])
          }
      }
      pats.push(p)
    }
    match check_exhaustive(pats, ty) {
      Some(w) => {
        // 见证实例化后不被任何 arm 覆盖。
        let v = instantiate_witness(w, ty)
        !covered(pats, v)
      }
      None => {
        // 穷尽：抽样若干该类型的值必被覆盖。
        let samples : Array[ValX] = match ty {
          TXBool => [VXBool(true), VXBool(false)]
          TXInt => [VXInt(0), VXInt(3), VXInt(-17), VXInt(seed % 100)]
          TXList(_) =>
            [
              VXList([]),
              VXList([VXBool(true)]),
              VXList([VXBool(false), VXBool(true)]),
            ]
          _ =>
            [
              VXTuple([VXBool(true), VXInt(0)]),
              VXTuple([VXBool(false), VXInt(5)]),
            ]
        }
        let mut all = true
        for v in samples {
          if !covered(pats, v) {
            all = false
          }
        }
        all
      }
    }
  })
  assert_true(ok)
}
