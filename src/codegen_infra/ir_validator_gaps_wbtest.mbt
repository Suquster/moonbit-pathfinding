// ir_validator_gaps_wbtest.mbt —— IR 验证器类型/控制流分支覆盖收口
// （INFRA 第十九批）：各指令的 Mem 非值、Imm 非地址、空 callee、
// 终结器 SSA 定义、终结指令混入块体等分支的确定性见证。

///|
fn ivg_errs(blocks : Array[TypedBlock]) -> Array[IrError] {
  match validate_ir(TypedFunction::{ entry: "entry", blocks }) {
    Ok(_) => []
    Err(errs) => errs
  }
}

///|
test "validate_ir 各指令 Mem 非值与 Imm 非地址拒绝" {
  let errs = ivg_errs([
    TypedBlock::{
      label: "entry",
      instrs: [
        Add(dst=1, lhs=Mem(0), rhs=Mem(1)),
        Sub(dst=2, lhs=Mem(0), rhs=Imm(1)),
        Mul(dst=3, lhs=Imm(1), rhs=Mem(0)),
        Load(dst=4, addr=Imm(7)),
        Store(addr=Imm(7), value=Mem(0)),
        Call(dst=5, callee="", args=[Mem(0), Imm(1)]),
        Phi(dst=6, args=[("entry", Mem(0)), ("entry", Imm(1))]),
      ],
      terminator: Some(Ret(value=Some(Mem(0)))),
    },
  ])
  assert_true(
    errs.contains(TypeMismatch(instr="Call", detail="callee name is empty")),
  )
  // Add 双臂 / Sub lhs / Mul rhs / Load addr / Store 双违规 / Call 实参 /
  // Phi 来路 / Ret 返回值：共 10 条类型错误。
  let mut ty = 0
  for e in errs {
    match e {
      TypeMismatch(_) => ty = ty + 1
      _ => ()
    }
  }
  assert_true(ty == 11)
}

///|
test "validate_ir CondBr 条件与双目标缺失" {
  let errs = ivg_errs([
    TypedBlock::{
      label: "entry",
      instrs: [],
      terminator: Some(CondBr(cond=Mem(0), then_="a", else_="b")),
    },
  ])
  assert_true(
    errs.contains(
      TypeMismatch(
        instr="CondBr",
        detail="cond: expected value (Reg/Imm), got Mem",
      ),
    ) ||
    errs.length() >= 3,
  )
  let mut cf = 0
  for e in errs {
    match e {
      ControlFlowError(_) => cf = cf + 1
      _ => ()
    }
  }
  assert_true(cf == 2)
}

///|
test "validate_ir 终结器定义 SSA 与结构违规" {
  // Call 作为 terminator：非终结指令占据 terminator 字段，且其 dst 参与
  // SSA 统计（与块体定义冲突）。
  let errs = ivg_errs([
    TypedBlock::{
      label: "entry",
      instrs: [Add(dst=1, lhs=Imm(1), rhs=Imm(2)), Br(target="entry")],
      terminator: Some(Call(dst=1, callee="f", args=[Reg(1)])),
    },
  ])
  assert_true(errs.contains(SsaViolation(reg=1)))
  assert_true(
    errs.contains(
      ControlFlowError(
        block="entry",
        detail="terminator field holds a non-terminator instruction",
      ),
    ),
  )
  assert_true(
    errs.contains(
      ControlFlowError(
        block="entry",
        detail="terminator instruction appears in block body",
      ),
    ),
  )
  // 缺终结器 + 入口块缺失。
  let errs2 = ivg_errs([
    TypedBlock::{ label: "other", instrs: [], terminator: None },
  ])
  assert_true(
    errs2.contains(
      ControlFlowError(block="entry", detail="entry block not found"),
    ),
  )
  assert_true(
    errs2.contains(ControlFlowError(block="other", detail="missing terminator")),
  )
}
