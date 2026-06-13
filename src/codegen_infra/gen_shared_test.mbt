// gen_shared_test.mbt —— 旗舰深化属性测试的共享生成器与图工具（黑盒测试单元）。
//
// 本文件聚合「带唯一入口的随机控制流图」「随机 IR 树 + 覆盖完整的带代价规则集」
// 等生成器，供 prop_*_test.mbt（黑盒）复用，统一以 @infra_pbt 的 `Gen`/`Rng`
// 驱动，三后端确定性一致。白盒（*_wbtest.mbt）单元另有独立生成器（见对应文件）。
//
// 设计取舍：
//   * CFG 仅含前向边（block i → block j 要求 i < j），从而为 DAG——保证支配关系
//     与 entry-rooted 路径良定义、路径枚举有限、属性参考实现可计算；
//   * 出度上界为 2，使条件块 `cbr` 的两个目标恰为其两个后继；
//   * 条件统一取外部输入变量 `p`（永不被定义 → SCCP 视为 Bottom，不触发常量
//     条件剪枝），使语义保持类属性沿任意 entry-rooted 路径安全。

///|
/// 变量名池（小集合，提高跨块重定义 → 触发 φ 的概率）。
let cfg_var_pool : Array[String] = ["a", "b", "c", "x"]

///|
/// 二元运算符池（与 `fold_op` 可折叠运算符一致）。
let cfg_op_pool : Array[String] = ["+", "-", "*"]

///|
/// 数组是否包含某整数（测试本地工具）。
fn t_contains_int(arr : Array[Int], x : Int) -> Bool {
  for v in arr {
    if v == x {
      return true
    }
  }
  false
}

///|
/// 数组是否包含某字符串（测试本地工具）。
fn t_contains_str(arr : Array[String], x : String) -> Bool {
  for v in arr {
    if v == x {
      return true
    }
  }
  false
}

///|
/// 生成一个块的指令序列：0..2 条定义 + 一个终结指令（依后继数为 ret/br/cbr）。
fn gen_block_instrs(
  rng : @infra_pbt.Rng,
  succ_labels : Array[String],
) -> Array[String] {
  let instrs : Array[String] = []
  let ndef = rng.next_below(3)
  let mut d = 0
  while d < ndef {
    let lhs = cfg_var_pool[rng.next_below(cfg_var_pool.length())]
    if rng.next_bool() {
      instrs.push(lhs + " = " + rng.next_range(0, 9).to_string())
    } else {
      let a = cfg_var_pool[rng.next_below(cfg_var_pool.length())]
      let b = cfg_var_pool[rng.next_below(cfg_var_pool.length())]
      let op = cfg_op_pool[rng.next_below(cfg_op_pool.length())]
      instrs.push(lhs + " = " + a + " " + op + " " + b)
    }
    d = d + 1
  }
  if succ_labels.length() == 0 {
    instrs.push("ret " + cfg_var_pool[rng.next_below(cfg_var_pool.length())])
  } else if succ_labels.length() == 1 {
    instrs.push("br " + succ_labels[0])
  } else {
    instrs.push("cbr p " + succ_labels[0] + " " + succ_labels[1])
  }
  instrs
}

///|
/// 随机控制流图生成器：唯一入口 `b0`、前向边 DAG、出度 ≤ 2、含汇合块。
fn gen_cfg() -> @infra_pbt.Gen[Array[BasicBlock]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(3, 7)
    let succ : Array[Array[Int]] = []
    for _ in 0..<n {
      succ.push([])
    }
    // 生成树：每个 i≥1 至少有一个前驱 j<i（保证可达），出度 ≤ 2。
    for i in 1..<n {
      let start = rng.next_below(i)
      let mut placed = false
      for off in 0..<i {
        let j = (start + off) % i
        if succ[j].length() < 2 && not(t_contains_int(succ[j], i)) {
          succ[j].push(i)
          placed = true
          break
        }
      }
      ignore(placed)
    }
    // 额外前向边制造汇合点（多前驱）。
    let extra = rng.next_below(n)
    let mut e = 0
    while e < extra {
      let a = rng.next_below(n - 1)
      let b = rng.next_range(a + 1, n - 1)
      if succ[a].length() < 2 && not(t_contains_int(succ[a], b)) {
        succ[a].push(b)
      }
      e = e + 1
    }
    let blocks : Array[BasicBlock] = []
    for i in 0..<n {
      succ[i].sort()
      let succ_labels : Array[String] = []
      for t in succ[i] {
        succ_labels.push("b" + t.to_string())
      }
      let instrs = gen_block_instrs(rng, succ_labels)
      blocks.push({ label: "b" + i.to_string(), instrs, succs: succ_labels })
    }
    blocks
  })
}

