// coloring.mbt —— Chaitin-Briggs 乐观着色与溢出代价启发式，旗舰深化旁路新增。
//
// paper-to-code：Chaitin 1982《Register Allocation & Spilling via Graph
// Coloring》；Briggs 1994 乐观着色（optimistic coloring）。三阶段栈式着色：
//   * simplify：反复移除度 `< k` 的节点并压入选择栈；
//   * potential-spill：无低度节点时按溢出代价选「代价最低」的度 `≥ k` 节点乐观
//     入栈并标记潜在溢出（R2.1）；
//   * select：按入栈逆序出栈，回填未被已着色邻居占用的最小寄存器；潜在溢出节点
//     若无可用寄存器则实际溢出 `Spill`（R1.2）。
//
// 设计落点（design.md §4.8，R1/R2.1）：为每个待分配变量产出恰一个 `Location`
// 且覆盖全部节点（R1.4）；任意干涉边两端若都为 `Reg` 则编号不同（R1.5）；
// `k ≥ 最大度+1` 时无溢出（R1.3/1.6）。既有 `allocate_coloring` 保留为基线，
// 不被本函数替换（R15.2）。复用同包私有 `build_adjacency`。

///|
/// 溢出代价度量：变量 → 代价（代价越低越优先作为乐观溢出候选）。
pub(all) struct SpillCost {
  cost : Map[Var, Double]
} derive(Debug)

///|
/// 均匀溢出代价（空表，所有变量查得缺省值 1.0），用作默认参数。
pub fn SpillCost::uniform() -> SpillCost {
  { cost: Map([]) }
}

///|
/// 由使用频度（以干涉度为代理）与活跃区间长度估算溢出代价：
/// `cost = (degree + 1) / max(1, interval_length)`。度高 / 区间短 → 代价高
/// （越不该被溢出）；度低 / 区间长 → 代价低（优先溢出）。
pub fn spill_cost(
  g : InterferenceGraph,
  intervals : Array[LiveInterval],
) -> SpillCost {
  let len_of : Map[Var, Int] = Map([])
  for iv in intervals {
    len_of[iv.variable] = iv.end - iv.start + 1
  }
  let adj = build_adjacency(g)
  let cost : Map[Var, Double] = Map([])
  for v in g.nodes {
    let deg = adj.get(v).unwrap_or([]).length()
    let freq = (deg + 1).to_double()
    let len = match len_of.get(v) {
      Some(l) => if l <= 0 { 1 } else { l }
      None => 1
    }
    cost[v] = freq / len.to_double()
  }
  { cost, }
}

///|
/// Chaitin-Briggs 三阶段栈式乐观着色 + 实际溢出回退。
pub fn allocate_coloring_briggs(
  g : InterferenceGraph,
  k : Int,
  cost? : SpillCost = SpillCost::uniform(),
) -> Map[Var, Location] {
  let result : Map[Var, Location] = Map([])
  // 退化：k ≤ 0，全部溢出。
  if k <= 0 {
    let nodes = g.nodes.copy()
    nodes.sort()
    let mut sp = 0
    for v in nodes {
      result[v] = Location::Spill(sp)
      sp = sp + 1
    }
    return result
  }
  let adj = build_adjacency(g)
  let nodes = g.nodes.copy()
  nodes.sort() // 按 id 升序，保证确定性
  // 工作度数（随移除递减）。
  let working : Map[Var, Int] = Map([])
  for v in nodes {
    working[v] = adj.get(v).unwrap_or([]).length()
  }
  let removed : Map[Var, Bool] = Map([])
  let stack : Array[Var] = [] // 入栈顺序（底→顶）；select 逆序出栈
  let total = nodes.length()
  while removed.length() < total {
    // simplify：取最小 id 的未移除、工作度 < k 的节点。
    let mut chosen : Var? = None
    for v in nodes {
      if !removed.contains(v) && working.get(v).unwrap_or(0) < k {
        chosen = Some(v)
        break
      }
    }
    let pick = match chosen {
      Some(v) => v
      None => {
        // potential-spill：未移除节点中溢出代价最低者（tie：最小 id）。
        let mut best : Var? = None
        let mut best_cost = 0.0
        for v in nodes {
          if removed.contains(v) {
            continue
          }
          let c = cost.cost.get(v).unwrap_or(1.0)
          match best {
            None => {
              best = Some(v)
              best_cost = c
            }
            Some(_) =>
              if c < best_cost {
                best = Some(v)
                best_cost = c
              }
          }
        }
        best.unwrap()
      }
    }
    removed[pick] = true
    stack.push(pick)
    for u in adj.get(pick).unwrap_or([]) {
      if !removed.contains(u) {
        working[u] = working.get(u).unwrap_or(1) - 1
      }
    }
  }
  // select：逆序出栈回填最小可用寄存器；无可用则实际溢出。
  let color_of : Map[Var, Int] = Map([])
  let mut next_spill = 0
  let mut idx = stack.length() - 1
  while idx >= 0 {
    let v = stack[idx]
    let forbidden : Map[Int, Bool] = Map([])
    for u in adj.get(v).unwrap_or([]) {
      match color_of.get(u) {
        Some(c) => forbidden[c] = true
        None => ()
      }
    }
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
    idx = idx - 1
  }
  result
}
