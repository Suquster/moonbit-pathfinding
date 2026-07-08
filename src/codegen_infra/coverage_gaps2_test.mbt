// 黑盒测试：codegen_infra 未覆盖分支（TypedInstr/Operand/IrError Show 渲染、
// 验证器错误分支、线性扫描 k=0、liveness 词法边界）。

///|
test "typed_ir：全指令 Show 渲染（Sub/Store/Call/Ret None/CondBr/Phi/Mem）" {
  let sub = TypedInstr::Sub(dst=1, lhs=Reg(2), rhs=Mem(4))
  assert_true("\{sub}".contains("Sub(") && "\{sub}".contains("Mem(4)"))
  let st = TypedInstr::Store(addr=Mem(0), value=Imm(7))
  assert_true("\{st}".contains("Store("))
  let call = TypedInstr::Call(dst=3, callee="f", args=[Reg(1), Imm(2)])
  let cs = "\{call}"
  assert_true(
    cs.contains("Call(") && cs.contains("Reg(1)") && cs.contains(", "),
  )
  let rn = TypedInstr::Ret(value=None)
  assert_true("\{rn}".contains("Ret(None)"))
  let cb = TypedInstr::CondBr(cond=Reg(5), then_="a", else_="b")
  assert_true("\{cb}".contains("CondBr("))
  let phi = TypedInstr::Phi(dst=6, args=[("a", Reg(1)), ("b", Imm(0))])
  assert_true("\{phi}".contains("Phi("))
  let op : Operand = Mem(9)
  assert_true("\{op}" == "Mem(9)")
}

///|
test "ir_validator：SSA 重定义 / 双操作数类型错误 / 控制流错误的 Show 渲染" {
  // 同一寄存器定义两次 → SsaViolation；rhs 用 Mem → TypeMismatch。
  let f : TypedFunction = {
    entry: "e",
    blocks: [
      {
        label: "e",
        instrs: [
          Add(dst=1, lhs=Mem(0), rhs=Mem(1)),
          Add(dst=1, lhs=Imm(1), rhs=Imm(2)),
        ],
        terminator: Some(Br(target="missing")),
      },
    ],
  }
  guard validate_ir(f) is Err(errs)
  let all = errs.map(fn(e) { "\{e}" }).join(";")
  assert_true(all.contains("SsaViolation"))
  assert_true(all.contains("TypeMismatch") && all.contains("rhs"))
  assert_true(all.contains("ControlFlowError"))
}

///|
test "线性扫描：k=0 时所有区间溢出" {
  let ivs : Array[LiveInterval] = [
    { variable: { id: 1 }, start: 0, end: 3 },
    { variable: { id: 2 }, start: 1, end: 2 },
  ]
  let alloc = allocate_linear_scan(ivs, 0)
  assert_true(alloc.get({ id: 1 }) is Some(Spill(_)))
  assert_true(alloc.get({ id: 2 }) is Some(Spill(_)))
  assert_true(allocation_has_spill(alloc))
}

///|
test "liveness：空指令块与 liveness_step 缺省空集分支" {
  let blocks : Array[BasicBlock] = [
    { label: "a", instrs: [""], succs: ["b"] },
    { label: "b", instrs: ["ret x"], succs: [] },
  ]
  let live = analyze_liveness(blocks)
  // liveness_step 对缺失 live_in 的块走空集缺省分支。
  let empty : LivenessResult = { live_in: Map([]), live_out: Map([]) }
  let stepped = liveness_step(blocks, empty)
  assert_true(stepped.live_in.contains("a") && stepped.live_in.contains("b"))
  assert_true(live.live_in.contains("b"))
}
