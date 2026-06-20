// codegen_infra.mbt —— 方向三 Codegen_Infra（R3）的核心类型与接口桩。
//
// 对应任务 11.1：定义 `InterferenceGraph`、`Location`（Reg/Spill）、
// `SsaProgram` 及配套辅助类型，并给出寄存器分配 / SSA / 指令选择的接口桩
// （`allocate_coloring` / `allocate_linear_scan` / `build_ssa` /
// `run_passes` / `select`）。类型签名严格遵循 design.md §「方向三：
// Codegen_Infra」。完整算法逻辑属任务 11.2，本文件仅建立类型与桩。

// ---------------------------------------------------------------------------
// 核心类型（Core Types）
// ---------------------------------------------------------------------------

///|
/// 变量（虚拟寄存器）标识。
///
/// 作为干涉图节点与分配结果 `Map[Var, Location]` 的键，故派生 `Eq` 与
/// `Hash`；派生 `Compare` 以支持确定性排序，`Show` 便于诊断输出。
pub(all) struct Var {
  id : Int
} derive(Eq, Hash, Compare, Show)

///|
/// 物理存储位置：分配到物理寄存器编号 `Reg`，或溢出到栈槽编号 `Spill`。
/// 严格对应 design.md：`pub enum Location { Reg(Int); Spill(Int) }`。
pub(all) enum Location {
  Reg(Int)
  Spill(Int)
} derive(Eq, Show)

///|
/// 干涉图（Interference Graph）。
///
/// `nodes` 为参与分配的变量集合，`edges` 为「同时活跃」而互相干涉的变量
/// 对（无向，约定以较小 `id` 在前由构造者保证）。设计要求其着色复用既有
/// 图着色 / `@directed` 干涉图资产（见 `interference_components`）。
pub(all) struct InterferenceGraph {
  nodes : Array[Var]
  edges : Array[(Var, Var)]
} derive(Show)

///|
/// 活跃区间（Live Interval）—— 线性扫描寄存器分配的输入单元。
pub(all) struct LiveInterval {
  variable : Var
  start : Int
  end : Int
} derive(Eq, Show)

///|
/// 基本块（Basic Block）—— SSA 构造的输入单元。
///
/// 骨架阶段以字符串数组占位表示块内指令与后继标签；任务 11.2 将以结构化
/// IR 节点替换，以支撑真实的支配关系计算与 φ 函数插入。
pub(all) struct BasicBlock {
  label : String
  instrs : Array[String]
  succs : Array[String]
} derive(Show)

///|
/// φ 函数（SSA 形式在控制流汇合点合并多个到达定义）。
pub(all) struct Phi {
  dest : Var
  args : Array[Var]
} derive(Show)

///|
/// SSA 程序（Static Single Assignment Program）。
///
/// 由基本块序列与插入的 φ 函数构成。任务 11.4 将以证明谓词
/// `ssa_single_assignment` 校验「每个变量恰好被定义一次」的单赋值不变量。
pub(all) struct SsaProgram {
  blocks : Array[BasicBlock]
  phis : Array[Phi]
} derive(Show)

///|
/// 优化 pass 标识。`run_passes` 按声明顺序执行并保持 SSA 不变量（任务 11.2）。
pub(all) enum Pass {
  ConstFold // 常量折叠
  DeadCodeElim // 死代码消除
  CopyProp // 复制传播
} derive(Eq, Show)

///|
/// 指令选择规则（Instruction Selection Rule）—— isel DSL 的一条模式→模板映射。
pub(all) struct IselRule {
  pattern : String
  template : String
} derive(Eq, Show)

///|
/// 中间表示节点（IR Node）—— `select` 的输入树。
pub(all) enum IrNode {
  Const(Int)
  VarRef(Var)
  BinOp(String, IrNode, IrNode)
} derive(Show)

///|
/// 目标指令（Target Instruction）—— `select` 的输出单元。
pub(all) struct TargetInstr {
  op : String
  operands : Array[String]
} derive(Eq, Show)

// ---------------------------------------------------------------------------
// 复用接缝（Reuse Seam）：依赖既有 @directed 干涉图资产
// ---------------------------------------------------------------------------