// ---------------------------------------------------------------------------
// 图工具（黑盒参考实现，用于支配 / 支配边界属性的独立校验）
// ---------------------------------------------------------------------------

///|
/// 计算块标签 → 后继的映射。
fn succ_map(blocks : Array[BasicBlock]) -> Map[String, Array[String]] {
  let m : Map[String, Array[String]] = Map([])
  for b in blocks {
    m[b.label] = b.succs
  }
  m
}

///|
/// 在「移除 blocked 节点」后，from 是否能到达 to（BFS）。
/// `blocked == ""` 表示不移除任何节点。
fn reachable_avoiding(
  blocks : Array[BasicBlock],
  from : String,
  to : String,
  blocked : String,
) -> Bool {
  if from == blocked {
    return false
  }
  let sm = succ_map(blocks)
  let seen : Map[String, Bool] = Map([])
  let queue : Array[String] = [from]
  seen[from] = true
  let mut qi = 0
  while qi < queue.length() {
    let cur = queue[qi]
    qi = qi + 1
    if cur == to {
      return true
    }
    for s in sm.get(cur).unwrap_or([]) {
      if s != blocked && not(seen.contains(s)) {
        seen[s] = true
        queue.push(s)
      }
    }
  }
  // to 可能等于 from：上面循环已在 cur==to 时返回；这里再判一次起点。
  from == to
}

///|
/// 参考支配判定：`d` 支配 `n` ⟺ 移除 `d` 后入口无法到达 `n`（d≠entry,d≠n）。
fn reference_dominates(
  blocks : Array[BasicBlock],
  entry : String,
  d : String,
  n : String,
) -> Bool {
  if d == n {
    return true
  }
  if d == entry {
    return true
  }
  not(reachable_avoiding(blocks, entry, n, d))
}

///|
/// 计算某块的前驱标签集（测试本地，按块序）。
fn preds_of(blocks : Array[BasicBlock], label : String) -> Array[String] {
  let out : Array[String] = []
  for b in blocks {
    for s in b.succs {
      if s == label {
        out.push(b.label)
      }
    }
  }
  out
}

// ---------------------------------------------------------------------------
// 随机 IR 树 + 覆盖完整的带代价规则集（指令选择属性）
// ---------------------------------------------------------------------------

///|
/// 递归生成随机 IR 树（深度受限）。
fn gen_ir_node(rng : @infra_pbt.Rng, depth : Int) -> IrNode {
  if depth <= 0 || rng.next_below(3) == 0 {
    if rng.next_bool() {
      IrNode::Const(rng.next_range(0, 9))
    } else {
      IrNode::VarRef({ id: rng.next_below(4) })
    }
  } else {
    let op = cfg_op_pool[rng.next_below(cfg_op_pool.length())]
    IrNode::BinOp(op, gen_ir_node(rng, depth - 1), gen_ir_node(rng, depth - 1))
  }
}

///|
/// 随机 IR 树生成器（深度上界 `max_depth`）。
fn gen_ir(max_depth : Int) -> @infra_pbt.Gen[IrNode] {
  @infra_pbt.Gen::new(fn(rng) { gen_ir_node(rng, max_depth) })
}

///|
/// 生成覆盖完整的带代价规则集：恒含 `Const`/`VarRef`/`BinOp` 通用规则，
/// 随机追加 `BinOp:<op>` 运算符特化规则（代价随机，≥1）。
fn gen_cost_rules(rng : @infra_pbt.Rng) -> Array[CostRule] {
  let rules : Array[CostRule] = [
    { pattern: "Const", template: "li", cost: rng.next_range(1, 5) },
    { pattern: "VarRef", template: "ld", cost: rng.next_range(1, 5) },
    { pattern: "BinOp", template: "op", cost: rng.next_range(2, 9) },
  ]
  for op in cfg_op_pool {
    if rng.next_bool() {
      rules.push({
        pattern: "BinOp:" + op,
        template: "s" + op,
        cost: rng.next_range(1, 9),
      })
    }
  }
  rules
}

///|
/// 生成器：随机 IR 树 + 覆盖完整带代价规则集。
fn gen_ir_and_rules(max_depth : Int) -> @infra_pbt.Gen[(IrNode, Array[CostRule])] {
  @infra_pbt.Gen::new(fn(rng) {
    let ir = gen_ir_node(rng, max_depth)
    let rules = gen_cost_rules(rng)
    (ir, rules)
  })
}

