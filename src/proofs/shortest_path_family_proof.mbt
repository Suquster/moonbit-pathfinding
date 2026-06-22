// shortest_path_family_proof.mbt — 最短路族算法后置条件谓词（任务 11.1）
//
// 本文件为「最短路族」算法（astar / bellman_ford / dag_sp /
// bidirectional_dijkstra / ida_star / yen / johnson / floyd_warshall 等）
// 各提供 ≥1 个后置条件谓词，统一建立在 `predicates.mbt` 的聚合组合子
// `shortest_path_post` 之上（A 路径合法 + B 代价一致 + C none-witness）。
//
// 设计约束（对应 Requirement 9.1–9.5、design.md proofs 扩展）：
//   * proofs 包**仅依赖 @core**，本文件不 import 任何算法包；谓词只接收
//     `result` + successor / edge_weight 闭包等做**纯验证**。与真实算法的
//     交叉验证由后续测试任务（10.x）承担。
//   * 单源单目标算法的谓词是 `shortest_path_post` 的**薄封装/语义特化**：
//     签名一致，仅按各算法语义命名，便于未来 `moon prove` 的
//     `#ensures(astar_post(...))` 等注解按名引用。
//   * 全对最短路（johnson / floyd_warshall）：提供「逐对调用
//     `shortest_path_post` 的聚合谓词」，对每个 (s, t) 校验返回路径与代价。
//   * K 最短路（yen）：提供「每条路径合法且代价非降」的谓词。
//   * dijkstra_post 已存在于 `dijkstra_proof.mbt`，此处不重复。

///|
/// `astar_post` —— A* 后置条件谓词。
///
/// A* 在可采纳（admissible）启发式下与 Dijkstra 同样给出最短路，其返回结果
/// 形如 `(Array[N], W)?`，后置条件与最短路族一致：A 路径合法 + B 代价一致 +
/// C none-witness。本谓词为 `shortest_path_post` 的语义特化薄封装。
pub fn[N : Eq + Hash, W : @core.Weight] astar_post(
  result : (Array[N], W)?,
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  shortest_path_post(result, start, goal, successors, edge_weight, nodes)
}

///|
/// `bellman_ford_post` —— Bellman–Ford 后置条件谓词。
///
/// Bellman–Ford 支持负权边（但要求无负环），其「找到一条最短路」的后置条件
/// 同样可由 path-validity + cost-consistency + none-witness 表述。注意可达性
/// 预言机 `is_reachable` 不依赖边权符号，故负权场景下 C 分量依然成立。
pub fn[N : Eq + Hash, W : @core.Weight] bellman_ford_post(
  result : (Array[N], W)?,
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  shortest_path_post(result, start, goal, successors, edge_weight, nodes)
}

///|
/// `dag_sp_post` —— DAG 最短路（按拓扑序松弛）后置条件谓词。
///
/// 有向无环图最短路同样返回 `(Array[N], W)?`，后置条件与最短路族一致。
/// 本谓词不校验输入图的无环性（那是前提条件，由专门的前置谓词或测试承担），
/// 只对返回结果做 A+B+C 验证。
pub fn[N : Eq + Hash, W : @core.Weight] dag_sp_post(
  result : (Array[N], W)?,
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  shortest_path_post(result, start, goal, successors, edge_weight, nodes)
}

///|
/// `bidirectional_dijkstra_post` —— 双向 Dijkstra 后置条件谓词。
///
/// 双向搜索从源与目标两侧同时扩展并在中点相遇，但其对外契约仍是「返回一条
/// 合法且代价自洽的最短路」，故后置条件与单向版本一致。中点相遇/停止判据属
/// 实现内部不变量，不在结果级后置条件内表达。
pub fn[N : Eq + Hash, W : @core.Weight] bidirectional_dijkstra_post(
  result : (Array[N], W)?,
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  shortest_path_post(result, start, goal, successors, edge_weight, nodes)
}

///|
/// `ida_star_post` —— IDA*（迭代加深 A*）后置条件谓词。
///
/// IDA* 用代价阈值迭代加深替代优先队列，但其返回结果与 A* 同形
/// `(Array[N], W)?`，后置条件一致。迭代加深的阈值单调递增属内部终止度量，
/// 不在结果级后置条件内表达。
pub fn[N : Eq + Hash, W : @core.Weight] ida_star_post(
  result : (Array[N], W)?,
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  shortest_path_post(result, start, goal, successors, edge_weight, nodes)
}

