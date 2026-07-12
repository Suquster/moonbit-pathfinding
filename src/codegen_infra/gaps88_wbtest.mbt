// gaps88_wbtest.mbt —— 内部记号/诊断辅助余臂（第八十八批）。

///|
/// token_of：负 id 为临时记号，无名正 id 回退 v<id>。
test "token_of：临时与无名回退记号" {
  let id2name : Map[Int, String] = Map([])
  assert_eq(token_of(-3, id2name), "tmp3")
  assert_eq(token_of(7, id2name), "v7")
  id2name[7] = "x"
  assert_eq(token_of(7, id2name), "x#7")
}

///|
/// operand_kind_name：三类操作数名称。
test "operand_kind_name：Reg/Imm/Mem" {
  assert_eq(operand_kind_name(Reg(1)), "Reg")
  assert_eq(operand_kind_name(Imm(3)), "Imm")
  assert_eq(operand_kind_name(Mem(0)), "Mem")
}
