// sccp_gaps_wbtest.mbt —— SCCP 格 meet/求值回退分支收口
// （INFRA 第四十五批）。

///|
test "lat_meet：Top 右单位元与常量相遇" {
  assert_true(lat_meet(Const(1), Top) == Const(1))
  assert_true(lat_meet(Top, Const(2)) == Const(2))
  assert_true(lat_meet(Const(1), Const(1)) == Const(1))
  assert_true(lat_meet(Const(1), Const(2)) == Bottom)
}

///|
test "eval_def_lattice：不可折叠算符与非法记号数回退 Bottom" {
  let values : Map[String, LatticeValue] = Map([])
  let defset : Map[String, Bool] = Map([])
  // 两常量但算符不可折叠 → Bottom。
  assert_true(
    eval_def_lattice(["x", "=", "6", "/", "3"], values, defset) == Bottom,
  )
  // 记号数非 3/5 → Bottom。
  assert_true(eval_def_lattice(["x", "="], values, defset) == Bottom)
}

///|
test "sccp：空程序恒等返回" {
  let p = SsaProgram::{ blocks: [], phis: [] }
  let out = sccp(p)
  assert_eq(out.blocks.length(), 0)
}