///|
/// 构造干涉图的对称邻接表。
///
/// 干涉边是无向的，这里把每条边 `(a, b)` 同时登记为 `a -> b` 与 `b -> a`，
/// 以便复用面向有向图的 `@directed` 算法。
fn build_adjacency(g : InterferenceGraph) -> Map[Var, Array[Var]] {
  let adj : Map[Var, Array[Var]] = Map([])
  for v in g.nodes {
    adj[v] = []
  }
  for e in g.edges {
    let (a, b) = e
    let la = adj.get(a).unwrap_or([])
    la.push(b)
    adj[a] = la
    let lb = adj.get(b).unwrap_or([])
    lb.push(a)
    adj[b] = lb
  }
  adj
}

///|
/// 复用 `@directed.tarjan_scc` 将干涉图按连通分量分组。
///
/// 设计要求 Codegen_Infra「复用既有图着色 / 干涉图资产」。仓库当前并无独立
/// 的「图着色」函数，故 11.1 阶段以 `@directed` 既有的可复用部分作为接缝：
/// 在对称邻接下，`tarjan_scc` 把相互可达的变量归入同一连通分量，从而把图
/// 着色分解为对各连通分量独立着色的子问题。`allocate_coloring` 的完整着色
/// 逻辑（k 着色 + 溢出）属任务 11.2，将构建于此分组之上。
pub fn interference_components(g : InterferenceGraph) -> Array[Array[Var]] {
  let adj = build_adjacency(g)
  @directed.tarjan_scc(g.nodes, fn(v) { adj.get(v).unwrap_or([]) })
}

// ---------------------------------------------------------------------------
// 寄存器分配（reg_alloc）：图着色 + 线性扫描
// ---------------------------------------------------------------------------

///|
/// 基于图着色的寄存器分配。
///
/// 设计签名：`allocate_coloring(g, k) -> Map[Var, Location]`。复用既有图着色
/// 接缝：先经 `interference_components`（底层 `@directed.tarjan_scc`）把干涉图
/// 分解为互不相连的连通分量，再对各分量独立做贪心 k 着色——按变量 id 升序
/// 处理，为当前变量选取 `[0, k)` 内未被「已着色邻居」占用的最小寄存器；若不
/// 存在可用寄存器则分配到递增的溢出槽 `Spill`。
///
/// 正确性不变量（Requirement 3.3）：任意两个相互干涉（相邻）的变量不会共享
/// 同一寄存器——因为为每个变量选色时显式排除了其邻居已占用的寄存器编号。
pub fn allocate_coloring(g : InterferenceGraph, k : Int) -> Map[Var, Location] {
  let result : Map[Var, Location] = Map([])
  let adj = build_adjacency(g)
  // 复用既有连通分量分组接缝，将着色分解为对各分量独立着色的子问题。
  let comps = interference_components(g)
  // 以分量最小变量 id 排序，保证三后端确定性输出。
  comps.sort_by(fn(a, b) {
    let ma = component_min_id(a)
    let mb = component_min_id(b)
    if ma < mb {
      -1
    } else if ma > mb {
      1
    } else {
      0
    }
  })
  let color_of : Map[Var, Int] = Map([])
  let mut next_spill = 0
  for comp in comps {
    let nodes = comp.copy()
    nodes.sort() // Var 派生 Compare，按 id 升序，保证确定性
    for v in nodes {
      // 收集已着色邻居占用的寄存器编号。
      let forbidden : Map[Int, Bool] = Map([])
      for u in adj.get(v).unwrap_or([]) {
        match color_of.get(u) {
          Some(c) => forbidden[c] = true
          None => ()
        }
      }
      // 选取 [0, k) 内未被邻居占用的最小寄存器；不存在则溢出。
      let mut chosen = -1
      for c in 0..<k {
        if !forbidden.contains(c) {
          chosen = c
          break
        }
      }
      if chosen >= 0 {
        result[v] = Location::Reg(chosen)
        color_of[v] = chosen
      } else {
        result[v] = Location::Spill(next_spill)
        next_spill = next_spill + 1
      }
    }
  }
  result
}