///|
/// 统计 IR 树节点数。
fn count_ir_nodes(ir : IrNode) -> Int {
  match ir {
    Const(_) => 1
    VarRef(_) => 1
    BinOp(_, l, r) => 1 + count_ir_nodes(l) + count_ir_nodes(r)
  }
}


// ---------------------------------------------------------------------------
// 黑盒记号工具（自带 tokenizer / 版本解析，不依赖包内私有）
// ---------------------------------------------------------------------------

///|
/// 以空格切分指令为记号（测试本地）。
fn t_tokenize(s : String) -> Array[String] {
  let toks : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == ' ' {
      if cur != "" {
        toks.push(cur)
        cur = ""
      }
    } else {
      cur = cur + c.to_string()
    }
  }
  if cur != "" {
    toks.push(cur)
  }
  toks
}

///|
/// 解析带版本记号 `name#ver` → `(name, ver)`；非该形式返回 None。
fn t_split_versioned(tok : String) -> (String, Int)? {
  let cs = tok.iter().to_array()
  let mut hash = -1
  for i in 0..<cs.length() {
    if cs[i] == '#' {
      hash = i
    }
  }
  if hash <= 0 || hash + 1 >= cs.length() {
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
  let mut name = ""
  for i in 0..<hash {
    name = name + cs[i].to_string()
  }
  Some((name, n))
}

///|
/// 收集 SSA 程序全部定义版本号（块内定义左值 + φ 目标）。
fn t_def_version_ids(p : SsaProgram) -> Array[Int] {
  let ids : Array[Int] = []
  for b in p.blocks {
    for instr in b.instrs {
      let toks = t_tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        match t_split_versioned(toks[0]) {
          Some((_, v)) => ids.push(v)
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

///|
/// 整数数组是否两两互不相同。
fn t_all_distinct(xs : Array[Int]) -> Bool {
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
/// 重建每个 φ 的 (所在块, 变量名)，与 `p.phis` 顺序对齐；无法定位者为 ("", "")。
fn t_phi_sites(p : SsaProgram) -> Array[(String, String)] {
  let ver2name : Map[Int, String] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = t_tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        match t_split_versioned(toks[0]) {
          Some((nm, v)) => ver2name[v] = nm
          None => ()
        }
      }
    }
  }
  let out : Array[(String, String)] = []
  for phi in p.phis {
    if phi.args.length() == 0 {
      out.push(("", ""))
      continue
    }
    let name = ver2name.get(phi.args[0].id).unwrap_or("")
    if name == "" {
      out.push(("", ""))
      continue
    }
    let dest_tok = name + "#" + phi.dest.id.to_string()
    let mut found = ""
    for b in p.blocks {
      if preds_of(p.blocks, b.label).length() < 2 {
        continue
      }
      let mut uses = false
      for instr in b.instrs {
        for t in t_tokenize(instr) {
          if t == dest_tok {
            uses = true
            break
          }
        }
        if uses {
          break
        }
      }
      if uses {
        found = b.label
        break
      }
    }
    out.push((found, name))
  }
  out
}

///|
/// 计算某变量定义块集合的迭代支配边界（Cytron worklist），供 P9 参考校验。
fn t_iterated_df(
  df : Map[String, Array[String]],
  defblocks : Array[String],
) -> Map[String, Bool] {
  let has_phi : Map[String, Bool] = Map([])
  let on_work : Map[String, Bool] = Map([])
  let worklist : Array[String] = []
  for b in defblocks {
    worklist.push(b)
    on_work[b] = true
  }
  while worklist.length() > 0 {
    let x = worklist.pop().unwrap()
    for y in df.get(x).unwrap_or([]) {
      if not(has_phi.contains(y)) {
        has_phi[y] = true
        if not(on_work.contains(y)) {
          on_work[y] = true
          worklist.push(y)
        }
      }
    }
  }
  has_phi
}

///|
/// 计算各变量的定义块集合（限可达块，去重；用原始 CFG 的未版本化名字）。
fn t_def_blocks(
  blocks : Array[BasicBlock],
  reach : Map[String, Bool],
) -> Map[String, Array[String]] {
  let m : Map[String, Array[String]] = Map([])
  for b in blocks {
    if not(reach.contains(b.label)) {
      continue
    }
    for instr in b.instrs {
      let toks = t_tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        let name = toks[0]
        let lst = m.get(name).unwrap_or([])
        if not(t_contains_str(lst, b.label)) {
          lst.push(b.label)
        }
        m[name] = lst
      }
    }
  }
  m
}

// ---------------------------------------------------------------------------
// 语义保持类属性（P12/P13/P14）的共享生成器：SSA 程序 + 初始赋值 + entry-rooted 路径
// ---------------------------------------------------------------------------

///|
/// 沿 succs 从入口（`blocks[0]`）随机游走，产生一条 entry-rooted 路径（终于 sink）。
fn t_gen_path(rng : @infra_pbt.Rng, blocks : Array[BasicBlock]) -> Array[String] {
  let by_label : Map[String, BasicBlock] = Map([])
  for b in blocks {
    by_label[b.label] = b
  }
  let path : Array[String] = []
  let mut cur = if blocks.length() > 0 { blocks[0].label } else { "" }
  let mut steps = 0
  let limit = blocks.length() + 2
  while steps <= limit && cur != "" {
    path.push(cur)
    match by_label.get(cur) {
      Some(b) =>
        if b.succs.length() == 0 {
          break
        } else {
          cur = b.succs[rng.next_below(b.succs.length())]
        }
      None => break
    }
    steps = steps + 1
  }
  path
}

///|
/// 随机右值：常量或 `a op b`（操作数取自变量池）。
fn t_rand_rhs(rng : @infra_pbt.Rng) -> String {
  if rng.next_bool() {
    rng.next_range(0, 9).to_string()
  } else {
    let a = cfg_var_pool[rng.next_below(cfg_var_pool.length())]
    let b = cfg_var_pool[rng.next_below(cfg_var_pool.length())]
    let op = cfg_op_pool[rng.next_below(cfg_op_pool.length())]
    a + " " + op + " " + b
  }
}

///|
/// 生成 `count` 条随机定义指令。
fn t_eval_defs(rng : @infra_pbt.Rng, count : Int) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i < count {
    let lhs = cfg_var_pool[rng.next_below(cfg_var_pool.length())]
    out.push(lhs + " = " + t_rand_rhs(rng))
    i = i + 1
  }
  out
}

///|
/// 受控形态的语义测试 CFG：直线 / 单菱形 / 三路汇合（单层汇合，φ 目标仅在其
/// 汇合块被使用 → φ 落点重建无歧义；条件取外部 `p` → SCCP 不剪枝）。
fn gen_eval_blocks(rng : @infra_pbt.Rng) -> Array[BasicBlock] {
  let shape = rng.next_below(3)
  if shape == 0 {
    // 直线代码。
    let instrs = t_eval_defs(rng, rng.next_range(1, 4))
    instrs.push("ret " + cfg_var_pool[rng.next_below(cfg_var_pool.length())])
    [{ label: "b0", instrs, succs: [] }]
  } else if shape == 1 {
    // 单菱形：then/else 均定义 x → join 处为 x 插 φ。
    let then_instrs : Array[String] = ["x = " + t_rand_rhs(rng)]
    for e in t_eval_defs(rng, rng.next_below(2)) {
      then_instrs.push(e)
    }
    then_instrs.push("br join")
    let else_instrs : Array[String] = ["x = " + t_rand_rhs(rng)]
    for e in t_eval_defs(rng, rng.next_below(2)) {
      else_instrs.push(e)
    }
    else_instrs.push("br join")
    [
      { label: "b0", instrs: ["cbr p then else"], succs: ["then", "else"] },
      { label: "then", instrs: then_instrs, succs: ["join"] },
      { label: "else", instrs: else_instrs, succs: ["join"] },
      { label: "join", instrs: ["y = x + 1", "ret y"], succs: [] },
    ]
  } else {
    // 三路汇合。
    let b1 : Array[String] = ["x = " + t_rand_rhs(rng), "br join"]
    let b2 : Array[String] = ["x = " + t_rand_rhs(rng), "br join"]
    let b3 : Array[String] = ["x = " + t_rand_rhs(rng), "br join"]
    [
      { label: "b0", instrs: ["cbr p b1 b2"], succs: ["b1", "b2", "b3"] },
      { label: "b1", instrs: b1, succs: ["join"] },
      { label: "b2", instrs: b2, succs: ["join"] },
      { label: "b3", instrs: b3, succs: ["join"] },
      { label: "join", instrs: ["ret x"], succs: [] },
    ]
  }
}

///|
/// 生成器：随机 SSA 程序（受控形态，`build_ssa_minimal` 构造）+ 初始赋值 +
/// entry-rooted 路径。
fn gen_ssa_eval_case() -> @infra_pbt.Gen[
  (SsaProgram, Map[String, Int], Array[String]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let blocks = gen_eval_blocks(rng)
    let entry = blocks[0].label
    let ssa = build_ssa_minimal(blocks, entry~)
    let init : Map[String, Int] = Map([])
    for nm in cfg_var_pool {
      init[nm] = rng.next_range(0, 9)
    }
    init["p"] = rng.next_range(0, 9)
    let path = t_gen_path(rng, blocks)
    (ssa, init, path)
  })
}

