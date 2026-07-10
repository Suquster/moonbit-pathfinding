// vm_gaps_wbtest.mbt —— VM 栈值全函数回退分支收口
// （INFRA 第三十四批）：空栈弹取/取顶、非目标构造回退、递归闭包投影。

///|
test "pop_s / top_s：空栈安全回退 SInt(0)" {
  let stack : Array[SVal] = []
  assert_true(pop_s(stack) is SInt(0))
  assert_true(top_s(stack) is SInt(0))
}

///|
test "sval_int / sval_bool：非目标构造回退默认值" {
  assert_eq(sval_int(SBool(true)), 0)
  assert_false(sval_bool(SInt(1)))
}

///|
test "sval_to_val：递归闭包投影为形参正确的占位闭包" {
  let body = Bytecode::{ instrs: [PushInt(1), Ret] }
  let v = sval_to_val(SRecClosure("f", "x", body, @list.empty()))
  assert_true(v is VClosure("x", _, _))
}
