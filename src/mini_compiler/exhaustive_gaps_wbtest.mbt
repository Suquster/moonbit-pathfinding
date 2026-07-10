// exhaustive_gaps_wbtest.mbt —— Maranget 穷尽性内部算子收口
// （INFRA 第二十三批）：通配特化展开、见证重建、缺失整数字面量。

///|
test "specialize_row：通配首模式按元数展开等量通配" {
  match specialize_row(CTuple(2), 2, [PWild, PInt(9)]) {
    Some(out) => {
      assert_eq(out.length(), 3)
      assert_true(out[0] is PWild)
      assert_true(out[1] is PWild)
      assert_true(out[2] is PInt(9))
    }
    None => assert_true(false)
  }
}

///|
test "rebuild_witness：整数构造子重建 PInt 头" {
  let (head, rest) = rebuild_witness(CInt(7), 0, [PBool(true)])
  assert_true(head is PInt(7))
  assert_eq(rest.length(), 1)
}

///|
test "redundant_arms：完整签名后通配臂冗余（元组/布尔）" {
  // 元组完整签名 → 通配臂无用（签名分派路径，逐构造展开通配）。
  let r1 = redundant_arms(
    [PTuple([PWild, PWild]), PWild],
    TXTuple([TXInt, TXBool]),
  )
  assert_true(r1 == [1])
  // 布尔完整签名 → 第三臂冗余。
  let r2 = redundant_arms([PBool(true), PBool(false), PWild], TXBool)
  assert_true(r2 == [2])
  // 通配行在前 → 后续构造臂冗余（矩阵含通配行的 None 分派）。
  let r3 = redundant_arms([PWild, PInt(1)], TXInt)
  assert_true(r3 == [1])
}

///|
test "check_exhaustive：布尔/列表缺失见证与穷尽判定" {
  assert_true(check_exhaustive([PBool(true)], TXBool) is Some(_))
  assert_true(check_exhaustive([PNil], TXList(TXInt)) is Some(_))
  assert_true(
    check_exhaustive([PNil, PCons(PWild, PWild)], TXList(TXInt)) is None,
  )
  // 元组首元非整数（布尔）缺失见证：头以 PWild 重建。
  assert_true(
    check_exhaustive([PTuple([PBool(true), PInt(0)])], TXTuple([TXBool, TXInt]))
    is Some(_),
  )
}

///|
test "fresh_int_not_in：跳过既有字面量并忽略非整数头" {
  let p = fresh_int_not_in([PInt(0), PInt(1), PWild, PBool(true)])
  assert_true(p is PInt(2))
}

///|
test "missing_witness：非整数首列见证回退 PWild 且拼接余列" {
  // 布尔首列已覆盖 true/false 之外仍缺失？构造未覆盖余列使见证含 PWild 头。
  let w = check_exhaustive(
    [PTuple([PWild, PBool(true)])],
    TXTuple([TXList(TXInt), TXBool]),
  )
  assert_true(w is Some(_))
}

///|
test "useful：构造子特化失配与完整签名余列拼接" {
  // 元组模式列固定 → root_ctor 命中、specialize 后余列拼接（sub_tys_of）。
  let r = redundant_arms(
    [PTuple([PNil, PWild]), PTuple([PCons(PWild, PWild), PWild])],
    TXTuple([TXList(TXInt), TXBool]),
  )
  assert_true(r.length() == 0)
  // 完整签名（列表 Nil/Cons）后通配臂冗余：走 ws 余列拼接分支。
  let r2 = redundant_arms(
    [PTuple([PNil, PWild]), PTuple([PCons(PWild, PWild), PWild]), PWild],
    TXTuple([TXList(TXInt), TXBool]),
  )
  assert_true(r2 == [2])
}
