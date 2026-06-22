// unweighted_family_proof.mbt — 无权可达族（unweighted reachability family）
// 后置条件谓词基座（tasks.md 11.2 · Requirement 9.1/9.2/9.3/9.5）。
//
// 设计依据 design.md「proofs（扩展）」族表：
//   | 无权可达（bfs/bfs_all/dfs/bidirectional_bfs） | A + C |
//
// 即本族算法只校验两类不变量，**不**校验最短性（minimality / B）：
//   (A) path-validity —— 路径结构合法：非空、首节点=源、末节点=目标、
//       每相邻对 `(path[i], path[i+1])` 在图中存在对应有向边；
//   (C) none-witness  —— 无解见证：返回空/None ⟺ 输入图中确无从源到
//       目标的路径（用 `predicates.mbt` 的有界 BFS 预言机 `is_reachable`
//       交叉验证）。
//
// 之所以剔除最短性：DFS 仅保证「找到某条可达路径」而非最短路；为使同一族
// 谓词对 bfs/bfs_all/dfs/bidirectional_bfs 一致适用，本族统一只取 A+C。
// （`bfs_post` 已在 `bfs_proof.mbt` 额外叠加了 `check_minimality`，是 BFS
//  专属的更强后置条件；此处的族级谓词不复用该最短性分量。）
//
// 本文件仅依赖同包 `@proofs` 内既有谓词（`check_starts_at_start` /
// `check_ends_at_goal` / `check_edges_valid` / `check_none_witness` /
// `is_reachable`），不 import 任何算法包——proofs 仅依赖 @core。
//
// (D) bad-witness 拒绝：以下谓词均为纯函数，只读取 `result` / `reached` /
// `nodes` 并返回 `Bool`，从不写回或丢弃入参；对违反 A/C 之一的结果必判
// `false`。该拒绝行为由 10.5 的 bad-witness 测试统一驱动验证。

///|
/// `dfs_post(result, start, successors, goal, nodes)` —— DFS 后置条件谓词
/// （A + C）。`dfs` 返回 `Array[N]?`，与 BFS 同形，故复用同包既有分量谓词：
///
///   * (A) `check_starts_at_start` + `check_ends_at_goal` + `check_edges_valid`
///         —— 返回非空路径时，首节点=源、末节点满足 `goal`、每相邻对为图中边；
///   * (C) `check_none_witness` —— 返回 `None` ⟺ 图中确无从 `start` 到满足
///         `goal` 节点的路径。
///
/// 注意：**不**含最短性分量——DFS 不保证最短路，只保证找到某条合法可达路径。
///
/// 运行时用法示例：
///
/// ```moonbit skip
/// let r = @directed.dfs(start, succ, goal)
/// assert_true(@proofs.dfs_post(r, start, succ, goal, nodes))
/// ```
pub fn[N : Eq + Hash] dfs_post(
  result : Array[N]?,
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
  nodes : Array[N],
) -> Bool {
  // (A) 路径结构合法：非空、首=源、末=目标、相邻对为边。
  check_starts_at_start(result, start) &&
  check_ends_at_goal(result, goal) &&
  check_edges_valid(result, start, successors) &&
  // (C) 无解见证：None ⟺ 目标确不可达。
  check_none_witness(result, start, successors, goal, nodes)
}

///|
/// `bidirectional_bfs_post(result, start, goal, successors, nodes)` ——
/// 双向 BFS 后置条件谓词（A + C）。`bidirectional_bfs` 以**具体节点** `goal`
/// 为目标并返回 `Array[N]?`；此处把节点目标包装为谓词 `fn(x) { x == goal }`
/// 后复用同包分量谓词，与 `dfs_post` 同构。
///
///   * (A) 返回非空路径时：首节点=`start`、末节点=`goal`、每相邻对为图中边；
///   * (C) 返回 `None` ⟺ 图中确无从 `start` 到 `goal` 的路径。
///
/// 同样**不**含最短性分量：本族谓词统一只取 A+C（双向 BFS 的最短性若需单独
/// 论证，应另以专属谓词表述，避免与族级定义混淆）。
///
/// 运行时用法示例：
///
/// ```moonbit skip
/// let r = @directed.bidirectional_bfs(start, goal, succ, preds)
/// assert_true(@proofs.bidirectional_bfs_post(r, start, goal, succ, nodes))
/// ```
pub fn[N : Eq + Hash] bidirectional_bfs_post(
  result : Array[N]?,
  start : N,
  goal : N,
  successors : (N) -> Array[N],
  nodes : Array[N],
) -> Bool {
  // 把「具体节点目标」包装为谓词，复用无权族分量谓词。
  let goal_pred = fn(n : N) -> Bool { n == goal }
  // (A) 路径结构合法：非空、首=源、末=目标节点、相邻对为边。
  check_starts_at_start(result, start) &&
  check_ends_at_goal(result, goal_pred) &&
  check_edges_valid(result, start, successors) &&
  // (C) 无解见证：None ⟺ goal 确不可达。
  check_none_witness(result, start, successors, goal_pred, nodes)
}

///|
/// `bfs_all_post(reached, start, successors, nodes)` —— 全可达（多源/全图）
/// BFS 后置条件谓词（A + C）。
///
/// `bfs_all` 产出一棵以 `start` 为根的可达树（`BfsTree`：source/dist/parent）；
/// 由于 proofs 仅依赖 @core、不可 import 算法包，本谓词不直接接收 `BfsTree`，
/// 而是接收从该树剥离出的**可达节点集合** `reached : Array[N]`（调用方以
/// `tree.dist` 的键集合传入），并以图结构 + `nodes` 交叉验证其正确性：
///
///   * (A) soundness（返回的每个节点确实可达）：`start` 必在 `reached` 内，
///         且对 `reached` 中每个节点 `r`，有界可达性预言机 `is_reachable`
///         判定 `r` 确可从 `start` 抵达；
///   * (C) completeness / none-witness（所有可达节点都被包含）：对 `nodes`
///         中每个节点 `n`，若 `n` 确可从 `start` 抵达，则 `n` 必在 `reached`
///         内——等价于「节点缺席 `reached` ⟺ 该节点不可达」。
///
/// 二者合取即「`reached` 恰为从 `start` 出发的可达节点集」，是无权全可达
/// 算法结果形状下 A+C 的自然表述。
///
/// 运行时用法示例：
///
/// ```moonbit skip
/// let tree = @unweighted.bfs_all(start, succ)
/// let reached = tree.dist.keys().collect()
/// assert_true(@proofs.bfs_all_post(reached, start, succ, nodes))
/// ```
pub fn[N : Eq + Hash] bfs_all_post(
  reached : Array[N],
  start : N,
  successors : (N) -> Array[N],
  nodes : Array[N],
) -> Bool {
  // 预构可达集合，使成员判定为 O(1)（避免对每次查询做 O(n) 线性扫描）。
  let reached_set : Map[N, Bool] = Map([])
  for r in reached {
    reached_set[r] = true
  }
  // (A) soundness：源点必被包含。
  if !reached_set.contains(start) {
    return false
  }
  // (A) soundness：reached 中每个节点都确实可从 start 抵达。
  for r in reached {
    let goal_pred = fn(n : N) -> Bool { n == r }
    if !is_reachable(start, goal_pred, successors, nodes) {
      return false
    }
  }
  // (C) completeness：每个确实可达的节点都必须被包含。
  for n in nodes {
    let goal_pred = fn(m : N) -> Bool { m == n }
    if is_reachable(start, goal_pred, successors, nodes) &&
      !reached_set.contains(n) {
      return false
    }
  }
  true
}
