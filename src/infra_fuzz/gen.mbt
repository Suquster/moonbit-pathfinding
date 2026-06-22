// gen.mbt —— 结构化随机图模型 `FuzzGraph` 与确定性图生成器（task 7.1）。
//
// 设计依据（design.md §5.1 Fuzz_Generator · Requirement 16.6 / 17.1 / 17.7）：
//
//   pub(all) struct FuzzGraph { n : Int; edges : Array[(Int, Int, Double)] }
//   pub fn fuzz_graph_gen(max_n, max_edges)        -> @infra_pbt.Gen[FuzzGraph]
//   pub fn fuzz_graph_nonneg_gen(max_n, max_edges) -> @infra_pbt.Gen[FuzzGraph]
//
// 设计哲学：
//   * 生成器完全由 `@infra_pbt.Rng`（`UInt64` 种子，xorshift64）驱动；一切
//     随机抉择按确定性顺序自同一 `Rng` 取数，从而「同种子 → 逐元素相同的
//     图」（R17.7 可复现）。
//   * 以 `frequency` 在多种结构类别间按权重择一；以 `one_of` 在三类「带保证
//     结构」（自环 / 平行边 / 多连通分量）间等概率择一；以 `sized` 为稀疏图
//     派生由种子决定的节点规模——三种组合子共同覆盖 R17.1 的全部结构类别。
//   * 全函数（total）实现：对退化参数（如 max_n=0 / max_edges=0）有确定的
//     安全回退，绝不使用 abort/todo!/panic 占位，绝不进入死循环。
//   * 命名常量替代 magic number；权重以「分」为整数单位生成后换算为 Double，
//     避免浮点不确定性，保证三后端一致。

///|
/// 节点规模硬上限（R17.1：节点数 0..10000）。
let node_hard_max : Int = 10000

///|
/// 边规模硬上限（R17.1：边数 0..100000）。
let edge_hard_max : Int = 100000

///|
/// 稠密图节点上限。约束 N×(N-1) 的可能边数规模在 edge_hard_max 之内，
/// 使稠密类别（边数 ≥ N×(N-1)/4）总能落在 [阈值, N×(N-1)] 区间。
let dense_node_cap : Int = 64

///|
/// 「带保证结构」类别（自环 / 平行边 / 多连通分量）的节点上限，规模适中即可
/// 稳定体现目标结构，避免无谓的大图开销。
let special_node_cap : Int = 32

///|
/// 单节点图的自环数量上限（0..single_loop_max）。≥2 时同时体现「自环 + 平行边」。
let single_loop_max : Int = 3

///|
/// 稀疏图「边数 ≤ 2N」约束中的边数系数。
let sparse_edge_factor : Int = 2

///|
/// 稀疏图按 `sized` 规模放大节点数的步长：`size ∈ [0,100]` → 节点最多约
/// (size+1)×scale，覆盖至 node_hard_max 的大规模稀疏图。
let sparse_size_scale : Int = 100

///|
/// 权重生成的最小正「分」值：1 分 → 0.01（R16/差分权重下限 0.01）。
let weight_cents_min_pos : Int = 1

///|
/// 权重生成的最大「分」值：1e8 分 → 1e6（R16/差分权重上限 1e6）。
let weight_cents_max : Int = 100000000

///|
/// 「分」到「单位」的换算因子（100 分 = 1.0）。
let cents_per_unit : Double = 100.0

///|
/// 结构类别在 `frequency` 中的相对权重（命名常量替代裸数字）。
let freq_empty : Int = 1

///|
let freq_single : Int = 2

///|
let freq_dense : Int = 3

///|
let freq_sparse : Int = 4

///|
let freq_special : Int = 3

