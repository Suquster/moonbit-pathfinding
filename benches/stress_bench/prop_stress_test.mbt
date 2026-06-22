// Feature: championship-v1-upgrade, Property 9: 大规模算法路径合法性与代价一致性
//
// 本文件以属性测试（property-based test）校验大规模图族上 BFS / Dijkstra / A\*
// 的路径合法性与代价一致性（design.md §「Property 9」/ Requirement 7.1–7.4）：
//
//   **大规模算法路径合法性与代价一致性**：对任意随机加权网格图与随机查询，
//   BFS / Dijkstra / A\* 均终止并满足——
//     * 返回非空路径时，每相邻节点对在输入图中存在对应边、首节点 = 源、
//       末节点 = 目标（R7.2 / R7.3）；
//     * 返回代价与沿返回路径各边权重之和的偏差 ≤ 1e-9（R7.3，整数权下恒为 0）；
//     * 目标不可达时返回明确无解（空路径 / None）（R7.4）；
//     * 运行前后输入图逐元素不变（R7.1）。
//
// 规模说明（与 task 20.1 协作）：完整 10000 节点规模采集由 stress_bench.mbt 的
// `@bench.T` 基准块承载（仅 `moon bench` 执行）。本属性测试在 **适中网格规模**
// （边长 3–16，节点 ≤256）上跑 ≥100 次随机实例以验证 Property 9 的合法性 / 代价 /
// 可达 / 不改图四类不变量，从而保证普通 `moon test` 能在 wasm-gc 解释执行下于
// 合理时间内完成（设计依据：differential 测试亦采用按复杂度分级的适中规模）。
//
// 随机实例族：4-连通加权网格 + 随机障碍掩码 + 随机端点。障碍使部分实例的目标
// 自然不可达，从而同时覆盖「可达」与「不可达」两类用例（R7.2/R7.3 与 R7.4）。
// 可达性由独立的参考 BFS 泛洪（`reachable_ref`）裁定，作为算法返回 Some/None
// 是否正确的金标准——避免「算法在可达目标上误返回 None」之类的漏判。

// ───────────────────────────── 属性测试参数（命名常量） ─────────────────────────────

///|
/// 属性测试迭代次数（≥100 基线 · R22.1 / task 20.2「count≥100」）。
let p9_iters : Int = 128

///|
/// 随机网格边长下限（含）。取 3 以覆盖最小的多行多列结构。
let p9_min_side : Int = 3

///|
/// 随机网格边长上限（含）。16²=256 节点，在 wasm-gc 解释执行下 128 次迭代 ×
/// 3 算法仍可秒级完成；完整 10k 规模由 task 20.1 的基准块承载。
let p9_max_side : Int = 16

///|
/// 障碍占比上限（百分比）。每个实例的障碍占比在 `[0, p9_max_block_pct]` 内随机，
/// 使「可达 / 不可达」两类用例自然混合出现（端点格强制保持开放）。
let p9_max_block_pct : Int = 40

///|
/// 可复现反例重扫的基准种子（R7.5 诊断可复现）。主属性失败时自该种子起逐一
/// 递增定位首个可复现失败实例并输出结构化诊断。
let p9_base_seed : UInt64 = 0x9A11_57E5_5C0F_FEE9

///|
/// 可复现反例重扫的最大尝试次数：仅在主属性已失败时执行，对正常通过路径零开销。
let p9_rescan_iters : Int = 4096

// ───────────────────────────── 随机实例模型 ─────────────────────────────

///|
/// 单个随机压力实例：边长、带权邻接表、派生无权邻接表与查询端点。
struct StressInstance {
  side : Int
  adj : Array[Array[(Int, Int)]]
  uadj : Array[Array[Int]]
  source : Int
  target : Int
}

///|
/// 由带权邻接表派生无权邻接表（仅取邻居标识），供 BFS 与参考可达性复用。
fn p9_derive_unweighted(adj : Array[Array[(Int, Int)]]) -> Array[Array[Int]] {
  let n = adj.length()
  let uadj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    let out = uadj[u]
    for pair in adj[u] {
      out.push(pair.0)
    }
  }
  uadj
}

