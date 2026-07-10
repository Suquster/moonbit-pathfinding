// gvn_gaps_wbtest.mbt —— 全局值编号回退分支收口
// （INFRA 第二十八批）。

///|
test "gvn：空程序原样返回" {
  let p = SsaProgram::{ blocks: [], phis: [] }
  let out = gvn(p)
  assert_eq(out.blocks.length(), 0)
}

///|
test "operand_vn：已定义未编号记号唯一回退" {
  let vn_of : Map[String, String] = Map([])
  let defset : Map[String, Bool] = Map([])
  defset["x_1"] = true
  assert_eq(operand_vn("x_1", vn_of, defset), "U|x_1")
  assert_eq(operand_vn("7", vn_of, defset), "L|7")
  assert_eq(operand_vn("ext", vn_of, defset), "E|ext")
}

///|
test "def_value_number：非常规形态唯一文本编号" {
  let vn_of : Map[String, String] = Map([])
  let defset : Map[String, Bool] = Map([])
  let vn = def_value_number(["x", "=", "a", "+", "b", "+", "c"], vn_of, defset)
  assert_true(vn.has_prefix("U|"))
}
