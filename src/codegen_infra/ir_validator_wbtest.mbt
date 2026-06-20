// ir_validator_wbtest.mbt —— IR 验证器烟雾测试（任务 8.2，白盒）。
//
// 置于白盒测试（`_wbtest.mbt`，与被测代码同包），以便直接构造 `pub`（包外
// 只读）的 `IrError` 变体用于断言比对。仅做极少量「合法 IR 通过 / 三类错误
// 各被捕获」的烟雾验证；完整属性测试属任务 8.4。断言统一以
// `assert_true(... == ...)` / `Array::contains`（仅依赖派生 `Eq`）表达，
// 规避核心库 `Show` 弃用告警，使本文件零告警。

///|
/// 构造一个合法（满足 SSA / 类型 / 控制流）的最小函数：
/// entry: r1 = 2 + 3; br exit / exit: ret r1。
fn make_valid_function() -> TypedFunction {
  let entry_block = TypedBlock::{
    label: "entry",
    instrs: [Add(dst=1, lhs=Imm(2), rhs=Imm(3))],
    terminator: Some(Br(target="exit")),
  }
  let exit_block = TypedBlock::{
    label: "exit",
    instrs: [],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  TypedFunction::{ entry: "entry", blocks: [entry_block, exit_block] }
}

///|
/// AC2：合法 SSA 的 IR 验证通过（返回 `Ok`）。
test "validate_ir 合法 IR 通过" {
  let func = make_valid_function()
  let ok = match validate_ir(func) {
    Ok(_) => true
    Err(_) => false
  }
  assert_true(ok)
}

///|
/// AC3：寄存器被定义两次 → `SsaViolation`。
test "validate_ir 重复定义报 SsaViolation" {
  let block = TypedBlock::{
    label: "entry",
    instrs: [
      Add(dst=1, lhs=Imm(2), rhs=Imm(3)),
      Mul(dst=1, lhs=Reg(1), rhs=Imm(2)),
    ],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let func = TypedFunction::{ entry: "entry", blocks: [block] }
  match validate_ir(func) {
    Ok(_) => assert_true(false)
    Err(errs) => assert_true(errs.contains(SsaViolation(reg=1)))
  }
}

///|
/// AC5：跳转到不存在的块 → `ControlFlowError`。
test "validate_ir 跳到不存在块报 ControlFlowError" {
  let block = TypedBlock::{
    label: "entry",
    instrs: [],
    terminator: Some(Br(target="nowhere")),
  }
  let func = TypedFunction::{ entry: "entry", blocks: [block] }
  match validate_ir(func) {
    Ok(_) => assert_true(false)
    Err(errs) =>
      assert_true(
        errs.contains(
          ControlFlowError(
            block="entry",
            detail="jump target 'nowhere' not found",
          ),
        ),
      )
  }
}

///|
/// AC4：`Store` 以 `Imm` 作写入地址 → `TypeMismatch`。
test "validate_ir Store 立即数地址报 TypeMismatch" {
  let block = TypedBlock::{
    label: "entry",
    instrs: [Store(addr=Imm(0), value=Reg(1))],
    terminator: Some(Ret(value=None)),
  }
  let func = TypedFunction::{ entry: "entry", blocks: [block] }
  match validate_ir(func) {
    Ok(_) => assert_true(false)
    Err(errs) =>
      assert_true(
        errs.contains(
          TypeMismatch(
            instr="Store",
            detail="addr is Imm, expected address operand (Reg or Mem)",
          ),
        ),
      )
  }
}