///|
/// 基于线性扫描的寄存器分配。
///
/// 设计签名：`allocate_linear_scan(intervals, k) -> Map[Var, Location]`。按活跃
/// 区间起点（再按终点、变量 id）升序处理：先回收终点早于当前区间起点的过期
/// 区间所占寄存器；若仍有空闲寄存器则分配之；否则在「与当前终点最远的活跃
/// 区间」与「当前区间」之间溢出终点更远者（经典 Poletto-Sarnak 策略）。
pub fn allocate_linear_scan(
  intervals : Array[LiveInterval],
  k : Int,
) -> Map[Var, Location] {
  let result : Map[Var, Location] = Map([])
  // 按起点（再按终点、变量 id）升序排序，保证确定性。
  let sorted = intervals.copy()
  sorted.sort_by(fn(a, b) {
    if a.start != b.start {
      a.start - b.start
    } else if a.end != b.end {
      a.end - b.end
    } else {
      a.variable.id - b.variable.id
    }
  })
  let mut next_spill = 0
  // 无可用寄存器：所有区间溢出。
  if k <= 0 {
    for iv in sorted {
      result[iv.variable] = Location::Spill(next_spill)
      next_spill = next_spill + 1
    }
    return result
  }
  // active：当前占用寄存器的活跃区间，按终点升序维护。
  let mut active : Array[LiveInterval] = []
  let reg_of : Map[Var, Int] = Map([])
  for current in sorted {
    // 过期回收：终点早于 current 起点的区间释放寄存器。
    active = expire_intervals(active, current.start)
    if active.length() >= k {
      // 寄存器耗尽：与终点最远的活跃区间比较，决定溢出谁。
      let spill = active[active.length() - 1]
      if spill.end > current.end {
        // 溢出 spill，把其寄存器让给 current。
        let r = reg_of.get(spill.variable).unwrap()
        result[current.variable] = Location::Reg(r)
        reg_of[current.variable] = r
        result[spill.variable] = Location::Spill(next_spill)
        next_spill = next_spill + 1
        active.remove(active.length() - 1) |> ignore
        insert_by_end(active, current)
      } else {
        // current 终点更远，直接溢出 current。
        result[current.variable] = Location::Spill(next_spill)
        next_spill = next_spill + 1
      }
    } else {
      let r = pick_free_register(active, reg_of, k)
      result[current.variable] = Location::Reg(r)
      reg_of[current.variable] = r
      insert_by_end(active, current)
    }
  }
  result
}

// ---------------------------------------------------------------------------
// SSA（ssa）：版本化构造 + φ 插入 + pass 流水线
// ---------------------------------------------------------------------------

