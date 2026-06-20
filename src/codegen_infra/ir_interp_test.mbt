// ir_interp_test.mbt —— 类型化 IR 解释器的烟雾测试（任务 8.3）。
//
// 仅做极少量「直线求值正确、分支求值正确、确定性（两次相等）」的烟雾验证；
// 完整的解释器属性测试（≥100 迭代、三后端）属任务 8.4。
//
// 断言风格说明：统一以 `assert_true(... == ...)`（仅依赖派生 `Eq`）表达，
// 规避 `assert_eq` / `inspect` 因核心库 `Show` 弃用而产生的 deprecated 告警，
// 使本新增文件 `moon check` 零告警。

///|
/// 烟雾测试：直线 `Add` + `Ret` 函数求值正确。
///
/// entry: r1 = Imm(2) + Imm(3) = 5; ret r1 → returned == Some(5)。
test "interp_ir 直线 add+ret 求值" {
  let entry = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [Add(dst=1, lhs=Imm(2), rhs=Imm(3))],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let func = @codegen_infra.TypedFunction::{ entry: "entry", blocks: [entry] }
  let res = @codegen_infra.interp_ir(func, args=Map([]))
  assert_true(res.returned == Some(5))
  assert_true(res.regs.get(1) == Some(5))
}

///|
/// 烟雾测试：入参寄存器预置 + Call 实参求和约定。
///
/// args: {r0:4, r1:6}; entry: r2 = Call("f", [Reg(0), Reg(1)]) = 4+6 = 10;
/// ret r2 → returned == Some(10)。
test "interp_ir 入参预置与 Call 求和约定" {
  let entry = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [Call(dst=2, callee="f", args=[Reg(0), Reg(1)])],
    terminator: Some(Ret(value=Some(Reg(2)))),
  }
  let func = @codegen_infra.TypedFunction::{ entry: "entry", blocks: [entry] }
  let res = @codegen_infra.interp_ir(func, args=Map([(0, 4), (1, 6)]))
  assert_true(res.returned == Some(10))
}

///|
/// 烟雾测试：带条件分支的函数求值正确（CondBr 取 then 分支）。
///
/// args: {r0:1}; entry: CondBr(cond=Reg(0)) → r0 非零走 then；
/// then: r1 = Imm(7) + Imm(0); ret r1 → returned == Some(7)。
/// else: ret Imm(0) → returned == Some(0)（未走到）。
test "interp_ir 条件分支求值" {
  let entry = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [],
    terminator: Some(CondBr(cond=Reg(0), then_="t", else_="e")),
  }
  let t_block = @codegen_infra.TypedBlock::{
    label: "t",
    instrs: [Add(dst=1, lhs=Imm(7), rhs=Imm(0))],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let e_block = @codegen_infra.TypedBlock::{
    label: "e",
    instrs: [],
    terminator: Some(Ret(value=Some(Imm(0)))),
  }
  let func = @codegen_infra.TypedFunction::{
    entry: "entry",
    blocks: [entry, t_block, e_block],
  }
  let taken = @codegen_infra.interp_ir(func, args=Map([(0, 1)]))
  assert_true(taken.returned == Some(7))
  let not_taken = @codegen_infra.interp_ir(func, args=Map([(0, 0)]))
  assert_true(not_taken.returned == Some(0))
}

///|
/// 烟雾测试：Phi 按前驱块选值（来自 then 前驱取对应取值）。
///
/// entry → Br(merge)（prev=entry）；merge: r1 = Phi[(entry, Imm(42)),
/// (other, Imm(7))]，prev==entry 取 Imm(42)；ret r1 → Some(42)。
test "interp_ir Phi 按前驱选值" {
  let entry = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [],
    terminator: Some(Br(target="merge")),
  }
  let merge = @codegen_infra.TypedBlock::{
    label: "merge",
    instrs: [Phi(dst=1, args=[("entry", Imm(42)), ("other", Imm(7))])],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let func = @codegen_infra.TypedFunction::{
    entry: "entry",
    blocks: [entry, merge],
  }
  let res = @codegen_infra.interp_ir(func, args=Map([]))
  assert_true(res.returned == Some(42))
}

///|
/// 烟雾测试：Load / Store 内存读写语义。
///
/// entry: Store(Mem(3), Imm(99)) → 槽3=99; r1 = Load(Mem(3)) → 99;
/// ret r1 → Some(99)。
test "interp_ir load/store 内存语义" {
  let entry = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [Store(addr=Mem(3), value=Imm(99)), Load(dst=1, addr=Mem(3))],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let func = @codegen_infra.TypedFunction::{ entry: "entry", blocks: [entry] }
  let res = @codegen_infra.interp_ir(func, args=Map([]))
  assert_true(res.returned == Some(99))
}

///|
/// 烟雾测试：确定性 —— 同一 IR + 同一 args 两次解释结果完全相等。
test "interp_ir 确定性两次相等" {
  let entry = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [
      Add(dst=1, lhs=Reg(0), rhs=Imm(10)),
      Mul(dst=2, lhs=Reg(1), rhs=Imm(2)),
    ],
    terminator: Some(Ret(value=Some(Reg(2)))),
  }
  let func = @codegen_infra.TypedFunction::{ entry: "entry", blocks: [entry] }
  let r1 = @codegen_infra.interp_ir(func, args=Map([(0, 5)]))
  let r2 = @codegen_infra.interp_ir(func, args=Map([(0, 5)]))
  assert_true(r1 == r2)
  assert_true(r1.returned == Some(30))
}
