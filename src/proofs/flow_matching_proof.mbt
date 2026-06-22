// flow_matching_proof.mbt —— 流与匹配 / 拓扑 / 欧拉族后置条件谓词（R9.1/R9.2）。
//
// 覆盖算法族：edmonds_karp / dinic / min_cut / min_cost_flow /
// hopcroft_karp / kuhn_munkres / eulerian / topo_sort。
//
// 设计约定（与 predicates.mbt 一致）：
//   * 全部谓词 **纯且全（total）**：只读取入参、返回 Bool，从不就地修改
//     调用方传入的 Array / Map（内部使用的临时表为本地新建），故对故意构造
//     的 Bad_Witness（违反后置条件的输入）必判 false 且不破坏入参（R9.6）；
//   * 以 **精确类型** 表示流网络与匹配：容量 / 流量 / 单位费用为 Array[Int]，
//     边集为 Array[(Int, Int)]，匹配为 Array[(Int, Int)]，拓扑 / 欧拉序为
//     Array[Int]——禁止字符串模拟结构化数据；
//   * 不 import 任何算法包，仅依赖 @core（经 moon.pkg）与标准库 Map / Array；
//   * 边索引语义：capacity[e] / flow[e] / unit_cost[e] 与 edges[e] 对齐，
//     edges[e] = (起点, 终点) 表示一条有向边。

///|
/// `max_flow_valid` —— 最大流合法性谓词（edmonds_karp / dinic）。
///
/// 当且仅当给定流量分配同时满足以下三项时判定为真，否则为假：
///   1. **容量约束**：对每条边 e，`0 <= flow[e] <= capacity[e]`；
///   2. **流守恒**：对每个非源非汇节点 n，入流 == 出流（净流量为 0）；
///   3. **流值一致**：源点净出流 == `flow_value`，且汇点净入流 == `flow_value`
///      （后者为守恒的推论，显式校验更稳健）。
///
/// 入参长度 / 下标越界 / 源汇非法等结构性问题均判 false 以保持谓词总。
pub fn max_flow_valid(
  num_nodes : Int,
  edges : Array[(Int, Int)],
  capacity : Array[Int],
  flow : Array[Int],
  source : Int,
  sink : Int,
  flow_value : Int,
) -> Bool {
  let m = edges.length()
  // 数组长度必须与边数对齐。
  if capacity.length() != m || flow.length() != m {
    return false
  }
  if num_nodes <= 0 {
    return false
  }
  if source < 0 || source >= num_nodes || sink < 0 || sink >= num_nodes {
    return false
  }
  if source == sink {
    return false
  }
  // 容量约束 + 非负。
  let mut i = 0
  while i < m {
    if flow[i] < 0 || flow[i] > capacity[i] {
      return false
    }
    i += 1
  }
  // 计算各节点净流量（出流 - 入流）。
  let net = Array::make(num_nodes, 0)
  let mut e = 0
  while e < m {
    let (u, v) = edges[e]
    if u < 0 || u >= num_nodes || v < 0 || v >= num_nodes {
      return false
    }
    net[u] = net[u] + flow[e]
    net[v] = net[v] - flow[e]
    e += 1
  }
  // 流守恒：非源非汇节点净流量必须为 0。
  let mut n = 0
  while n < num_nodes {
    if n != source && n != sink && net[n] != 0 {
      return false
    }
    n += 1
  }
  // 流值一致：源点净出流 == flow_value，汇点净入流 == flow_value。
  net[source] == flow_value && net[sink] == -flow_value
}

