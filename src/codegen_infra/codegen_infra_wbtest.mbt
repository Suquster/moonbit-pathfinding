// codegen_infra_test.mbt —— 方向三 Codegen_Infra（R3）的单元测试。
//
// 对应任务 11.2：覆盖寄存器分配（图着色 + 线性扫描）、SSA 构造（含 φ 插入
// 与单赋值不变量）、pass 流水线（常量折叠 / 死代码消除 / 复制传播）与指令
// 选择 DSL 的核心功能与重要边界。Property 7/8 的属性测试属任务 11.3 / 11.4。

// ---------------------------------------------------------------------------
// 测试辅助（test helpers）
// ---------------------------------------------------------------------------

///|
/// 校验分配方案满足干涉不变量：任意一条干涉边两端若均着色为寄存器，则编号
/// 互不相同（核心正确性不变量，Requirement 3.3）。
fn all_edges_distinct(
  g : InterferenceGraph,
  alloc : Map[Var, Location],
) -> Bool {
  for e in g.edges {
    let (a, b) = e
    match (alloc.get(a), alloc.get(b)) {
      (Some(Reg(x)), Some(Reg(y))) => if x == y { return false }
      _ => ()
    }
  }
  true
}

///|
/// 统计分配方案中溢出到栈槽的变量数量。
fn count_spills(alloc : Map[Var, Location]) -> Int {
  let mut n = 0
  for kv in alloc {
    let (_, loc) = kv
    match loc {
      Spill(_) => n = n + 1
      Reg(_) => ()
    }
  }
  n
}

///|
/// 数组元素是否两两互不相同。
fn all_distinct(xs : Array[Int]) -> Bool {
  let seen : Map[Int, Bool] = Map([])
  for x in xs {
    if seen.contains(x) {
      return false
    }
    seen[x] = true
  }
  true
}

///|
/// 收集 SSA 程序中所有「定义」的版本号（块内定义左值 + φ 目标）。
///
/// 用于单赋值不变量校验：若返回的版本号两两互不相同，则程序满足 SSA 单赋值
/// 不变量（每个变量恰有唯一一次静态定义）。借助白盒测试访问包内私有的
/// `tokenize` / `version_id` 辅助。
fn ssa_definition_ids(p : SsaProgram) -> Array[Int] {
  let ids : Array[Int] = []
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        match version_id(toks[0]) {
          Some(v) => ids.push(v)
          None => ()
        }
      }
    }
  }
  for phi in p.phis {
    ids.push(phi.dest.id)
  }
  ids
}

// ---------------------------------------------------------------------------
// 核心类型
// ---------------------------------------------------------------------------

///|
/// `Location` 枚举可构造 Reg / Spill 两种位置且可相等比较。
test "Location 枚举 Reg/Spill 可构造并比较" {
  inspect(Location::Reg(3) == Location::Reg(3), content="true")
  inspect(Location::Reg(0) == Location::Spill(0), content="false")
}

// ---------------------------------------------------------------------------
// 寄存器分配：图着色
// ---------------------------------------------------------------------------

///|
/// K3 完全干涉图在 k=3 时三个变量均着色为寄存器且两两不同。
test "allocate_coloring K3 在 k=3 时全部着色且相邻不同" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [
      ({ id: 0 }, { id: 1 }),
      ({ id: 1 }, { id: 2 }),
      ({ id: 0 }, { id: 2 }),
    ],
  }
  let alloc = allocate_coloring(g, 3)
  inspect(alloc.length(), content="3")
  inspect(count_spills(alloc), content="0")
  assert_true(all_edges_distinct(g, alloc))
}

///|
/// K3 在寄存器不足（k=2）时无法三着色，至少溢出一个变量；干涉不变量仍成立。
test "allocate_coloring K3 在 k=2 时溢出且不变量保持" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [
      ({ id: 0 }, { id: 1 }),
      ({ id: 1 }, { id: 2 }),
      ({ id: 0 }, { id: 2 }),
    ],
  }
  let alloc = allocate_coloring(g, 2)
  assert_true(count_spills(alloc) >= 1)
  assert_true(all_edges_distinct(g, alloc))
}

