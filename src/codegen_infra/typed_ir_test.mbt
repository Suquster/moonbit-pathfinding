// typed_ir_test.mbt —— 类型化 IR 数据结构的烟雾测试（任务 8.1）。
//
// 仅做极少量「能构造、Eq 自洽、辅助方法语义正确、Show 可渲染」的烟雾验证；
// 完整的验证器/解释器属性测试分别属任务 8.2 / 8.3 / 8.4。
//
// 断言风格说明：统一以 `assert_true(... == ...)`（仅依赖派生 `Eq`）表达，
// 规避 `assert_eq` / `inspect` 因核心库 `Show` 弃用而产生的 deprecated 告警，
// 使本新增文件 `moon check` 零告警。

///|
/// 烟雾测试：操作数与指令可构造，`Eq` 自洽（相同构造相等、不同构造不等）。
test "typed_ir 构造与相等性" {
  let i1 : @codegen_infra.TypedInstr = Add(dst=1, lhs=Reg(2), rhs=Imm(3))
  let i2 : @codegen_infra.TypedInstr = Add(dst=1, lhs=Reg(2), rhs=Imm(3))
  let i3 : @codegen_infra.TypedInstr = Add(dst=1, lhs=Reg(2), rhs=Imm(4))
  assert_true(i1 == i2)
  assert_true(i1 != i3)
}

///|
/// 烟雾测试：`defined_reg` 对定义类/非定义类指令的语义。
test "typed_ir defined_reg 语义" {
  let mul : @codegen_infra.TypedInstr = Mul(dst=7, lhs=Reg(1), rhs=Reg(2))
  let store : @codegen_infra.TypedInstr = Store(addr=Mem(0), value=Reg(1))
  let ret : @codegen_infra.TypedInstr = Ret(value=Some(Reg(7)))
  assert_true(mul.defined_reg() == Some(7))
  assert_true(store.defined_reg() == None)
  assert_true(ret.defined_reg() == None)
}

///|
/// 烟雾测试：`is_terminator` 区分终结/普通指令。
test "typed_ir is_terminator 语义" {
  let br : @codegen_infra.TypedInstr = Br(target="L2")
  let condbr : @codegen_infra.TypedInstr = CondBr(
    cond=Reg(1),
    then_="L2",
    else_="L3",
  )
  let load : @codegen_infra.TypedInstr = Load(dst=1, addr=Mem(0))
  assert_true(br.is_terminator())
  assert_true(condbr.is_terminator())
  assert_true(load.is_terminator() == false)
}

///|
/// 烟雾测试：函数可构造，`block_labels` 保序收集标签，`Show` 可渲染非空文本。
test "typed_ir 函数与 block_labels / Show" {
  let entry_block = @codegen_infra.TypedBlock::{
    label: "entry",
    instrs: [Add(dst=1, lhs=Imm(2), rhs=Imm(3))],
    terminator: Some(Br(target="exit")),
  }
  let exit_block = @codegen_infra.TypedBlock::{
    label: "exit",
    instrs: [],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let func = @codegen_infra.TypedFunction::{
    entry: "entry",
    blocks: [entry_block, exit_block],
  }
  assert_true(func.block_labels() == ["entry", "exit"])
  // Show 可渲染（含入口标签子串），手写 `Show` 路径被覆盖。
  let text = func.to_string()
  assert_true(text.contains("entry"))
}
