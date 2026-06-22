// advanced_ext.mbt —— 前沿算法（CH / JPS / ALT）生产级能力补全的「新增入口」
// （tasks.md 19.1 · Requirement 8.1 生产级 / 8.6 API 冻结 + bypass）。
//
// 设计原则（steering · R8.6）：
//   既有公开签名 `ch_preprocess` / `ch_query` / `jps` / `alt_preprocess` /
//   `alt_query` **一律冻结、不得修改**；本文件仅以**新增 pub 函数**的方式补强
//   生产可用能力（bypass），`.mbti` 只增不减。
//
// 本文件提供两类新增能力：
//   1. **可控预处理入口**（生产路网常见需求——预计算的收缩顺序 / 地标集）：
//        * `ch_preprocess_with_order`     —— 以调用方给定的收缩顺序构建 CH。
//        * `alt_preprocess_with_landmarks` —— 以调用方给定的地标集构建 ALT。
//      二者对非法输入（越界 / 重复 / 缺失）做**防御性归一化**而非崩溃（R8.1）。
//   2. **批量查询入口**（一次预处理、多次查询的高频场景）：
//        * `ch_query_batch` / `alt_query_batch` / `jps_batch`。
//      批量入口严格复用已冻结的单次查询函数，逐对求解、保持语义一致。
//
// 质量约束（steering）：全函数实现、无 abort/todo!/panic 占位；精确类型表示
//   结构化数据；循环内不做字符串 `+` 拼接；全程中文注释、`///|` 块风格。

///|
/// CH 预处理（**调用方指定收缩顺序** · bypass 新增入口）。
///
/// 与 `ch_preprocess`（按 edge-difference 启发式动态定序）不同，本入口严格
/// 按调用方给定的 `order` 序列依次收缩节点——这是生产路网中「离线预计算高质量
/// 收缩顺序、在线复用」的标准用法（Geisberger et al. 2008 §5）。
///
/// **防御性归一化（R8.1，绝不崩溃）**：`order` 不必是 `nodes` 的精确排列。
///   * 仅保留既属于 `nodes`、又未重复出现的标识，按其在 `order` 中的首次出现
///     顺序收缩；
///   * 对 `order` 未覆盖的节点，按其在 `nodes` 中的原始顺序追加到末尾收缩。
///   这样无论调用方传入部分 / 含越界 / 含重复的顺序，每个节点都恰好被收缩一次，
///   产出的 `CHGraph` 始终合法、可供 `ch_query` 正确查询。
///
/// 返回与 `ch_preprocess` 同构的 `CHGraph`，可直接交给冻结的 `ch_query` 使用。
pub fn[N : Eq + Hash, W : @core.Weight + Compare] ch_preprocess_with_order(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
  order : Array[N],
) -> CHGraph[N, W] {
  // 归一化收缩序列：先采纳合法且未重复的 order 项，再补齐遗漏节点。
  let node_set : Map[N, Bool] = Map([])
  for n in nodes {
    node_set[n] = true
  }
  let seen : Map[N, Bool] = Map([])
  let seq : Array[N] = []
  for n in order {
    if node_set.get(n).unwrap_or(false) && !seen.get(n).unwrap_or(false) {
      seen[n] = true
      seq.push(n)
    }
  }
  for n in nodes {
    if !seen.get(n).unwrap_or(false) {
      seen[n] = true
      seq.push(n)
    }
  }
  // 复用与 ch_preprocess 完全一致的收缩与建图原语，确保两入口逐步行为相同。
  let level : Map[N, Int] = Map([])
  let shortcut : Map[(N, N), N] = Map([])
  let (residual, rev_residual) = ch_init_residual(nodes, successors)
  let contracted : Map[N, Bool] = Map([])
  let mut next_level = 0
  for v in seq {
    level[v] = next_level
    next_level += 1
    ch_contract_node(v, residual, rev_residual, contracted, shortcut)
  }
  let (up_adj, dn_adj) = ch_build_adjacency(nodes, level, residual)
  { nodes, level, up_adj, dn_adj, shortcut }
}