///|
/// `max_flow_equals_min_cut` —— 最大流 = 最小割谓词（min_cut）。
///
/// `source_side[n]` 为 true 表示节点 n 落在割的源侧。当且仅当：
///   1. 割合法：源点在源侧、汇点在汇侧；
///   2. 该割的容量（所有由源侧指向汇侧的边的容量之和）== `max_flow_value`
/// 时判定为真。下标越界 / 长度不符判 false。
///
/// 据最大流最小割定理，最大流值等于最小割容量；本谓词校验给定割的容量与
/// 算法给出的最大流值一致。
pub fn max_flow_equals_min_cut(
  num_nodes : Int,
  edges : Array[(Int, Int)],
  capacity : Array[Int],
  source_side : Array[Bool],
  source : Int,
  sink : Int,
  max_flow_value : Int,
) -> Bool {
  let m = edges.length()
  if capacity.length() != m {
    return false
  }
  if source_side.length() != num_nodes {
    return false
  }
  if source < 0 || source >= num_nodes || sink < 0 || sink >= num_nodes {
    return false
  }
  // 割合法性：源在源侧、汇在汇侧。
  if !source_side[source] || source_side[sink] {
    return false
  }
  // 累加跨越割（源侧 → 汇侧）的边容量。
  let mut cut = 0
  let mut e = 0
  while e < m {
    let (u, v) = edges[e]
    if u < 0 || u >= num_nodes || v < 0 || v >= num_nodes {
      return false
    }
    if source_side[u] && !source_side[v] {
      cut = cut + capacity[e]
    }
    e += 1
  }
  cut == max_flow_value
}

///|
/// `min_cost_flow_valid` —— 最小费用流合法性谓词（min_cost_flow）。
///
/// 当且仅当：
///   1. 流量分配合法（守恒 + 容量约束 + 流值一致，复用 `max_flow_valid`）；
///   2. 总费用 == Σ flow[e] × unit_cost[e]
/// 时判定为真。`unit_cost` 长度须与边数一致，否则判 false。
pub fn min_cost_flow_valid(
  num_nodes : Int,
  edges : Array[(Int, Int)],
  capacity : Array[Int],
  unit_cost : Array[Int],
  flow : Array[Int],
  source : Int,
  sink : Int,
  flow_value : Int,
  total_cost : Int,
) -> Bool {
  // 流合法性（守恒 + 容量 + 流值）。
  if !max_flow_valid(num_nodes, edges, capacity, flow, source, sink, flow_value) {
    return false
  }
  if unit_cost.length() != edges.length() {
    return false
  }
  // 费用 = Σ 流量 × 单位费用。
  let mut cost = 0
  let mut i = 0
  while i < edges.length() {
    cost = cost + flow[i] * unit_cost[i]
    i += 1
  }
  cost == total_cost
}

///|
/// `matching_valid` —— 二分图匹配合法性谓词（hopcroft_karp / kuhn_munkres）。
///
/// `matching` 为匹配边集合，元素 `(l, r)` 表示左部节点 l 与右部节点 r 匹配；
/// `graph_edges` 为图中允许的边集合（同样 `(l, r)`）。当且仅当：
///   1. 每条匹配边都存在于图中；
///   2. 每个左部节点至多被匹配一次、每个右部节点至多被匹配一次
/// 时判定为真。左右节点编号空间相互独立（分别记账），故编号可重叠。
///
/// 使用嵌套 Map（Map[Int, Map[Int, Bool]]）表示边集，避免字符串拼接键。
pub fn matching_valid(
  matching : Array[(Int, Int)],
  graph_edges : Array[(Int, Int)],
) -> Bool {
  // 构造图边集合：edge_set[l] 内含所有合法右端点 r。
  let edge_set : Map[Int, Map[Int, Bool]] = Map([])
  for pair in graph_edges {
    let (u, v) = pair
    match edge_set.get(u) {
      Some(inner) => inner[v] = true
      None => {
        let inner : Map[Int, Bool] = Map([])
        inner[v] = true
        edge_set[u] = inner
      }
    }
  }
  let used_left : Map[Int, Bool] = Map([])
  let used_right : Map[Int, Bool] = Map([])
  for pair in matching {
    let (l, r) = pair
    // 匹配边必须存在于图中。
    let exists = match edge_set.get(l) {
      Some(inner) => inner.contains(r)
      None => false
    }
    if !exists {
      return false
    }
    // 每个左 / 右节点至多匹配一次。
    if used_left.contains(l) || used_right.contains(r) {
      return false
    }
    used_left[l] = true
    used_right[r] = true
  }
  true
}