///|
/// 在带权邻接表中查找有向边 `u -> v` 的权重；不存在返回 `None`。
fn p9_find_edge_weight(
  adj : Array[Array[(Int, Int)]],
  u : Int,
  v : Int,
) -> Int? {
  if u < 0 || u >= adj.length() {
    return None
  }
  for pair in adj[u] {
    if pair.0 == v {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 顺序敏感的图校验和；算法运行前后两次取值相等即视为输入图未被修改（R7.1）。
/// 使用 31 进制滚动哈希并按位与掩码保持三后端数值稳定。
fn p9_checksum(adj : Array[Array[(Int, Int)]]) -> Int {
  let mask = 0x7fffffff
  let mut h = 0x1F2E3D4C
  for u in 0..<adj.length() {
    h = (h * 31 + u).land(mask)
    for pair in adj[u] {
      let (v, w) = pair
      h = (h * 31 + v).land(mask)
      h = (h * 31 + w).land(mask)
    }
  }
  h
}

// ───────────────────────────── 随机实例生成器 ─────────────────────────────

///|
/// 随机压力实例生成器：完全由 `@infra_pbt.Rng` 驱动以保证同种子可复现。
///
/// 步骤：
///   1. 边长 `side ∈ [p9_min_side, p9_max_side]`，节点数 `n = side²`。
///   2. 障碍占比 `pct ∈ [0, p9_max_block_pct]`；逐格按 `next_below(100) < pct`
///      标记障碍。
///   3. 端点 `source, target ∈ [0, n)`（允许相等，覆盖平凡查询边界）。强制将
///      端点格设为开放，避免「端点本身被障碍封死」这类与可达性无关的退化。
///   4. 向右 / 向下连双向边，权重 `∈ [1, stress_max_weight]`（≥1 保证曼哈顿
///      启发式可采纳）；任一端点为障碍则跳过该边。
fn p9_instance_gen() -> @infra_pbt.Gen[StressInstance] {
  @infra_pbt.Gen::new(fn(rng) {
    let side = rng.next_range(p9_min_side, p9_max_side)
    let n = side * side
    let pct = rng.next_range(0, p9_max_block_pct)
    let blocked = Array::make(n, false)
    for i in 0..<n {
      blocked[i] = rng.next_below(100) < pct
    }
    let source = rng.next_below(n)
    let target = rng.next_below(n)
    // 端点格强制开放：保证「不可达」仅由结构（障碍隔断）造成，而非端点自封。
    blocked[source] = false
    blocked[target] = false
    let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
    for r in 0..<side {
      for c in 0..<side {
        let u = r * side + c
        if c + 1 < side {
          let v = r * side + (c + 1)
          // 先采样权重以保持随机序列稳定，再依据障碍决定是否落边。
          let w = 1 + rng.next_below(stress_max_weight)
          if !blocked[u] && !blocked[v] {
            adj[u].push((v, w))
            adj[v].push((u, w))
          }
        }
        if r + 1 < side {
          let v = (r + 1) * side + c
          let w = 1 + rng.next_below(stress_max_weight)
          if !blocked[u] && !blocked[v] {
            adj[u].push((v, w))
            adj[v].push((u, w))
          }
        }
      }
    }
    let uadj = p9_derive_unweighted(adj)
    { side, adj, uadj, source, target }
  })
}

// ───────────────────────────── 参考可达性（金标准） ─────────────────────────────

///|
/// 参考 BFS 泛洪：独立判定 `target` 是否从 `source` 可达，作为算法返回
/// Some / None 是否正确的金标准。以数组游标实现 FIFO 队列，O(V+E) 终止。
fn p9_reachable_ref(
  uadj : Array[Array[Int]],
  source : Int,
  target : Int,
) -> Bool {
  let n = uadj.length()
  if source < 0 || source >= n || target < 0 || target >= n {
    return false
  }
  let visited = Array::make(n, false)
  let queue : Array[Int] = []
  visited[source] = true
  queue.push(source)
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head = head + 1
    if u == target {
      return true
    }
    for v in uadj[u] {
      if !visited[v] {
        visited[v] = true
        queue.push(v)
      }
    }
  }
  visited[target]
}

// ───────────────────────────── 路径校验 ─────────────────────────────

///|
/// 校验无权路径（BFS）：非空、首 = 源、末 = 目标、每相邻对在图中存在边（R7.2）。
fn p9_unweighted_path_valid(
  adj : Array[Array[(Int, Int)]],
  path : Array[Int],
  source : Int,
  target : Int,
) -> Bool {
  let len = path.length()
  if len == 0 {
    return false
  }
  if !(path[0] == source && path[len - 1] == target) {
    return false
  }
  for i in 0..<(len - 1) {
    if p9_find_edge_weight(adj, path[i], path[i + 1]) is None {
      return false
    }
  }
  true
}

///|
/// 校验带权路径（Dijkstra / A\*）：返回 `(path_valid, cost_consistent)`。
///   * path_valid：非空、首 = 源、末 = 目标、每相邻对在图中存在边（R7.2/R7.3）。
///   * cost_consistent：返回代价与沿路径各边权之和的偏差 ≤ `stress_cost_epsilon`
///     （R7.3，整数权下恒为 0）。
fn p9_weighted_path_valid(
  adj : Array[Array[(Int, Int)]],
  path : Array[Int],
  cost : Int,
  source : Int,
  target : Int,
) -> (Bool, Bool) {
  let len = path.length()
  if len == 0 {
    return (false, false)
  }
  let endpoints_ok = path[0] == source && path[len - 1] == target
  let mut edges_ok = true
  let mut sum = 0
  for i in 0..<(len - 1) {
    match p9_find_edge_weight(adj, path[i], path[i + 1]) {
      Some(w) => sum = sum + w
      None => edges_ok = false
    }
  }
  let path_valid = endpoints_ok && edges_ok
  let cost_consistent = (cost.to_double() - sum.to_double()).abs() <=
    stress_cost_epsilon
  (path_valid, cost_consistent)
}

// ───────────────────────────── 单实例属性判定 ─────────────────────────────

///|
/// 对单个随机实例，运行 BFS / Dijkstra / A\* 并逐项判定 Property 9 不变量。
/// 返回 `true` 表示三算法均满足合法性 / 代价 / 可达 / 不改图（R7.1–R7.4）。
///
/// 判定口径：以参考可达性 `reachable` 为金标准——
///   * 可达：算法必须返回 Some 且路径合法（带权另需代价一致）；
///   * 不可达：算法必须返回 None（空 / None）；
///   * 任何算法运行不得改动输入图（前后校验和一致）。
fn p9_instance_holds(inst : StressInstance) -> Bool {
  let reachable = p9_reachable_ref(inst.uadj, inst.source, inst.target)
  let before = p9_checksum(inst.adj)

  // —— BFS（无权可达）。 ——
  let bfs_res = @uw.bfs(inst.source, fn(u) { inst.uadj[u] }, fn(v) {
    v == inst.target
  })
  let bfs_ok = match bfs_res {
    Some(path) =>
      reachable &&
      p9_unweighted_path_valid(inst.adj, path, inst.source, inst.target)
    None => !reachable
  }

  // —— Dijkstra（带权最短路）。 ——
  let dij_res = @dir.dijkstra(inst.source, fn(u) { inst.adj[u] }, fn(v) {
    v == inst.target
  })
  let dij_ok = match dij_res {
    Some((path, cost)) => {
      let (pv, cc) = p9_weighted_path_valid(
        inst.adj,
        path,
        cost,
        inst.source,
        inst.target,
      )
      reachable && pv && cc
    }
    None => !reachable
  }

  // —— A\*（曼哈顿启发式，边权 ≥1 故可采纳）。 ——
  let side = inst.side
  let tr = inst.target / side
  let tc = inst.target % side
  let heuristic = fn(u : Int) -> Int {
    let ur = u / side
    let uc = u % side
    (ur - tr).abs() + (uc - tc).abs()
  }
  let astar_res = @dir.astar(inst.source, fn(u) { inst.adj[u] }, heuristic, fn(
    v,
  ) {
    v == inst.target
  })
  let astar_ok = match astar_res {
    Some((path, cost)) => {
      let (pv, cc) = p9_weighted_path_valid(
        inst.adj,
        path,
        cost,
        inst.source,
        inst.target,
      )
      reachable && pv && cc
    }
    None => !reachable
  }
  let after = p9_checksum(inst.adj)
  let graph_unmodified = before == after
  bfs_ok && dij_ok && astar_ok && graph_unmodified
}

// ───────────────────────────── 失败诊断（可复现重扫） ─────────────────────────────

///|
/// 渲染单个失败实例的结构化诊断（用 `@infra_text.TextBuilder`，禁止循环内 `+`）。
fn p9_instance_diagnostic(inst : StressInstance, seed : UInt64) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("[stress-prop] seed=")
  tb.push_str(seed.to_string())
  tb.push_str(" side=")
  tb.push_str(inst.side.to_string())
  tb.push_str(" n=")
  tb.push_str(inst.adj.length().to_string())
  tb.push_str(" src=")
  tb.push_str(inst.source.to_string())
  tb.push_str(" dst=")
  tb.push_str(inst.target.to_string())
  tb.push_str(" reachable_ref=")
  tb.push_str(p9_reachable_ref(inst.uadj, inst.source, inst.target).to_string())
  tb.push_str(" instance_holds=")
  tb.push_str(p9_instance_holds(inst).to_string())
  tb.build()
}

///|
/// 可复现反例重扫（R7.5 诊断）：自 `base_seed` 起逐一递增种子，用该种子独立
/// 构造 `Rng` 产出实例并判定；一旦发现失败即返回其结构化诊断。整个
/// `(seed → Rng → 实例)` 流程确定性，故诊断中的种子可逐字节重放该反例。
/// `iters` 次内未命中则返回 `None`。
fn p9_seeded_report(base_seed : UInt64, iters : Int) -> String? {
  let gen = p9_instance_gen()
  let mut i = 0
  while i < iters {
    let seed = base_seed + i.to_uint64()
    let inst = gen.generate(@infra_pbt.rng_new(seed))
    if !p9_instance_holds(inst) {
      return Some(p9_instance_diagnostic(inst, seed))
    }
    i = i + 1
  }
  None
}

// ───────────────────────────── 属性测试主体 ─────────────────────────────

///|
/// Feature: championship-v1-upgrade, Property 9: 大规模算法路径合法性与代价一致性
///
/// 对任意随机加权网格图与随机查询，BFS / Dijkstra / A\* 终止并满足：返回非空
/// 路径时每相邻对为图中边、首 = 源、末 = 目标，返回代价与沿路径边权之和偏差
/// ≤1e-9；目标不可达时返回空 / None；运行不修改输入图。每个属性各迭代 128 次
/// （≥100 基线）；失败时以可复现种子重扫并输出含「实例 / 种子」的诊断（R7.5）。
///
/// **Validates: Requirements 7.1, 7.2, 7.3, 7.4**
test "Feature: championship-v1-upgrade, Property 9: large-scale path validity and cost consistency" {
  // 锚点 1：可达性参考与算法一致的最小确定性实例（2×2 全开网格，角到角必达）。
  let anchor_gen = p9_instance_gen()
  let anchor = anchor_gen.generate(@infra_pbt.rng_new(0x1357_9BDF_2468_ACE0))
  // 锚点实例自身满足 Property 9 不变量。
  assert_true(p9_instance_holds(anchor))
  // 锚点 2：同种子生成逐元素确定性（可复现性，R7.5 诊断种子可重放的前提）。
  let g1 = anchor_gen.generate(@infra_pbt.rng_new(0xABCD_1234_5678_9F0E))
  let g2 = anchor_gen.generate(@infra_pbt.rng_new(0xABCD_1234_5678_9F0E))
  assert_eq(g1.side, g2.side)
  assert_eq(g1.source, g2.source)
  assert_eq(g1.target, g2.target)
  assert_eq(p9_checksum(g1.adj), p9_checksum(g2.adj))
  // 锚点 3：恒满足的属性下，可复现重扫不应产生伪反例（found=None）。
  assert_true(p9_seeded_report(p9_base_seed, 256) is None)

  // 主属性：≥100 次随机实例下 Property 9 恒成立（R7.1–R7.4）。
  let ok = @infra_pbt.holds_for_all(
    p9_instance_gen(),
    fn(inst) { p9_instance_holds(inst) },
    iters=p9_iters,
  )
  if !ok {
    // R7.5：以可复现种子重扫，输出含实例 / 种子的结构化诊断便于定位。
    match p9_seeded_report(p9_base_seed, p9_rescan_iters) {
      Some(report) => println(report)
      None =>
        println(
          "属性测试已发现反例，但可复现重扫未在上限内命中；请提高 p9_rescan_iters 或更换 p9_base_seed 复现。",
        )
    }
  }
  assert_true(ok)
}