///|
/// 结构化随机图：节点为 `0..n-1`；`edges` 为有向边 `(源, 目标, 权重)` 序列，
/// 允许自环（源 == 目标）与平行边（同一 `(源, 目标)` 多次出现）。
///
/// 作为差分 / 模糊测试的统一输入模型；`derive(Eq, Show)` 使「同种子确定性」
/// 等性质可直接以相等性断言与快照校验（R17.7）。字段 `n` 为节点数，`edges`
/// 以三元组数组精确表达每条有向边的源、目标与浮点权重（禁止字符串模拟结构化
/// 数据，R22.6）。该模型可经 `to_successors` 等适配后接入各算法入口。
pub(all) struct FuzzGraph {
  n : Int
  edges : Array[(Int, Int, Double)]
} derive(Eq, Show)

///|
/// 取两整数较小值。
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// 取两整数较大值。
fn imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// 将整数夹取到闭区间 `[lo, hi]`。
fn clamp_int(v : Int, lo : Int, hi : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// 由 `Rng` 生成一个权重。`nonneg` 为真时仅产出非负权（0.01..1e6，供
/// Dijkstra/BFS/Bellman-Ford 差分使用 · R16.6）；否则产出可正可负的权
/// （-1e6..1e6，供 Bellman-Ford/SPFA 等支持负权的算法模糊）。
///
/// 以整数「分」生成再换算为 Double，规避浮点取值的后端差异，保证可复现。
fn fuzz_weight(rng : @infra_pbt.Rng, nonneg : Bool) -> Double {
  let cents = if nonneg {
    rng.next_range(weight_cents_min_pos, weight_cents_max)
  } else {
    rng.next_range(-weight_cents_max, weight_cents_max)
  }
  cents.to_double() / cents_per_unit
}

///|
/// 在 `[lo, hi)` 节点区间内随机连一条边（含权重）。区间宽度 `> 0` 由调用方保证。
fn random_edge_in(
  rng : @infra_pbt.Rng,
  lo : Int,
  hi : Int,
  nonneg : Bool,
) -> (Int, Int, Double) {
  let span = hi - lo
  let u = lo + rng.next_below(span)
  let v = lo + rng.next_below(span)
  (u, v, fuzz_weight(rng, nonneg))
}

///|
/// 类别：空图（n=0，无边）。覆盖 R17.1 的「空图」边界。
fn empty_graph_gen() -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.Gen::new(fn(_rng) { { n: 0, edges: [] } })
}

///|
/// 类别：单节点图（n=1）。附带 0..single_loop_max 个自环；≥2 时同时体现平行边。
/// 覆盖 R17.1 的「单节点图」（及部分「自环 / 平行边」）边界。
fn single_node_gen(nonneg : Bool) -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let loops = rng.next_below(single_loop_max + 1)
    let edges : Array[(Int, Int, Double)] = []
    let mut i = 0
    while i < loops {
      edges.push((0, 0, fuzz_weight(rng, nonneg)))
      i += 1
    }
    { n: 1, edges }
  })
}

///|
/// 类别：稠密图。节点取 `[2, min(dense_node_cap, max_n)]`，边数落在
/// `[N×(N-1)/4, min(max_edges, N×(N-1))]`，从而满足「稠密：边数 ≥ N×(N-1)/4」
/// （R17.1）。边以非自环为主（自环类别另有专门生成器覆盖）。
fn dense_graph_gen(
  max_n : Int,
  max_edges : Int,
  nonneg : Bool,
) -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let cap = imin(dense_node_cap, max_n)
    // 退化：不足以构成稠密图（节点 < 2）时回退为至多单节点的无边图。
    if cap < 2 {
      return { n: imax(0, cap), edges: [] }
    }
    let n = rng.next_range(2, cap)
    let max_possible = n * (n - 1) // 有向简单图最多边数
    let threshold = max_possible / 4 // 稠密阈值 N×(N-1)/4
    let upper = imin(max_edges, max_possible)
    let lo = imin(threshold, upper)
    let count = rng.next_range(lo, upper)
    let edges : Array[(Int, Int, Double)] = []
    let mut i = 0
    while i < count {
      let u = rng.next_below(n)
      let mut v = rng.next_below(n)
      // 规避自环以使边落在简单图边集内，保证稠密度统计口径一致。
      if v == u {
        v = (u + 1) % n
      }
      edges.push((u, v, fuzz_weight(rng, nonneg)))
      i += 1
    }
    { n, edges }
  })
}

