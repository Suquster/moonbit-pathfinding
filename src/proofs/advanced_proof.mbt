// advanced_proof.mbt —— 加速算法族（预处理型最短路）的后置条件谓词。
//
// 本文件为 `src/advanced`（以及 `src/directed` 的生产级同名实现）中的
// 预处理型加速算法——Contraction Hierarchies (CH)、Customizable CH (CCH)、
// ALT（A* + Landmarks + Δ）、Hub Labeling (HL)、PHAST、(R)PHAST、
// many-to-many、Jump Point Search (JPS)——各提供后置条件谓词。
//
// 设计约束（与 shortest_path_family_proof.mbt 一致）：
//   * proofs 生产代码**仅依赖 @core**；本文件不 import 任何算法包，谓词只接收
//     `result` + successor/edge_weight 闭包做**纯验证**，与真实算法的交叉验证
//     由测试任务承担。
//   * 加速算法的对外契约仍是「返回一条合法且代价自洽的最短路」，故其单点查询
//     后置条件是 `shortest_path_post` 的语义特化薄封装（A 路径合法 + B 代价
//     一致 + C none-witness），与 astar_post / bidirectional_dijkstra_post 同构。
//   * 加速算法**独有**的核心不变量是「与朴素基线（Dijkstra）等价」：预处理引入
//     shortcut / 势函数 / 标签后，查询结果的**代价**必须与无预处理的参考实现
//     逐对相等（路径可因并列而不同，代价不可）。该正确性护栏由本文件新增的
//     `cost_agrees_with_reference` / `batch_cost_agrees` 谓词表述。

///|
/// `ch_query_post` —— Contraction Hierarchies 单点查询后置条件谓词。
///
/// CH 通过节点收缩预插 shortcut 边加速查询，但对外仍返回 `(Array[N], W)?`
/// 形状的最短路，后置条件与最短路族一致（A+B+C）。shortcut 的三角不等式
/// 保持属预处理内部不变量，不在结果级后置条件内表达。纯、全函数。
pub fn[N : Eq + Hash, W : @core.Weight] ch_query_post(
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
/// `cch_query_post` —— Customizable CH 单点查询后置条件谓词。
///
/// CCH 把收缩序（拓扑）与边权（度量）解耦，换权后无需重排即可重定制，但查询
/// 结果契约不变，后置条件与 CH 一致。度量定制阶段的正确性由 metric-agnostic
/// 换权后仍与 Dijkstra 等价来保证（见 `cost_agrees_with_reference`）。纯、全。
pub fn[N : Eq + Hash, W : @core.Weight] cch_query_post(
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
/// `alt_query_post` —— ALT（A* + Landmarks + 三角不等式）单点查询后置条件。
///
/// ALT 用地标预计算的距离经三角不等式导出可采纳（admissible）下界启发式，
/// 加速 A* 而不牺牲最优性，故结果与 A* 同形、后置条件一致（A+B+C）。地标
/// 下界的可采纳性属启发式内部性质，由「与 Dijkstra 代价等价」间接护栏。纯、全。
pub fn[N : Eq + Hash, W : @core.Weight] alt_query_post(
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
/// `hub_labeling_post` —— Hub Labeling (2-hop) 单点查询后置条件谓词。
///
/// HL 为每个节点预存前向/后向标签，查询时对两侧标签做有序归并取最小和。其
/// 返回的最短路仍满足最短路族后置条件（A+B+C）；2-hop cover 性质（任意
/// 最短路必经某公共 hub）属标签构造不变量，由「与 Dijkstra 代价等价」护栏。纯、全。
pub fn[N : Eq + Hash, W : @core.Weight] hub_labeling_post(
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
/// `jps_post` —— Jump Point Search（栅格跳点搜索）单点查询后置条件谓词。
///
/// JPS 在均匀代价栅格上用对称性剪枝跳过中间节点，只在跳点扩展，但返回的仍是
/// 一条合法且代价自洽的最短路（栅格节点为 `(Int, Int)`）。剪枝规则的正确性
/// （跳点保留最优性）由「与栅格 A*/Dijkstra 代价等价」护栏。纯、全函数。
pub fn[W : @core.Weight] jps_post(
  result : (Array[(Int, Int)], W)?,
  start : (Int, Int),
  goal : ((Int, Int)) -> Bool,
  successors : ((Int, Int)) -> Array[((Int, Int), W)],
  edge_weight : ((Int, Int), (Int, Int)) -> W?,
  nodes : Array[(Int, Int)],
) -> Bool {
  shortest_path_post(result, start, goal, successors, edge_weight, nodes)
}

///|
/// `cost_agrees_with_reference(fast, reference)` —— 加速算法**独有**的核心
/// 正确性不变量：预处理型算法的查询结果与朴素参考实现（Dijkstra）逐对**代价
/// 相等**。
///
/// 判定语义（只比较代价，不比较路径——并列最短路可有不同节点序列，但代价唯一）：
///   * 两者均 `None`（都判不可达）⟹ 一致，真；
///   * 两者均 `Some`，当且仅当代价相等 ⟹ 真；
///   * 一方 `Some` 一方 `None`（可达性判定分歧）⟹ 假。
///
/// 这是 CH/CCH/ALT/HL/PHAST/JPS 等一切「用预处理换查询速度」算法的最强正确性
/// 护栏：无论 shortcut、势函数、标签、跳点如何加速，输出的最短距离必须与无
/// 预处理的定义式实现完全一致。纯、全函数，对任意两结果恒返回 `Bool`。
pub fn[N, W : @core.Weight] cost_agrees_with_reference(
  fast : (Array[N], W)?,
  reference : (Array[N], W)?,
) -> Bool {
  match (fast, reference) {
    (None, None) => true
    (Some((_, cf)), Some((_, cr))) => cf == cr
    _ => false
  }
}

///|
/// `batch_cost_agrees(fast, reference)` —— 批量查询版的代价等价护栏。
///
/// 对 many-to-many / (R)PHAST / *_query_batch 这类**批量**接口：逐对校验
/// `fast[i]` 与 `reference[i]` 的代价一致（复用 `cost_agrees_with_reference`）。
/// 长度不等即判失败（批量结果必须与参考一一对应）。任一对分歧则整体失败。
/// 纯、全函数，对任意两结果数组恒返回 `Bool`。
pub fn[N, W : @core.Weight] batch_cost_agrees(
  fast : Array[(Array[N], W)?],
  reference : Array[(Array[N], W)?],
) -> Bool {
  if fast.length() != reference.length() {
    return false
  }
  let mut i = 0
  while i < fast.length() {
    if !cost_agrees_with_reference(fast[i], reference[i]) {
      return false
    }
    i += 1
  }
  true
}
