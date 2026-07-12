// 黑盒测试：覆盖率审计收口（INFRA 第八十批）——
// 复制传播的无版本左值/φ 实参替换、VarRef 选择模板与幽灵后继跳过。

///|
test "CopyProp：无版本左值复制不参与传播" {
  let p : @codegen_infra.SsaProgram = {
    blocks: [{ label: "b0", instrs: ["x = y#1", "z#2 = y#1 + 0"], succs: [] }],
    phis: [],
  }
  let out = @codegen_infra.run_passes(p, [@codegen_infra.Pass::CopyProp])
  // 无版本左值 `x = y#1` 原样保留，不产生替换。
  assert_true(out.blocks[0].instrs.contains("x = y#1"))
}

///|
test "CopyProp：φ 实参替换为复制源版本" {
  let p : @codegen_infra.SsaProgram = {
    blocks: [
      { label: "b0", instrs: ["a#2 = b#1"], succs: ["b1"] },
      { label: "b1", instrs: [], succs: [] },
    ],
    phis: [{ dest: { id: 3 }, args: [{ id: 2 }] }],
  }
  let out = @codegen_infra.run_passes(p, [@codegen_infra.Pass::CopyProp])
  assert_eq(out.phis[0].args[0].id, 1)
}

///|
test "select：VarRef 命中显式加载模板" {
  let rules : Array[@codegen_infra.IselRule] = [
    { pattern: "VarRef", template: "ld" },
  ]
  let ir : @codegen_infra.IrNode = @codegen_infra.IrNode::VarRef({ id: 7 })
  let out = @codegen_infra.select(rules, ir)
  assert_eq(out.length(), 1)
  assert_eq(out[0].op, "ld")
  assert_eq(out[0].operands[1], "v7")
}

///|
test "build_ssa：指向不存在标签的幽灵后继被跳过" {
  let blocks : Array[@codegen_infra.BasicBlock] = [
    { label: "e", instrs: ["x#1 = a#0 + 1"], succs: ["ghost"] },
  ]
  let out = @codegen_infra.build_ssa(blocks)
  assert_eq(out.blocks.length(), 1)
}
