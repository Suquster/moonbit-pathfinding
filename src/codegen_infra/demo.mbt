// demo.mbt —— 旗舰端到端示例：完整后端流水线，旁路新增。
//
// 设计落点（design.md §4.12，R12）：一份带条件分支（含菱形汇合）的小程序，串起
// 活跃性 → 支配边界最小 SSA → SCCP/GVN/DCE 优化 → 图着色与线性扫描分配 →
// BURS 指令选择全链路。`demo_program` 供文档与基准复用同一输入。

///|
/// 端到端流水线各阶段产物。
pub(all) struct PipelineStages {
  liveness : LivenessResult
  dom : DomTree
  ssa : SsaProgram
  optimized : SsaProgram
  coloring : Map[Var, Location]
  linear_scan : Map[Var, Location]
  instrs : Array[TargetInstr]
} derive(Debug)

///|
/// 旗舰示例程序：带条件分支与菱形汇合的小程序。
///
///   entry: n = 3; cbr p then else
///   then:  x = n + 1; br join
///   else:  x = n - 1; br join
///   join:  y = x * 2; ret y
pub fn demo_program() -> Array[BasicBlock] {
  [
    {
      label: "entry",
      instrs: ["n = 3", "cbr p then else"],
      succs: ["then", "else"],
    },
    { label: "then", instrs: ["x = n + 1", "br join"], succs: ["join"] },
    { label: "else", instrs: ["x = n - 1", "br join"], succs: ["join"] },
    { label: "join", instrs: ["y = x * 2", "ret y"], succs: [] },
  ]
}

///|
/// 旗舰示例的带代价指令选择规则集（运算符特化 + 通用兜底，覆盖完整）。
pub fn demo_isel_rules() -> Array[CostRule] {
  [
    { pattern: "Const", template: "li", cost: 1 },
    { pattern: "VarRef", template: "mov", cost: 1 },
    { pattern: "BinOp:+", template: "add", cost: 1 },
    { pattern: "BinOp:*", template: "mul", cost: 2 },
    { pattern: "BinOp", template: "op", cost: 3 },
  ]
}

///|
/// 旗舰示例的 IR 表达式：`(n + 1) * 2`。
pub fn demo_ir() -> IrNode {
  IrNode::BinOp(
    "*",
    IrNode::BinOp("+", IrNode::VarRef({ id: 0 }), IrNode::Const(1)),
    IrNode::Const(2),
  )
}

///|
/// 执行完整后端流水线：活跃性 → 支配 → 最小 SSA → 数据流优化 → 图着色 / 线性
/// 扫描分配 → BURS 指令选择，各阶段产物聚合为 `PipelineStages`。
///
/// 寄存器数取干涉图节点数（≥ 最大度 + 1）以保证示例无溢出（R12.4）；图着色与
/// 线性扫描在该无溢出场景下结论一致（R12.5）。
pub fn demo_pipeline() -> PipelineStages {
  let blocks = demo_program()
  let liveness = analyze_liveness(blocks)
  let dom = build_dom_tree(blocks, entry="entry")
  let ssa = build_ssa_minimal(blocks, entry="entry")
  let optimized = run_to_fixpoint(ssa, [
    OptPass::Sccp,
    OptPass::Gvn,
    OptPass::ConstFold,
    OptPass::DeadCodeElim,
    OptPass::CopyProp,
  ])
  let g = build_interference_from_liveness(blocks, liveness)
  let intervals = build_intervals_from_liveness(blocks, liveness)
  let k = if g.nodes.length() > 0 { g.nodes.length() } else { 1 }
  let coloring = allocate_coloring_briggs(g, k, cost=spill_cost(g, intervals))
  let linear_scan = allocate_linear_scan(intervals, k)
  let instrs = select_burs(demo_isel_rules(), demo_ir())
  { liveness, dom, ssa, optimized, coloring, linear_scan, instrs }
}
