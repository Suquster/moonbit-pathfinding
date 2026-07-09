// ml_eval_gaps_wbtest.mbt —— ML 解释器全函数回退分支收口
// （INFRA 第二十七批）。

///|
test "ml_env_lookup：递归记录携带非闭包值原样返回" {
  let env = ml_env_extend(ml_env_empty(), rec_key("f"), VInt(5))
  assert_true(ml_env_lookup(env, "f") == Some(VInt(5)))
}

///|
test "as_int / as_bool：非目标构造回退默认值" {
  assert_eq(as_int(VBool(true)), 0)
  assert_false(as_bool(VInt(1)))
}

///|
test "eval_ml：未绑定变量全函数回退为 0" {
  let sp : Span = { line: 0, col: 0 }
  assert_true(eval_ml(TEVar("ghost", TyInt, sp)) == VInt(0))
}

///|
test "VM::run：被调帧字节码耗尽（无 Ret）安全弹帧" {
  let body = Bytecode::{ instrs: [PushInt(9)] }
  let bc = Bytecode::{ instrs: [MkClosure("x", body), PushInt(0), Call, Ret] }
  assert_true(VM::run(bc, ml_env_empty()) == VInt(9))
}