///|
/// `perfect_matching_weight` —— 带权完美匹配谓词（kuhn_munkres）。
///
/// 在 `matching_valid` 基础上附加：
///   1. **完美匹配**：匹配边数 == `expected_size`（期望覆盖规模）；
///   2. **权重一致**：Σ matching_weights[i] == `total_weight`
/// 时判定为真。`matching_weights[i]` 为第 i 条匹配边 `matching[i]` 的权重，
/// 长度须与匹配边数一致，否则判 false。
pub fn perfect_matching_weight(
  matching : Array[(Int, Int)],
  graph_edges : Array[(Int, Int)],
  matching_weights : Array[Int],
  expected_size : Int,
  total_weight : Int,
) -> Bool {
  // 先校验匹配合法。
  if !matching_valid(matching, graph_edges) {
    return false
  }
  // 完美匹配：匹配边数 == 期望规模。
  if matching.length() != expected_size {
    return false
  }
  if matching_weights.length() != matching.length() {
    return false
  }
  let mut w = 0
  let mut i = 0
  while i < matching_weights.length() {
    w = w + matching_weights[i]
    i += 1
  }
  w == total_weight
}

///|
/// `topo_order_post` —— 拓扑序合法性谓词（topo_sort）。
///
/// `order` 为节点的线性排列；`edges` 中每条 `(u, v)` 表示有向边 u → v。
/// 当且仅当对每条有向边 (u, v)，u 在序中严格先于 v 时判定为真。
///
/// 序中出现重复节点、边端点不在序中均视为非法，判 false。
/// 纯、全函数，对任意排列与任意边集恒返回 `Bool`（不 abort）。
pub fn topo_order_post(order : Array[Int], edges : Array[(Int, Int)]) -> Bool {
  // 建立 节点 → 位置 的映射，重复节点判非法。
  let pos : Map[Int, Int] = Map([])
  let mut i = 0
  while i < order.length() {
    if pos.contains(order[i]) {
      return false
    }
    pos[order[i]] = i
    i += 1
  }
  // 每条边 (u, v)：u 必须先于 v。
  let mut k = 0
  while k < edges.length() {
    let (u, v) = edges[k]
    match (pos.get(u), pos.get(v)) {
      (Some(pu), Some(pv)) => if pu >= pv { return false }
      _ => return false
    }
    k += 1
  }
  true
}

///|
/// `eulerian_trail_valid` —— 欧拉路径 / 回路合法性谓词（eulerian）。
///
/// `trail` 为依次经过的节点序列；`edges` 为有向边集合（允许重边）。当且仅当：
///   1. 序列每相邻对 `(trail[i], trail[i+1])` 是图中一条尚未使用的有向边；
///   2. 恰好用尽每条边一次（即 `trail` 含 `edges.length()` 段、每段消耗一条
///      不同的可用边）
/// 时判定为真。
///
/// 边界：空边集时仅当 `trail` 至多含一个节点（无边可走）判真。使用
/// Map[Int, Map[Int, Int]] 记录每条有向边的可用重数，逐段递减消耗，自然支持
/// 重边且不修改入参。
pub fn eulerian_trail_valid(
  trail : Array[Int],
  edges : Array[(Int, Int)],
) -> Bool {
  let m = edges.length()
  // 空图：至多一个节点、无边可用。
  if m == 0 {
    return trail.length() <= 1
  }
  // 含 m 条边的欧拉路径需要恰好 m + 1 个节点。
  if trail.length() != m + 1 {
    return false
  }
  // 构造可用边重数表（本地新建，不触碰入参）。
  let avail : Map[Int, Map[Int, Int]] = Map([])
  for pair in edges {
    let (u, v) = pair
    match avail.get(u) {
      Some(inner) =>
        match inner.get(v) {
          Some(c) => inner[v] = c + 1
          None => inner[v] = 1
        }
      None => {
        let inner : Map[Int, Int] = Map([])
        inner[v] = 1
        avail[u] = inner
      }
    }
  }
  // 逐相邻对消耗一条可用边；任一段无可用边即非法。
  let mut i = 0
  while i < trail.length() - 1 {
    let u = trail[i]
    let v = trail[i + 1]
    let ok = match avail.get(u) {
      Some(inner) =>
        match inner.get(v) {
          Some(c) =>
            if c > 0 {
              inner[v] = c - 1
              true
            } else {
              false
            }
          None => false
        }
      None => false
    }
    if !ok {
      return false
    }
    i += 1
  }
  // trail 段数 == m 且每段成功消耗一条可用边，故恰好用尽每条边一次。
  true
}
