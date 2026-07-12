// tco_gaps_test.mbt —— 尾调用感知解释器布尔指令与无 Ret 帧收尾收口
// （INFRA 第二十五批）。

///|
test "run_tco：PushBool 与 Logic And/Or 求值" {
  let bc_and = Bytecode::{
    instrs: [PushBool(true), PushBool(false), Logic(And), Ret],
  }
  assert_true(run_tco(bc_and, ml_env_empty()) == VBool(false))
  let bc_or = Bytecode::{
    instrs: [PushBool(false), PushBool(true), Logic(Or), Ret],
  }
  assert_true(run_tco(bc_or, ml_env_empty()) == VBool(true))
}

///|
test "run_tco：被调帧字节码耗尽（无 Ret）时安全弹帧" {
  // 闭包体不含 Ret：帧耗尽 → 弹帧回调用者，栈顶保留结果。
  let body = Bytecode::{ instrs: [PushInt(7)] }
  let bc = Bytecode::{ instrs: [MkClosure("x", body), PushInt(0), Call, Ret] }
  assert_true(run_tco(bc, ml_env_empty()) == VInt(7))
}

///|
test "run_tco：非尾位置调用且被调帧无 Ret 时弹帧续接调用者" {
  // Call 为最后一条指令（非尾位置判定为假）：被调帧耗尽走弹帧余支。
  let body = Bytecode::{ instrs: [PushInt(7)] }
  let bc = Bytecode::{ instrs: [MkClosure("x", body), PushInt(0), Call] }
  assert_true(run_tco(bc, ml_env_empty()) == VInt(7))
}