///|
/// 相邻变量在 k=1 时必有一个溢出（无法用单寄存器为相邻变量同时着色）。
test "allocate_coloring 相邻变量 k=1 时其一溢出" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }],
    edges: [({ id: 0 }, { id: 1 })],
  }
  let alloc = allocate_coloring(g, 1)
  @debug.debug_inspect(alloc.get({ id: 0 }).unwrap(), content="Reg(0)")
  @debug.debug_inspect(alloc.get({ id: 1 }).unwrap(), content="Spill(0)")
}

// ---------------------------------------------------------------------------
// 寄存器分配：线性扫描
// ---------------------------------------------------------------------------

///|
/// 非重叠区间复用寄存器：A[0,2]、B[1,3] 重叠占两个寄存器，C[4,6] 复用其一。
test "allocate_linear_scan 非重叠区间复用寄存器" {
  let intervals = [
    LiveInterval::{ variable: { id: 0 }, start: 0, end: 2 },
    LiveInterval::{ variable: { id: 1 }, start: 1, end: 3 },
    LiveInterval::{ variable: { id: 2 }, start: 4, end: 6 },
  ]
  let alloc = allocate_linear_scan(intervals, 2)
  inspect(count_spills(alloc), content="0")
  @debug.debug_inspect(alloc.get({ id: 0 }).unwrap(), content="Reg(0)")
  @debug.debug_inspect(alloc.get({ id: 1 }).unwrap(), content="Reg(1)")
  @debug.debug_inspect(alloc.get({ id: 2 }).unwrap(), content="Reg(0)")
}

///|
/// 寄存器耗尽（k=1）时重叠区间溢出：A 保留寄存器，B 溢出。
test "allocate_linear_scan 寄存器耗尽时重叠区间溢出" {
  let intervals = [
    LiveInterval::{ variable: { id: 0 }, start: 0, end: 2 },
    LiveInterval::{ variable: { id: 1 }, start: 1, end: 3 },
  ]
  let alloc = allocate_linear_scan(intervals, 1)
  @debug.debug_inspect(alloc.get({ id: 0 }).unwrap(), content="Reg(0)")
  @debug.debug_inspect(alloc.get({ id: 1 }).unwrap(), content="Spill(0)")
}

// ---------------------------------------------------------------------------
// SSA 构造与 φ 插入
// ---------------------------------------------------------------------------

///|
/// 菱形控制流：变量 x 在 then/else 两块定义，汇合块 join 处插入一个 φ；
/// φ 实参数等于汇合块前驱数（2）；整体满足 SSA 单赋值不变量。
test "build_ssa 在菱形汇合点插入 φ 并保持单赋值" {
  let p = build_ssa([
    BasicBlock::{ label: "entry", instrs: [], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ])
  inspect(p.phis.length(), content="1")
  inspect(p.phis[0].args.length(), content="2")
  // then 块定义左值被版本化。
  inspect(p.blocks[1].instrs[0], content="x#0 = 1")
  assert_true(all_distinct(ssa_definition_ids(p)))
}

///|
/// 直线代码无汇合点：不插入 φ；定义左值与右值使用均被版本化。
test "build_ssa 直线代码不插入 φ 且版本化使用" {
  let p = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1", "y = x + 2"], succs: [] },
  ])
  inspect(p.phis.length(), content="0")
  inspect(p.blocks[0].instrs[0], content="x#0 = 1")
  inspect(p.blocks[0].instrs[1], content="y#1 = x#0 + 2")
  assert_true(all_distinct(ssa_definition_ids(p)))
}

// ---------------------------------------------------------------------------
// pass 流水线
// ---------------------------------------------------------------------------

///|
/// 常量折叠：`x = 1 + 2` 折叠为 `x = 3`。
test "run_passes 常量折叠" {
  let base = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1 + 2"], succs: [] },
  ])
  let folded = run_passes(base, [ConstFold])
  inspect(folded.blocks[0].instrs[0], content="x#0 = 3")
}