///|
/// 构造 SSA 程序（含 φ 函数插入）。
///
/// 设计签名：`build_ssa(blocks) -> SsaProgram`。
///
/// 指令约定：块内指令为以空格分隔的记号串；当记号序列形如 `name = rhs...`
/// （第二个记号恰为 `"="`）时视为定义变量 `name`，其余指令（如 `"ret"`、
/// `"br L1"`）不定义变量。
///
/// 构造流程：
///   1) 预扫描——按块/指令顺序为每个定义分配全局唯一版本号，落实 SSA 单
///      赋值不变量（Requirement 3.5：每个变量恰有唯一一次静态定义）；
///   2) φ 插入——对存在 ≥2 个前驱的汇合块，为「在 ≥2 个块中被定义」的变量
///      插入 φ 函数（满足支配汇合点的合并语义，Requirement 3.4）；
///   3) 重命名——线性扫描把定义左值与右值使用重写为带版本记号 `name#ver`，
///      进入汇合块时以该块 φ 目标作为相关变量的当前版本。
pub fn build_ssa(blocks : Array[BasicBlock]) -> SsaProgram {
  let mut next_id = 0
  // ---- 预扫描：为每个定义分配版本号 ----
  // lhs_id[bi][ii] 为该指令所定义变量的版本号；非定义指令置为 -1。
  let lhs_id : Array[Array[Int]] = []
  let defs_by_name : Map[String, Array[Int]] = Map([]) // 变量名 -> 定义版本号列表
  let blocks_by_name : Map[String, Array[Int]] = Map([]) // 变量名 -> 定义所在块索引（去重）
  for bi, b in blocks {
    let ids_row : Array[Int] = []
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        let name = toks[0]
        let id = next_id
        next_id = next_id + 1
        ids_row.push(id)
        let lst = defs_by_name.get(name).unwrap_or([])
        lst.push(id)
        defs_by_name[name] = lst
        let bl = blocks_by_name.get(name).unwrap_or([])
        if !array_contains_int(bl, bi) {
          bl.push(bi)
        }
        blocks_by_name[name] = bl
      } else {
        ids_row.push(-1)
      }
    }
    lhs_id.push(ids_row)
  }

  // ---- 前驱计数 ----
  let pred_count : Map[String, Int] = Map([])
  for b in blocks {
    for s in b.succs {
      pred_count[s] = pred_count.get(s).unwrap_or(0) + 1
    }
  }

  // ---- φ 插入 ----
  let phis : Array[Phi] = []
  // phi_at[label] = [(name, destId)]，供重命名阶段在进入汇合块时更新当前版本。
  let phi_at : Map[String, Array[(String, Int)]] = Map([])
  for b in blocks {
    let pc = pred_count.get(b.label).unwrap_or(0)
    if pc >= 2 {
      // 收集在 ≥2 个块中被定义的变量名，排序以保证确定性。
      let names : Array[String] = []
      for kv in blocks_by_name {
        let (name, blks) = kv
        if blks.length() >= 2 {
          names.push(name)
        }
      }
      names.sort()
      for name in names {
        let versions = defs_by_name.get(name).unwrap_or([])
        if versions.length() == 0 {
          continue
        }
        // 每个前驱贡献一个到达版本作为 φ 实参。
        let args : Array[Var] = []
        let mut i = 0
        while i < pc {
          args.push({ id: versions[i % versions.length()] })
          i = i + 1
        }
        let dest_id = next_id
        next_id = next_id + 1
        phis.push({ dest: { id: dest_id }, args })
        let row = phi_at.get(b.label).unwrap_or([])
        row.push((name, dest_id))
        phi_at[b.label] = row
      }
    }
  }

  // ---- 重命名：定义左值 + 右值使用 → 带版本记号 ----
  let current : Map[String, Int] = Map([]) // 变量名 -> 当前版本号
  let renamed_blocks : Array[BasicBlock] = []
  for bi, b in blocks {
    // 进入汇合块：φ 目标成为相关变量的当前版本。
    match phi_at.get(b.label) {
      Some(row) =>
        for pair in row {
          let (name, dest_id) = pair
          current[name] = dest_id
        }
      None => ()
    }
    let new_instrs : Array[String] = []
    for ii, instr in b.instrs {
      let toks = tokenize(instr)
      let id = lhs_id[bi][ii]
      if id >= 0 {
        // 定义指令：先以当前版本重写右值使用，再为左值赋新版本。
        let out : Array[String] = []
        out.push(versioned(toks[0], id))
        out.push("=")
        let mut j = 2
        while j < toks.length() {
          out.push(rename_use(toks[j], current))
          j = j + 1
        }
        current[toks[0]] = id
        new_instrs.push(join_tokens(out))
      } else {
        // 非定义指令：仅重写其中的变量使用。
        let out : Array[String] = []
        for t in toks {
          out.push(rename_use(t, current))
        }
        new_instrs.push(join_tokens(out))
      }
    }
    renamed_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  { blocks: renamed_blocks, phis }
}

///|
/// 按声明顺序执行优化 pass。
///
/// 设计签名：`run_passes(p, passes) -> SsaProgram`。依次对程序施加各 pass：
/// 常量折叠（`ConstFold`）、死代码消除（`DeadCodeElim`）、复制传播
/// （`CopyProp`）。各 pass 仅删除定义或改写右值，绝不引入重复定义，故每个
/// pass 后 SSA 单赋值不变量恒成立（Requirement 3.6）。
pub fn run_passes(p : SsaProgram, passes : Array[Pass]) -> SsaProgram {
  let mut cur = p
  for pass in passes {
    cur = match pass {
      ConstFold => pass_const_fold(cur)
      DeadCodeElim => pass_dead_code_elim(cur)
      CopyProp => pass_copy_prop(cur)
    }
  }
  cur
}

// ---------------------------------------------------------------------------
// 指令选择（isel）：声明式规则覆盖 IR 树
// ---------------------------------------------------------------------------