///|
/// 两个 EvalResult 的输出序列是否一致（语义等价的可观测判据）。
fn t_outputs_equal(a : EvalResult, b : EvalResult) -> Bool {
  if a.output.length() != b.output.length() {
    return false
  }
  for i in 0..<a.output.length() {
    if a.output[i] != b.output[i] {
      return false
    }
  }
  true
}


// ---------------------------------------------------------------------------
// 寄存器分配 / 一致性属性的共享生成器
// ---------------------------------------------------------------------------

///|
/// 随机干涉图生成器（节点 id = 0..n-1，n ∈ [1,8]；每对约 50% 概率连边）。
fn gen_interference_graph() -> @infra_pbt.Gen[InterferenceGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let nodes : Array[Var] = []
    for i in 0..<n {
      nodes.push({ id: i })
    }
    let edges : Array[(Var, Var)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push(({ id: i }, { id: j }))
        }
      }
    }
    { nodes, edges }
  })
}

///|
/// 干涉图的最大度。
fn t_max_degree(g : InterferenceGraph) -> Int {
  let deg : Map[Int, Int] = Map([])
  for v in g.nodes {
    deg[v.id] = 0
  }
  for e in g.edges {
    let (a, b) = e
    deg[a.id] = deg.get(a.id).unwrap_or(0) + 1
    deg[b.id] = deg.get(b.id).unwrap_or(0) + 1
  }
  let mut m = 0
  for kv in deg {
    let (_, d) = kv
    if d > m {
      m = d
    }
  }
  m
}

