// compat_test.mbt —— 既有 API 向后兼容回归（任务 19.5）。
//
// 回归断言：`allocate_coloring` / `allocate_linear_scan` / `interference_components`
// / `build_ssa` / `run_passes` / `select` 行为与 `0.1.0` 逐字段一致，核心类型字段
// / 派生语义不变，`interference_components` 仍复用 `@directed.tarjan_scc`。
// _Requirements: 6.4, 10.4, 11.4, 15.1, 15.2, 15.3_

///|
/// allocate_coloring（基线贪心）：K3 在 k=3 全部着色为寄存器、无溢出（冻结）。
test "compat: allocate_coloring K3 k=3 全部着色" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [
      ({ id: 0 }, { id: 1 }),
      ({ id: 1 }, { id: 2 }),
      ({ id: 0 }, { id: 2 }),
    ],
  }
  let alloc = allocate_coloring(g, 3)
  @debug.debug_inspect(alloc.get({ id: 0 }), content="Some(Reg(0))")
  @debug.debug_inspect(alloc.get({ id: 1 }), content="Some(Reg(1))")
  @debug.debug_inspect(alloc.get({ id: 2 }), content="Some(Reg(2))")
}

///|
/// allocate_linear_scan：非重叠区间复用寄存器（冻结）。
test "compat: allocate_linear_scan 非重叠区间复用寄存器" {
  let intervals = [
    LiveInterval::{ variable: { id: 0 }, start: 0, end: 2 },
    LiveInterval::{ variable: { id: 1 }, start: 1, end: 3 },
    LiveInterval::{ variable: { id: 2 }, start: 4, end: 6 },
  ]
  let alloc = allocate_linear_scan(intervals, 2)
  @debug.debug_inspect(alloc.get({ id: 0 }), content="Some(Reg(0))")
  @debug.debug_inspect(alloc.get({ id: 1 }), content="Some(Reg(1))")
  @debug.debug_inspect(alloc.get({ id: 2 }), content="Some(Reg(0))")
}

///|
/// interference_components：复用 @directed.tarjan_scc 分解连通分量（冻结）。
test "compat: interference_components 连通分量分解" {
  let g1 = InterferenceGraph::{ nodes: [{ id: 0 }, { id: 1 }], edges: [] }
  inspect(interference_components(g1).length(), content="2")
  let g2 = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }],
    edges: [({ id: 0 }, { id: 1 })],
  }
  inspect(interference_components(g2).length(), content="1")
}

///|
/// build_ssa：菱形汇合插入一个 φ、定义左值版本化（冻结）。
test "compat: build_ssa 菱形插入 φ 并版本化" {
  let p = build_ssa([
    BasicBlock::{ label: "entry", instrs: [], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ])
  inspect(p.phis.length(), content="1")
  inspect(p.blocks[1].instrs[0], content="x#0 = 1")
}

///|
/// run_passes：既有 Pass 序列常量折叠行为冻结。
test "compat: run_passes ConstFold 冻结" {
  let base = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1 + 2", "ret x"], succs: [] },
  ])
  let out = run_passes(base, [Pass::ConstFold])
  inspect(out.blocks[0].instrs[0], content="x#0 = 3")
}

///|
/// select：既有 isel 后序遍历序列冻结。
test "compat: select 后序遍历序列冻结" {
  let rules : Array[IselRule] = [
    { pattern: "Const", template: "li" },
    { pattern: "BinOp", template: "add" },
  ]
  let instrs = select(rules, IrNode::BinOp("+", Const(1), Const(2)))
  inspect(instrs.length(), content="3")
  inspect(instrs[2].op, content="add")
  inspect(instrs[2].operands[0], content="t2")
}

///|
/// 核心类型字段 / 派生语义不变：Location / Var 相等与可比较。
test "compat: 核心类型派生语义不变" {
  inspect(Location::Reg(3) == Location::Reg(3), content="true")
  inspect(Location::Reg(0) == Location::Spill(0), content="false")
  inspect(({ id: 1 } : Var) == ({ id: 1 } : Var), content="true")
}