///|
/// 指令选择 DSL。
///
/// 设计签名：`select(rules, ir) -> Array[TargetInstr]`。以声明式规则
/// （`IselRule { pattern, template }`）把 IR 树覆盖为目标指令序列：后序遍历
/// 先为子树生成指令，再为当前节点按模式查表选择目标操作码（`template`），
/// 并把子树结果作为操作数串接（Requirement 3.7）。
///
/// 模式约定：`"Const"` 匹配常量、`"VarRef"` 匹配变量引用、`"BinOp"` 匹配
/// 任意二元运算，`"BinOp:<op>"` 可针对具体运算符（如 `"BinOp:*"`）特化并
/// 优先于通用 `"BinOp"`。每个产出指令的首操作数为目标虚拟寄存器 `t{n}`。
/// 未提供匹配规则时回退：常量用 `li`、变量引用直接以 `v{id}` 作为操作数且
/// 不产指令、二元运算回退为运算符本身作为操作码。
pub fn select(rules : Array[IselRule], ir : IrNode) -> Array[TargetInstr] {
  let out : Array[TargetInstr] = []
  let counter = [0] // 以单元素数组充当可变虚拟寄存器计数器
  select_node(rules, ir, out, counter) |> ignore
  out
}

// ---------------------------------------------------------------------------
// 私有辅助（helpers）：寄存器分配
// ---------------------------------------------------------------------------

///|
/// 连通分量内的最小变量 id（用于分量排序，保证确定性输出）。
fn component_min_id(comp : Array[Var]) -> Int {
  let mut m = 2147483647
  for v in comp {
    if v.id < m {
      m = v.id
    }
  }
  m
}

///|
/// 回收过期活跃区间：保留终点不早于 `point` 的区间，返回新的有序数组
/// （仍按终点升序，因 `filter` 保持原相对顺序）。
fn expire_intervals(
  active : Array[LiveInterval],
  point : Int,
) -> Array[LiveInterval] {
  let kept : Array[LiveInterval] = []
  for iv in active {
    if iv.end >= point {
      kept.push(iv)
    }
  }
  kept
}

///|
/// 将区间按终点升序（终点相同再按变量 id）插入活跃集。
fn insert_by_end(active : Array[LiveInterval], iv : LiveInterval) -> Unit {
  active.push(iv)
  active.sort_by(fn(a, b) {
    if a.end != b.end {
      a.end - b.end
    } else {
      a.variable.id - b.variable.id
    }
  })
}

///|
/// 在 `[0, k)` 中选取一个未被活跃集占用的最小寄存器编号。
/// 调用点已保证 `active.length() < k`，故必有空闲寄存器。
fn pick_free_register(
  active : Array[LiveInterval],
  reg_of : Map[Var, Int],
  k : Int,
) -> Int {
  let used : Map[Int, Bool] = Map([])
  for iv in active {
    match reg_of.get(iv.variable) {
      Some(r) => used[r] = true
      None => ()
    }
  }
  let mut r = 0
  while r < k {
    if !used.contains(r) {
      return r
    }
    r = r + 1
  }
  0
}

// ---------------------------------------------------------------------------
// 私有辅助（helpers）：指令记号解析与版本化
// ---------------------------------------------------------------------------

///|
/// 以空格切分指令为记号序列（忽略连续空格产生的空记号）。
fn tokenize(s : String) -> Array[String] {
  let toks : Array[String] = []
  let cur = StringBuilder::new()
  let mut has = false
  for c in s {
    if c == ' ' {
      if has {
        toks.push(cur.to_string())
        cur.reset()
        has = false
      }
    } else {
      cur.write_char(c)
      has = true
    }
  }
  if has {
    toks.push(cur.to_string())
  }
  toks
}

///|
/// 以单空格拼接记号序列为指令字符串。
fn join_tokens(toks : Array[String]) -> String {
  let sb = StringBuilder::new()
  for i, t in toks {
    if i > 0 {
      sb.write_char(' ')
    }
    sb.write_string(t)
  }
  sb.to_string()
}

///|
/// 生成带版本号的变量记号，形如 `name#ver`。
fn versioned(name : String, id : Int) -> String {
  name + "#" + id.to_string()
}