///|
/// 类别：稀疏图。由 `sized` 派生由种子决定的节点规模（最多放大至 max_n，
/// 覆盖大规模稀疏图）；边数落在 `[0, min(max_edges, 2N)]`，满足「稀疏：
/// 边数 ≤ 2N」（R17.1）。
fn sparse_graph_gen(
  max_n : Int,
  max_edges : Int,
  nonneg : Bool,
) -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.sized(fn(size) {
    @infra_pbt.Gen::new(fn(rng) {
      let scaled = (size + 1) * sparse_size_scale
      let n = imin(max_n, imax(1, scaled))
      // n=0（max_n=0）时下方 next_below(0) 返回 0、边数亦为 0，安全退化为空图。
      let max_e = imin(max_edges, sparse_edge_factor * n)
      let count = if max_e <= 0 { 0 } else { rng.next_below(max_e + 1) }
      let edges : Array[(Int, Int, Double)] = []
      let mut i = 0
      while i < count {
        edges.push(random_edge_in(rng, 0, n, nonneg))
        i += 1
      }
      { n, edges }
    })
  })
}

///|
/// 类别：自环图。保证「至少 1 个自环」（R17.1）；并追加若干随机边。
fn self_loop_graph_gen(
  max_n : Int,
  max_edges : Int,
  nonneg : Bool,
) -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let cap = imin(special_node_cap, max_n)
    // 至少需要 1 个节点与 1 条边容量才能体现自环，否则安全退化为无边图。
    if cap < 1 || max_edges < 1 {
      return { n: imax(0, imin(cap, 1)), edges: [] }
    }
    let n = rng.next_range(1, cap)
    let edges : Array[(Int, Int, Double)] = []
    let loop_node = rng.next_below(n)
    edges.push((loop_node, loop_node, fuzz_weight(rng, nonneg))) // 保证自环
    let extra_cap = imin(max_edges - 1, sparse_edge_factor * n)
    let extra = if extra_cap <= 0 { 0 } else { rng.next_below(extra_cap + 1) }
    let mut i = 0
    while i < extra {
      edges.push(random_edge_in(rng, 0, n, nonneg))
      i += 1
    }
    { n, edges }
  })
}

///|
/// 类别：平行边图。保证「至少 1 组平行边」——同一 `(u, v)` 出现两次（R17.1）；
/// 并追加若干随机边。
fn parallel_edge_graph_gen(
  max_n : Int,
  max_edges : Int,
  nonneg : Bool,
) -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let cap = imin(special_node_cap, max_n)
    // 至少需要 1 个节点与 2 条边容量才能体现平行边，否则安全退化为无边图。
    if cap < 1 || max_edges < 2 {
      return { n: imax(0, imin(cap, 1)), edges: [] }
    }
    let n = rng.next_range(1, cap)
    let edges : Array[(Int, Int, Double)] = []
    let u = rng.next_below(n)
    let v = rng.next_below(n)
    // 同一 (u, v) 连续两条边构成平行边（权重各自独立取值，互不影响平行性）。
    edges.push((u, v, fuzz_weight(rng, nonneg)))
    edges.push((u, v, fuzz_weight(rng, nonneg)))
    let extra_cap = imin(max_edges - 2, sparse_edge_factor * n)
    let extra = if extra_cap <= 0 { 0 } else { rng.next_below(extra_cap + 1) }
    let mut i = 0
    while i < extra {
      edges.push(random_edge_in(rng, 0, n, nonneg))
      i += 1
    }
    { n, edges }
  })
}