///|
/// 图着色分配是否尊重干涉：每条边两端若均为 Reg 则编号不同。
fn t_coloring_respects(g : InterferenceGraph, alloc : Map[Var, Location]) -> Bool {
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
/// 分配是否覆盖图全部节点、每节点恰一个 Location。
fn t_alloc_covers(g : InterferenceGraph, alloc : Map[Var, Location]) -> Bool {
  if alloc.size() != g.nodes.length() {
    return false
  }
  for v in g.nodes {
    if alloc.get(v) is None {
      return false
    }
  }
  true
}

///|
/// 分配中的溢出数量。
fn t_count_spills(alloc : Map[Var, Location]) -> Int {
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
/// 生成最大重叠度 `≤ k` 的活跃区间集合 + `k`。
///
/// 构造为若干「轮次」的不相交团：第 r 轮所有区间同为 `[4r, 4r+1]`（彼此重叠成
/// 团，团大小 ∈ [1, k]），轮次间间隔 ≥3 故互不重叠。如此最大同时活跃数 ≤ k，
/// 且导出干涉图为「大小 ≤ k 的不相交团」之并——每个节点度 `< k`，图着色与线性
/// 扫描均判无需溢出。
fn gen_bounded_overlap_intervals() -> @infra_pbt.Gen[(Array[LiveInterval], Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_range(1, 4)
    let rounds = rng.next_range(1, 4)
    let intervals : Array[LiveInterval] = []
    let mut vid = 0
    for r in 0..<rounds {
      let m = rng.next_range(1, k) // 团大小 ∈ [1, k]
      let start = 4 * r
      let mut i = 0
      while i < m {
        intervals.push({ variable: { id: vid }, start, end: start + 1 })
        vid = vid + 1
        i = i + 1
      }
    }
    (intervals, k)
  })
}

///|
/// 生成随机干涉图 + 传送候选集 + k（用于保守合并安全性属性）。
fn gen_coalesce_case() -> @infra_pbt.Gen[
  (InterferenceGraph, MoveSet, Int),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 8)
    let nodes : Array[Var] = []
    for i in 0..<n {
      nodes.push({ id: i })
    }
    let edges : Array[(Var, Var)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_below(3) == 0 {
          edges.push(({ id: i }, { id: j }))
        }
      }
    }
    let g : InterferenceGraph = { nodes, edges }
    // 传送候选：0..n 对随机变量。
    let moves : Array[(Var, Var)] = []
    let m = rng.next_below(n)
    let mut t = 0
    while t < m {
      let a = rng.next_below(n)
      let b = rng.next_below(n)
      if a != b {
        moves.push(({ id: a }, { id: b }))
      }
      t = t + 1
    }
    let k = rng.next_range(1, 4)
    (g, { moves, }, k)
  })
}