///|
/// 重写一个右值记号：若其为「当前有版本的变量名」则替换为带版本记号，
/// 否则（运算符、字面量、未定义/前向引用）原样返回。
fn rename_use(tok : String, current : Map[String, Int]) -> String {
  match current.get(tok) {
    Some(id) => versioned(tok, id)
    None => tok
  }
}

///|
/// 数组是否包含某整数。
fn array_contains_int(arr : Array[Int], x : Int) -> Bool {
  for v in arr {
    if v == x {
      return true
    }
  }
  false
}

///|
/// 从带版本记号 `name#ver` 中解析出版本号；无 `#` 或非整数后缀时返回 `None`。
fn version_id(tok : String) -> Int? {
  let cs = tok.iter().to_array()
  let mut hash = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '#' {
      hash = i
    }
    i = i + 1
  }
  if hash < 0 || hash + 1 >= cs.length() {
    return None
  }
  let mut n = 0
  let mut j = hash + 1
  while j < cs.length() {
    let c = cs[j]
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    j = j + 1
  }
  Some(n)
}

///|
/// 解析整型字面量记号（支持可选前导负号）；非整数返回 `None`。
fn parse_int(tok : String) -> Int? {
  let cs = tok.iter().to_array()
  if cs.length() == 0 {
    return None
  }
  let mut start = 0
  let mut neg = false
  if cs[0] == '-' {
    neg = true
    start = 1
    if cs.length() == 1 {
      return None
    }
  }
  let mut n = 0
  let mut i = start
  while i < cs.length() {
    let c = cs[i]
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    i = i + 1
  }
  Some(if neg { -n } else { n })
}

// ---------------------------------------------------------------------------
// 私有辅助（helpers）：优化 pass
// ---------------------------------------------------------------------------

///|
/// 常量折叠：把形如 `lhs = a op b`（a、b 为整型字面量，op ∈ {+,-,*}）的
/// 指令折叠为 `lhs = <结果>`。
fn pass_const_fold(p : SsaProgram) -> SsaProgram {
  let new_blocks : Array[BasicBlock] = []
  for b in p.blocks {
    let new_instrs : Array[String] = []
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() == 5 && toks[1] == "=" {
        match (parse_int(toks[2]), parse_int(toks[4])) {
          (Some(x), Some(y)) =>
            match fold_op(toks[3], x, y) {
              Some(r) =>
                new_instrs.push(join_tokens([toks[0], "=", r.to_string()]))
              None => new_instrs.push(instr)
            }
          _ => new_instrs.push(instr)
        }
      } else {
        new_instrs.push(instr)
      }
    }
    new_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  { blocks: new_blocks, phis: p.phis }
}

///|
/// 折叠单个二元整数运算；不支持的运算符返回 `None`。
fn fold_op(op : String, x : Int, y : Int) -> Int? {
  if op == "+" {
    Some(x + y)
  } else if op == "-" {
    Some(x - y)
  } else if op == "*" {
    Some(x * y)
  } else {
    None
  }
}

///|
/// 死代码消除：删除其定义版本从未被任何右值使用、且不作为任何 φ 实参的
/// 块内定义指令。仅移除定义不会引入重复定义，故保持 SSA 单赋值不变量。
fn pass_dead_code_elim(p : SsaProgram) -> SsaProgram {
  // 收集被使用的版本号。
  let used : Map[Int, Bool] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      // 定义指令右值从记号 2 起，非定义指令全部记号皆为使用。
      let start = if toks.length() >= 2 && toks[1] == "=" { 2 } else { 0 }
      let mut j = start
      while j < toks.length() {
        match version_id(toks[j]) {
          Some(vid) => used[vid] = true
          None => ()
        }
        j = j + 1
      }
    }
  }
  for phi in p.phis {
    for a in phi.args {
      used[a.id] = true
    }
  }
  let new_blocks : Array[BasicBlock] = []
  for b in p.blocks {
    let new_instrs : Array[String] = []
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        match version_id(toks[0]) {
          Some(vid) => if used.contains(vid) { new_instrs.push(instr) }
          None => new_instrs.push(instr)
        }
      } else {
        new_instrs.push(instr)
      }
    }
    new_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  { blocks: new_blocks, phis: p.phis }
}

