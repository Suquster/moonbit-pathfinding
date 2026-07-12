// 黑盒测试：覆盖率审计收口（INFRA 第七十九批）——
// 解释器步数上限停机、evaluate 未知标签/坏版本号/未知算符回退、
// George 合并的高危邻居拒绝。

///|
test "interp_ir：无限循环达步数上限安全停机" {
  let f : @codegen_infra.TypedFunction = {
    entry: "l",
    blocks: [
      {
        label: "l",
        instrs: [
          @codegen_infra.TypedInstr::Add(
            dst=0,
            lhs=@codegen_infra.Operand::Imm(1),
            rhs=@codegen_infra.Operand::Reg(0),
          ),
        ],
        terminator: Some(@codegen_infra.TypedInstr::Br(target="l")),
      },
    ],
  }
  let out = @codegen_infra.interp_ir(f, args=Map([]))
  assert_true(out.returned is None)
}

///|
test "evaluate：未知路径标签跳过且坏版本号/未知算符安全回退" {
  let p : @codegen_infra.SsaProgram = {
    blocks: [
      { label: "b0", instrs: ["x#1 = a#0 / b#0", "y#2 = z#q"], succs: [] },
    ],
    phis: [{ dest: { id: 9 }, args: [] }],
  }
  let out = @codegen_infra.evaluate(p, Map([("a#0", 6), ("b#0", 2)]), [
    "nope", "b0",
  ])
  // 未知算符回退为左操作数取值。
  assert_true(out.values.get("x#1") == Some(6))
}

///|
test "gvn：菱形双臂含字面量操作数的冗余表达式上提合并" {
  let p : @codegen_infra.SsaProgram = {
    blocks: [
      { label: "e", instrs: [], succs: ["l", "r"] },
      { label: "l", instrs: ["x#1 = a#0 + 1"], succs: ["j"] },
      { label: "r", instrs: ["y#2 = a#0 + 1"], succs: ["j"] },
      { label: "j", instrs: ["z#3 = x#1 + y#2", "ret z#3"], succs: [] },
    ],
    phis: [],
  }
  let out = @codegen_infra.gvn(p)
  let mut occurrences = 0
  for b in out.blocks {
    for instr in b.instrs {
      if instr.contains("a#0 + 1") {
        occurrences = occurrences + 1
      }
    }
  }
  assert_eq(occurrences, 1)
}

///|
test "can_coalesce_george：高度数且不与 b 冲突的邻居拒绝合并" {
  let a : @codegen_infra.Var = { id: 0 }
  let b : @codegen_infra.Var = { id: 1 }
  let t : @codegen_infra.Var = { id: 2 }
  let c : @codegen_infra.Var = { id: 3 }
  let d : @codegen_infra.Var = { id: 4 }
  let g : @codegen_infra.InterferenceGraph = {
    nodes: [a, b, t, c, d],
    edges: [(a, t), (t, c), (t, d)],
  }
  assert_false(@codegen_infra.can_coalesce_george(g, a, b, 2))
}
