// ir_interp_gaps_wbtest.mbt —— IR 解释器兜底语义分支覆盖收口
// （INFRA 第二十一批）：Show 打印、Mem 作值/Imm 作地址兜底、跳转到
// 不存在块、缺终结指令、终结字段持非终结指令的安全停机见证。

///|
fn iig_run(blocks : Array[TypedBlock]) -> IrEvalResult {
  interp_ir(TypedFunction::{ entry: "entry", blocks }, args=Map([]))
}

///|
test "interp_ir Show 打印与操作数兜底语义" {
  // Show：多寄存器 + 有返回值。
  let r1 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [
        Add(dst=1, lhs=Imm(2), rhs=Imm(3)),
        Add(dst=2, lhs=Reg(1), rhs=Imm(1)),
      ],
      terminator: Some(Ret(value=Some(Reg(2)))),
    },
  ])
  assert_true(r1.returned == Some(6))
  let shown = r1.to_string()
  assert_true(shown.contains("IrEvalResult(regs={"))
  assert_true(shown.contains("returned=6"))
  // Show：空寄存器 + 无返回值。
  let r2 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [],
      terminator: Some(Ret(value=None)),
    },
  ])
  assert_true(r2.to_string() == "IrEvalResult(regs={}, returned=None)")
  // Mem 作「值」兜底：未写槽取默认 0；写后取槽内容。
  let r3 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [
        Store(addr=Mem(5), value=Imm(9)),
        Add(dst=1, lhs=Mem(5), rhs=Mem(6)),
      ],
      terminator: Some(Ret(value=Some(Reg(1)))),
    },
  ])
  assert_true(r3.returned == Some(9))
  // Imm 作「地址」兜底：字面值作槽号。
  let r4 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [Store(addr=Imm(7), value=Imm(4)), Load(dst=1, addr=Imm(7))],
      terminator: Some(Ret(value=Some(Reg(1)))),
    },
  ])
  assert_true(r4.returned == Some(4))
}

///|
test "interp_ir 非法结构安全停机" {
  // 跳到不存在块。
  let r1 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [],
      terminator: Some(Br(target="ghost")),
    },
  ])
  assert_true(r1.returned is None)
  // 缺终结指令。
  let r2 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [Add(dst=1, lhs=Imm(1), rhs=Imm(1))],
      terminator: None,
    },
  ])
  assert_true(r2.returned is None)
  assert_true(r2.regs.get(1) == Some(2))
  // 终结字段持非终结指令：安全停机而非崩溃。
  let r3 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [],
      terminator: Some(Phi(dst=1, args=[("entry", Imm(1))])),
    },
  ])
  assert_true(r3.returned is None)
  let r4 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [],
      terminator: Some(Call(dst=1, callee="f", args=[])),
    },
  ])
  assert_true(r4.returned is None)
  // 入口块缺失。
  let r5 = iig_run([
    TypedBlock::{
      label: "other",
      instrs: [],
      terminator: Some(Ret(value=None)),
    },
  ])
  assert_true(r5.returned is None)
  // CondBr 假分支路径。
  let r6 = iig_run([
    TypedBlock::{
      label: "entry",
      instrs: [],
      terminator: Some(CondBr(cond=Imm(0), then_="t", else_="e")),
    },
    TypedBlock::{
      label: "t",
      instrs: [],
      terminator: Some(Ret(value=Some(Imm(1)))),
    },
    TypedBlock::{
      label: "e",
      instrs: [],
      terminator: Some(Ret(value=Some(Imm(2)))),
    },
  ])
  assert_true(r6.returned == Some(2))
}