///|
/// 死代码消除：未被使用的定义 `x = 1` 被删除，被 ret 使用的 `y = 2` 保留。
test "run_passes 死代码消除删除未使用定义" {
  let base = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1", "y = 2", "ret y"], succs: [] },
  ])
  let dce = run_passes(base, [DeadCodeElim])
  inspect(dce.blocks[0].instrs.length(), content="2")
  inspect(dce.blocks[0].instrs[0], content="y#1 = 2")
  inspect(dce.blocks[0].instrs[1], content="ret y#1")
  assert_true(all_distinct(ssa_definition_ids(dce)))
}

///|
/// 复制传播：`y = x` 的使用被替换为 x 的版本，复制指令删除。
test "run_passes 复制传播替换并删除复制" {
  let base = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1", "y = x", "ret y"], succs: [] },
  ])
  let cp = run_passes(base, [CopyProp])
  // 复制 `y#1 = x#0` 被删除，ret 使用替换为 x#0。
  inspect(cp.blocks[0].instrs.length(), content="2")
  inspect(cp.blocks[0].instrs[1], content="ret x#0")
}

///|
/// 多 pass 按声明顺序执行后仍保持 SSA 单赋值不变量。
test "run_passes 多 pass 顺序执行保持单赋值不变量" {
  let base = build_ssa([
    BasicBlock::{
      label: "b0",
      instrs: ["x = 1 + 2", "y = 5", "ret x"],
      succs: [],
    },
  ])
  let out = run_passes(base, [ConstFold, DeadCodeElim])
  assert_true(all_distinct(ssa_definition_ids(out)))
}

// ---------------------------------------------------------------------------
// 指令选择 DSL
// ---------------------------------------------------------------------------

///|
/// 二元运算的指令选择：后序产出两条 Const 指令与一条 BinOp 指令。
test "select 覆盖二元运算树" {
  let rules = [
    IselRule::{ pattern: "Const", template: "li" },
    IselRule::{ pattern: "BinOp", template: "add" },
  ]
  let instrs = select(
    rules,
    IrNode::BinOp("+", IrNode::Const(1), IrNode::Const(2)),
  )
  inspect(instrs.length(), content="3")
  inspect(instrs[0].op, content="li")
  inspect(instrs[2].op, content="add")
  inspect(instrs[2].operands.length(), content="3")
  inspect(instrs[2].operands[0], content="t2")
  inspect(instrs[2].operands[1], content="t0")
  inspect(instrs[2].operands[2], content="t1")
}

///|
/// 运算符特化模式 `BinOp:*` 优先于通用 `BinOp`。
test "select 运算符特化模式优先" {
  let rules = [
    IselRule::{ pattern: "Const", template: "li" },
    IselRule::{ pattern: "BinOp:*", template: "mul" },
    IselRule::{ pattern: "BinOp", template: "add" },
  ]
  let instrs = select(
    rules,
    IrNode::BinOp("*", IrNode::Const(3), IrNode::Const(4)),
  )
  inspect(instrs[2].op, content="mul")
}

///|
/// 变量引用无匹配规则时不产指令，直接以 `v{id}` 作为操作数。
test "select 变量引用无规则时作为操作数" {
  let rules = [
    IselRule::{ pattern: "Const", template: "li" },
    IselRule::{ pattern: "BinOp", template: "add" },
  ]
  let instrs = select(
    rules,
    IrNode::BinOp("+", IrNode::VarRef({ id: 5 }), IrNode::Const(7)),
  )
  inspect(instrs.length(), content="2")
  inspect(instrs[1].operands[1], content="v5")
}

// ---------------------------------------------------------------------------
// 复用接缝：interference_components
// ---------------------------------------------------------------------------

///|
/// 复用接缝 `interference_components`：两个互不干涉的变量应分到两个连通分量。
test "interference_components 无边时每个变量自成一个分量" {
  let g = InterferenceGraph::{ nodes: [{ id: 0 }, { id: 1 }], edges: [] }
  inspect(interference_components(g).length(), content="2")
}

///|
/// 复用接缝 `interference_components`：相互干涉的两个变量归入同一连通分量。
test "interference_components 有边时干涉变量归入同一分量" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }],
    edges: [({ id: 0 }, { id: 1 })],
  }
  inspect(interference_components(g).length(), content="1")
}