///|
/// 类别：多连通分量图。将节点划分为两个非空组 `A=[0,split)` 与 `B=[split,n)`，
/// 所有边仅落在组内，从而保证「至少 2 个不连通分量」（R17.1）。
fn multi_component_graph_gen(
  max_n : Int,
  max_edges : Int,
  nonneg : Bool,
) -> @infra_pbt.Gen[FuzzGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let cap = imin(special_node_cap, max_n)
    // 至少需要 2 个节点才能划分为两个分量，否则安全退化为至多单节点无边图。
    if cap < 2 {
      return { n: imax(0, imin(cap, 1)), edges: [] }
    }
    let n = rng.next_range(2, cap)
    let split = rng.next_range(1, n - 1) // A=[0,split), B=[split,n)，两组均非空
    let max_e = imin(max_edges, sparse_edge_factor * n)
    let count = if max_e <= 0 { 0 } else { rng.next_below(max_e + 1) }
    let edges : Array[(Int, Int, Double)] = []
    let mut i = 0
    while i < count {
      // 等概率选择在 A 组或 B 组内部连边；跨组永不连边 → 两组互不连通。
      if rng.next_bool() {
        edges.push(random_edge_in(rng, 0, split, nonneg))
      } else {
        edges.push(random_edge_in(rng, split, n, nonneg))
      }
      i += 1
    }
    { n, edges }
  })
}

///|
/// 构造 `FuzzGraph` 生成器的统一内核：以 `frequency` 在各结构类别间按权重择一，
/// 其中三类「带保证结构」（自环 / 平行边 / 多连通分量）经 `one_of` 等概率择一。
/// `nonneg` 决定权重是否限定为非负。
///
/// 参数先夹取到硬上限 `[0, node_hard_max]` / `[0, edge_hard_max]`（R17.1），
/// 使非法或过大入参以安全边界处理而非崩溃。
fn build_fuzz_graph_gen(
  max_n : Int,
  max_edges : Int,
  nonneg : Bool,
) -> @infra_pbt.Gen[FuzzGraph] {
  let bn = clamp_int(max_n, 0, node_hard_max)
  let be = clamp_int(max_edges, 0, edge_hard_max)
  let special = @infra_pbt.one_of([
    self_loop_graph_gen(bn, be, nonneg),
    parallel_edge_graph_gen(bn, be, nonneg),
    multi_component_graph_gen(bn, be, nonneg),
  ])
  @infra_pbt.frequency([
    (freq_empty, empty_graph_gen()),
    (freq_single, single_node_gen(nonneg)),
    (freq_dense, dense_graph_gen(bn, be, nonneg)),
    (freq_sparse, sparse_graph_gen(bn, be, nonneg)),
    (freq_special, special),
  ])
}

///|
/// 多样图生成器（R17.1）：节点 0..10000、边 0..100000，覆盖空图 / 单节点 /
/// 稠密 / 稀疏 / 自环 / 平行边 / 多连通分量等结构类别。权重可正可负。
///
/// 完全由 `@infra_pbt.Rng`（`UInt64` 种子）驱动：以相同种子构造的 `Rng`
/// 两次生成产出逐元素相同的图（R17.7 可复现）。参数 `max_n` / `max_edges`
/// 为节点数与边数上界，实际规模由种子在 `[0, 上界]` 内派生。
pub fn fuzz_graph_gen(
  max_n : Int,
  max_edges : Int,
) -> @infra_pbt.Gen[FuzzGraph] {
  build_fuzz_graph_gen(max_n, max_edges, false)
}

///|
/// 非负权图生成器（R16.6）：结构覆盖同 `fuzz_graph_gen`，但所有边权限定为
/// 非负（0.01..1e6），供 Dijkstra / BFS / Bellman-Ford 之间的差分对比使用
/// （这些算法在非负权前提下结果应一致）。
///
/// 同样完全由 `@infra_pbt.Rng`（`UInt64` 种子）驱动，保证可复现（R17.7）。
/// 与 `fuzz_graph_gen` 仅在权重符号约束上不同：本生成器保证 `edges` 中每条
/// 边权落在 `[0.01, 1e6]`，从而满足非负权算法的前置条件。
pub fn fuzz_graph_nonneg_gen(
  max_n : Int,
  max_edges : Int,
) -> @infra_pbt.Gen[FuzzGraph] {
  build_fuzz_graph_gen(max_n, max_edges, true)
}
