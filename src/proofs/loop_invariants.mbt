// loop_invariants.mbt — 循环不变式运行时断言谓词（Requirement R10.2–R10.4）。
//
// 本模块为「可表达为对算法状态求值的布尔判定」的循环不变式提供运行时断言
// 函数，供测试在主循环每次迭代后求值（R10.2）。与 `predicates.mbt` 一致，
// 每个谓词都是 **纯函数 + 全函数（total）**：只读取入参、不就地修改、无副
// 作用、不在无界数据上递归，便于将来 `moon prove` 直接引用。
//
// 设计参考 design.md §3.2：
//   * `dijkstra_pop_monotonic` —— Dijkstra 弹出单调性（R10.3）：按弹出顺序
//     记录的已定距离序列单调非降。
//   * `bfs_level_invariant` —— BFS 层序（R10.4）：当前队列内任意两节点层级
//     差绝对值 ≤1。
// 各经典算法主循环的 `///|` 不变式注解（布尔陈述 + 初始化 + 保持，R10.1）已系统性
// 补齐至 README 算法目录编号 1–30 的全部经典算法主循环，例如：
//   * `src/unweighted/bfs.mbt`（I1–I5）/ `src/unweighted/bfs_all.mbt`
//   * `src/directed/dijkstra.mbt` / `dijkstra_all.mbt` / `astar.mbt` / `ida_star.mbt`
//   * `src/directed/bellman_ford.mbt` / `bellman_ford_paths.mbt` / `dag_shortest_path.mbt`
//   * `src/directed/floyd_warshall.mbt` / `floyd_warshall_paths.mbt` / `johnson.mbt`
//   * `src/directed/{dfs,bidirectional_bfs,bidirectional_dijkstra,topo_sort,tarjan_scc}.mbt`
//   * `src/directed/{edmonds_karp,dinic,min_cut,min_cost_flow,eulerian,condensation,yen}.mbt`
//   * `src/undirected/{kruskal,prim,connected_components,bridges,kuhn_munkres,hopcroft_karp}.mbt`
// 其中 Dijkstra 弹出单调性、BFS 层序两条可机判定的不变式由下列谓词在测试中运行时断言。

///|
/// `dijkstra_pop_monotonic(dists)` —— Dijkstra 弹出单调性不变式（R10.3）。
///
/// `dists` 为 Dijkstra 主循环按弹出顺序记录的「已确定距离」序列。当且仅当该
/// 序列单调非降时成立：对所有相邻下标 `i`，`dists[i] <= dists[i + 1]`。
///
/// 数学背景：Dijkstra 使用非负边权 + 最小堆，每次弹出的节点已定距离不小于此
/// 前所有已弹出节点的已定距离——这正是「已弹出节点距离最终确定」性质的核心
/// 见证。空序列与单元素序列平凡成立。
///
/// 纯函数：仅顺序读取 `dists`，不修改入参。`W : @core.Weight` 已蕴含
/// `Compare`，故可直接用 `compare` 比较。
pub fn[W : @core.Weight] dijkstra_pop_monotonic(dists : Array[W]) -> Bool {
  if dists.length() <= 1 {
    return true
  }
  let mut i = 0
  while i < dists.length() - 1 {
    // dists[i] > dists[i + 1] 即违反单调非降。
    if dists[i].compare(dists[i + 1]) > 0 {
      return false
    }
    i += 1
  }
  true
}

///|
/// `bfs_level_invariant(levels)` —— BFS 层序不变式（R10.4）。
///
/// `levels` 为 BFS 主循环某时刻队列内各节点的层级（从源点起的边数）。当且仅
/// 当队列中任意两节点的层级差绝对值 ≤1 时成立，等价于 `max(levels) -
/// min(levels) <= 1`。
///
/// 数学背景：BFS 按层推进，队列在任意时刻至多同时容纳相邻两层节点，故层级
/// 极差不超过 1——这是「BFS 返回最短（边数）路径」定理的关键不变式。空队列
/// 与单元素队列平凡成立。
///
/// 纯函数：仅一遍扫描求最小/最大值，不修改入参。
pub fn bfs_level_invariant(levels : Array[Int]) -> Bool {
  if levels.length() <= 1 {
    return true
  }
  let mut lo = levels[0]
  let mut hi = levels[0]
  let mut i = 1
  while i < levels.length() {
    let v = levels[i]
    if v < lo {
      lo = v
    }
    if v > hi {
      hi = v
    }
    i += 1
  }
  hi - lo <= 1
}

// ---------------------------------------------------------------------------
// 通用不变式辅助谓词（direction-agnostic invariant helpers）
//
// 以下谓词与具体算法无关，作为各经典算法循环不变式断言的复用基座，保持纯且
// 全（total）。
// ---------------------------------------------------------------------------

///|
/// `is_monotonic_nondecreasing(xs)` —— 通用单调非降谓词。
///
/// 当且仅当 `xs` 中对所有相邻下标 `i` 有 `xs[i] <= xs[i + 1]` 时成立。
/// `dijkstra_pop_monotonic` 即其在 `W : @core.Weight` 上的特化语义；此泛型
/// 版本可服务任意 `Compare` 类型（如 BFS 层级序列单调非降）。
pub fn[T : Compare] is_monotonic_nondecreasing(xs : Array[T]) -> Bool {
  if xs.length() <= 1 {
    return true
  }
  let mut i = 0
  while i < xs.length() - 1 {
    if xs[i].compare(xs[i + 1]) > 0 {
      return false
    }
    i += 1
  }
  true
}

///|
/// `pairwise_diff_within(levels, bound)` —— 极差上界谓词。
///
/// 当且仅当 `max(levels) - min(levels) <= bound` 时成立，即队列内任意两元素
/// 差绝对值不超过 `bound`。`bfs_level_invariant` 即其 `bound = 1` 的特化。
/// `bound < 0` 时仅空/单元素序列可能平凡成立。
pub fn pairwise_diff_within(levels : Array[Int], bound : Int) -> Bool {
  if levels.length() <= 1 {
    return true
  }
  let mut lo = levels[0]
  let mut hi = levels[0]
  let mut i = 1
  while i < levels.length() {
    let v = levels[i]
    if v < lo {
      lo = v
    }
    if v > hi {
      hi = v
    }
    i += 1
  }
  hi - lo <= bound
}