///|
/// `yen_post` —— Yen K 最短路后置条件谓词。
///
/// Yen 算法返回从 `start` 到满足 `goal` 的**前 K 条**（按代价升序）简单路径，
/// 结果形如 `Array[(Array[N], W)]`。其后置条件：
///   1. **逐条合法**：每条 `(path, cost)` 单独视为 `Some((path, cost))` 时满足
///      `shortest_path_post` 的 A（路径合法、末节点落在 goal）+ B（代价自洽）；
///   2. **代价非降**：相邻两条路径代价满足 `cost[i] <= cost[i+1]`（K 最短路
///      按代价升序枚举）。
///
/// 说明：none-witness(C) 对 K 最短路以「空数组 ⟺ 目标不可达」表达——空结果时
/// 用有界 BFS 预言机校验确无可达路径；非空时各条已是显式可达见证。
pub fn[N : Eq + Hash, W : @core.Weight] yen_post(
  results : Array[(Array[N], W)],
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  // 空结果：等价于「目标不可达」。复用带权 none-witness 预言机（传入 None）。
  if results.length() == 0 {
    return check_none_witness_weighted(None, start, successors, goal, nodes)
  }
  // 逐条校验合法性（A+B），并检查代价非降（升序枚举）。
  let mut i = 0
  while i < results.length() {
    let (path, cost) = results[i]
    // 单条路径视为 Some 后复用聚合组合子的 A+B 分量；none-witness 在非空结果
    // 下平凡为真（Some 分支），故此处对每条调用 shortest_path_post 即可。
    if !shortest_path_post(
        Some((path, cost)),
        start,
        goal,
        successors,
        edge_weight,
        nodes,
      ) {
      return false
    }
    // 代价非降：与前一条比较。
    if i > 0 {
      let (_prev_path, prev_cost) = results[i - 1]
      if cost < prev_cost {
        return false
      }
    }
    i += 1
  }
  true
}

///|
/// `johnson_post` —— Johnson 全对最短路后置条件谓词。
///
/// Johnson 算法用势函数重赋权后对每个源跑 Dijkstra，产出**全对**最短路。
/// 结果以查询闭包 `lookup : (N, N) -> (Array[N], W)?` 表达：`lookup(s, t)`
/// 返回从 `s` 到 `t` 的最短路（不可达为 `None`）。
///
/// 后置条件：对 `pairs` 中每个 `(s, t)`，将其化归为「以 `s` 为源、目标谓词
/// 为 `n == t`」的单源单目标最短路问题，逐对调用 `shortest_path_post` 校验
/// A+B+C。任一对失败则整体失败。
pub fn[N : Eq + Hash, W : @core.Weight] johnson_post(
  pairs : Array[(N, N)],
  lookup : (N, N) -> (Array[N], W)?,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  all_pairs_post(pairs, lookup, successors, edge_weight, nodes)
}

///|
/// `floyd_warshall_post` —— Floyd–Warshall 全对最短路后置条件谓词。
///
/// Floyd–Warshall 以三重松弛求全对最短路，结果同样以 `lookup` 闭包表达。
/// 后置条件与 `johnson_post` 一致：逐对化归为单源单目标问题并调用
/// `shortest_path_post`。两者共用 `all_pairs_post` 聚合骨架，避免重复。
pub fn[N : Eq + Hash, W : @core.Weight] floyd_warshall_post(
  pairs : Array[(N, N)],
  lookup : (N, N) -> (Array[N], W)?,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  all_pairs_post(pairs, lookup, successors, edge_weight, nodes)
}

///|
/// `all_pairs_post` —— 全对最短路聚合骨架（johnson / floyd_warshall 共用）。
///
/// 对 `pairs` 中每个有序对 `(s, t)`：取 `lookup(s, t)` 作为该对的最短路结果，
/// 以目标谓词 `n == t` 调用 `shortest_path_post` 校验 A（路径合法 + 末节点为
/// `t`）+ B（代价自洽）+ C（None ⟺ `t` 从 `s` 不可达）。所有对均通过才返回
/// `true`。纯函数，不修改任何入参。
pub fn[N : Eq + Hash, W : @core.Weight] all_pairs_post(
  pairs : Array[(N, N)],
  lookup : (N, N) -> (Array[N], W)?,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  let mut i = 0
  while i < pairs.length() {
    let (s, t) = pairs[i]
    let goal = fn(n : N) -> Bool { n == t }
    if !shortest_path_post(
        lookup(s, t),
        s,
        goal,
        successors,
        edge_weight,
        nodes,
      ) {
      return false
    }
    i += 1
  }
  true
}