///|
/// ALT 预处理（**调用方指定地标集** · bypass 新增入口）。
///
/// 与 `alt_preprocess`（farthest-first 自动选地标）不同，本入口直接采用调用方
/// 给定的 `landmarks`——便于复用领域知识（如选取路网枢纽 / 出入口作为地标），
/// 或在评测中固定地标集以保证可复现。
///
/// **防御性归一化（R8.1）**：仅保留既属于 `nodes`、又未重复的地标标识（按首次
/// 出现顺序）；越界或重复地标被忽略而非报错。地标集为空时退化为零启发式
/// （等价于 Dijkstra），仍返回合法 `Landmark` 结构。
///
/// 返回与 `alt_preprocess` 同构的 `Landmark`，可直接交给冻结的 `alt_query`。
pub fn[N : Eq + Hash, W : @core.Weight + Compare] alt_preprocess_with_landmarks(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
  landmarks : Array[N],
) -> Landmark[N, W] {
  let node_set : Map[N, Bool] = Map([])
  for n in nodes {
    node_set[n] = true
  }
  let seen : Map[N, Bool] = Map([])
  let chosen : Array[N] = []
  for l in landmarks {
    if node_set.get(l).unwrap_or(false) && !seen.get(l).unwrap_or(false) {
      seen[l] = true
      chosen.push(l)
    }
  }
  let (dist_from, dist_to) = alt_build_tables(nodes, successors, chosen)
  { nodes, landmarks: chosen, dist_from, dist_to }
}

///|
/// CH 批量查询（bypass 新增入口）：在同一预处理图上对多组 `(source, target)`
/// 依次查询，返回与 `pairs` 等长、逐位对应的结果数组。每个元素语义与单次
/// `ch_query` 完全一致（`Some((path, cost))` 或 `None`）。
///
/// 严格复用已冻结的 `ch_query`，因此批量结果与逐个调用 `ch_query` 逐位相同
/// （生产场景：一次预处理、海量点对查询，避免重复预处理开销）。
pub fn[N : Eq + Hash, W : @core.Weight + Compare] ch_query_batch(
  graph : CHGraph[N, W],
  pairs : Array[(N, N)],
) -> Array[(Array[N], W)?] {
  let out : Array[(Array[N], W)?] = []
  for p in pairs {
    let (s, t) = p
    out.push(ch_query(graph, s, t))
  }
  out
}

///|
/// ALT 批量查询（bypass 新增入口）：在同一地标预处理上对多组 `(start, goal)`
/// 依次查询。逐位结果与单次 `alt_query` 一致。`successors` 与预处理所用的后继
/// 函数应一致，方能保证启发式可采纳性。
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] alt_query_batch(
  lm : Landmark[N, W],
  pairs : Array[(N, N)],
  successors : (N) -> Array[(N, W)],
) -> Array[(Array[N], W)?] {
  let out : Array[(Array[N], W)?] = []
  for p in pairs {
    let (s, t) = p
    out.push(alt_query(lm, s, t, successors))
  }
  out
}

///|
/// JPS 批量查询（bypass 新增入口）：在同一网格上对多组 `(start, goal)` 依次
/// 运行 Jump Point Search。逐位结果与单次 `jps` 一致（`Some((path, cost))`
/// 或 `None`）。生产场景：同一静态地图上的多智能体 / 多目标寻路。
pub fn jps_batch(
  grid : JPSGrid,
  pairs : Array[((Int, Int), (Int, Int))],
) -> Array[(Array[(Int, Int)], Double)?] {
  let out : Array[(Array[(Int, Int)], Double)?] = []
  for p in pairs {
    let (s, g) = p
    out.push(jps(grid, s, g))
  }
  out
}