///|
/// 复制传播：对复制指令 `lhs = rhs`（右值恰为单个带版本变量记号），把后续
/// 对 `lhs` 版本的使用（含 φ 实参）替换为 `rhs` 版本，并删除该复制指令。
fn pass_copy_prop(p : SsaProgram) -> SsaProgram {
  // 收集替换映射：destVer -> srcToken。
  let replace : Map[Int, String] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() == 3 && toks[1] == "=" {
        match (version_id(toks[0]), version_id(toks[2])) {
          (Some(dst), Some(_)) => replace[dst] = toks[2]
          _ => ()
        }
      }
    }
  }
  // 重写块指令并删除复制定义。
  let new_blocks : Array[BasicBlock] = []
  for b in p.blocks {
    let new_instrs : Array[String] = []
    for instr in b.instrs {
      let toks = tokenize(instr)
      let is_copy = toks.length() == 3 &&
        toks[1] == "=" &&
        not_none(version_id(toks[0])) &&
        not_none(version_id(toks[2]))
      if is_copy {
        continue
      }
      let out : Array[String] = []
      let start = if toks.length() >= 2 && toks[1] == "=" {
        out.push(toks[0])
        out.push("=")
        2
      } else {
        0
      }
      let mut j = start
      while j < toks.length() {
        out.push(resolve_replace(toks[j], replace))
        j = j + 1
      }
      new_instrs.push(join_tokens(out))
    }
    new_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  // 重写 φ 实参。
  let new_phis : Array[Phi] = []
  for phi in p.phis {
    let new_args : Array[Var] = []
    for a in phi.args {
      match replace.get(a.id) {
        Some(tok) =>
          match version_id(tok) {
            Some(v) => new_args.push({ id: v })
            None => new_args.push(a)
          }
        None => new_args.push(a)
      }
    }
    new_phis.push({ dest: phi.dest, args: new_args })
  }
  { blocks: new_blocks, phis: new_phis }
}

///|
/// 若记号为被替换的版本变量，则返回其替换记号，否则原样返回。
fn resolve_replace(tok : String, replace : Map[Int, String]) -> String {
  match version_id(tok) {
    Some(v) =>
      match replace.get(v) {
        Some(rep) => rep
        None => tok
      }
    None => tok
  }
}

///|
/// `Option[Int]` 是否为 `Some`。
fn not_none(o : Int?) -> Bool {
  match o {
    Some(_) => true
    None => false
  }
}

// ---------------------------------------------------------------------------
// 私有辅助（helpers）：指令选择
// ---------------------------------------------------------------------------

///|
/// 后序遍历 IR 树生成目标指令，返回当前子树结果所在的操作数记号。
/// `counter` 为单元素数组充当的可变虚拟寄存器计数器。
fn select_node(
  rules : Array[IselRule],
  ir : IrNode,
  out : Array[TargetInstr],
  counter : Array[Int],
) -> String {
  match ir {
    Const(n) => {
      let dst = fresh_temp(counter)
      let op = lookup_rule(rules, "Const").unwrap_or("li")
      out.push({ op, operands: [dst, n.to_string()] })
      dst
    }
    VarRef(v) => {
      let name = "v" + v.id.to_string()
      match lookup_rule(rules, "VarRef") {
        Some(tmpl) => {
          let dst = fresh_temp(counter)
          out.push({ op: tmpl, operands: [dst, name] })
          dst
        }
        None => name
      }
    }
    BinOp(op, l, r) => {
      let lo = select_node(rules, l, out, counter)
      let ro = select_node(rules, r, out, counter)
      let dst = fresh_temp(counter)
      let tmpl = match lookup_rule(rules, "BinOp:" + op) {
        Some(t) => t
        None => lookup_rule(rules, "BinOp").unwrap_or(op)
      }
      out.push({ op: tmpl, operands: [dst, lo, ro] })
      dst
    }
  }
}

///|
/// 生成下一个虚拟寄存器记号 `t{n}` 并自增计数器。
fn fresh_temp(counter : Array[Int]) -> String {
  let id = counter[0]
  counter[0] = id + 1
  "t" + id.to_string()
}

///|
/// 查找首个 `pattern` 匹配的规则模板。
fn lookup_rule(rules : Array[IselRule], pattern : String) -> String? {
  for r in rules {
    if r.pattern == pattern {
      return Some(r.template)
    }
  }
  None
}
