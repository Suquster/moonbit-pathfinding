// spanning_connectivity_proof.mbt — 生成树与连通性族证明谓词（任务 11.3）。
//
// 本文件为「生成树（kruskal/prim）」与「连通性（connected_components /
// tarjan_scc / bridges / condensation）」两族图算法提供 ≥1 条后置条件谓词，
// 作为 30 算法证明基座（Requirement 9.1 / 9.2）的结构化补强。
//
// 设计原则（与 predicates.mbt / bfs_proof.mbt 一致）：
//   * 每条不变量编码为一个返回 `Bool` 的 `pub fn`，纯且全（total）：
//     只读取入参（节点数、边集、标签数组），从不就地修改，便于 `moon prove`
//     未来直接引用，也便于运行时 PBT 交叉验证。
//   * 结构化数据以**精确类型**表示：边集为 `Array[(Int, Int, Int)]`（带权）
//     或 `Array[(Int, Int)]`（无权），标签为 `Array[Int]`；**禁止字符串模拟**。
//   * **不 import 任何算法包**——并查集、可达性闭包、拓扑判环均在本文件内
//     用纯 `Array` / `Map` 自实现，仅复用 `@core`（包级依赖）。
//   * 结构计算可含循环，但**绝不**做循环内字符串累加（无 O(n²) 拼接）。
//
// 谓词清单：
//   生成树族（kruskal/prim）   —— `mst_post`
//   连通分量划分（connected_components） —— `components_partition_post`
//   强连通分量（tarjan_scc）   —— `scc_partition_post`
//   桥（bridges）             —— `edge_is_bridge` / `bridges_post`
//   缩点 DAG（condensation）   —— `condensation_is_dag`

// ---------------------------------------------------------------------------
// 内部并查集（union-find）—— 仅用纯 Array 实现，供生成树/连通分量谓词复用。
// ---------------------------------------------------------------------------

///|
/// `uf_make(n)` —— 创建 `n` 个独立集合的并查集父指针数组（`parent[i] == i`）。
fn uf_make(n : Int) -> Array[Int] {
  let parent = Array::make(n, 0)
  let mut i = 0
  while i < n {
    parent[i] = i
    i += 1
  }
  parent
}

///|
/// `uf_find(parent, x)` —— 带路径压缩的代表元查找（迭代实现，避免递归）。
fn uf_find(parent : Array[Int], x : Int) -> Int {
  let mut root = x
  while parent[root] != root {
    root = parent[root]
  }
  // 路径压缩：把沿途节点直接挂到根，保持谓词调用的近线性复杂度。
  let mut cur = x
  while parent[cur] != root {
    let next = parent[cur]
    parent[cur] = root
    cur = next
  }
  root
}

///|
/// `uf_union(parent, a, b)` —— 合并两元素所在集合；返回 `true` 表示本次确实
/// 合并了两个**不同**集合，返回 `false` 表示二者原本已同集合（即构成环）。
fn uf_union(parent : Array[Int], a : Int, b : Int) -> Bool {
  let ra = uf_find(parent, a)
  let rb = uf_find(parent, b)
  if ra == rb {
    return false
  }
  parent[ra] = rb
  true
}

///|
/// `in_range(x, n)` —— 节点编号合法性：`0 <= x < n`。
fn in_range(x : Int, n : Int) -> Bool {
  x >= 0 && x < n
}

// ---------------------------------------------------------------------------
// 内部有向可达性闭包 —— 供 SCC 谓词复用（有界 BFS 预言机）。
// ---------------------------------------------------------------------------

///|
/// `build_adj(n, edges)` —— 由有向边集构建邻接表（越界边将由调用方先行排除）。
fn build_adj(n : Int, edges : Array[(Int, Int)]) -> Array[Array[Int]] {
  let adj : Array[Array[Int]] = Array::make(n, [])
  let mut i = 0
  while i < n {
    adj[i] = []
    i += 1
  }
  for e in edges {
    let (u, v) = e
    adj[u].push(v)
  }
  adj
}

///|
/// `reachable_directed(adj, src, dst, n)` —— 有界 BFS 判定有向图中 `src` 能否
/// 到达 `dst`；访问标记保证每节点至多入队一次，至多迭代 `n` 个节点而终止。
fn reachable_directed(
  adj : Array[Array[Int]],
  src : Int,
  dst : Int,
  n : Int,
) -> Bool {
  if src == dst {
    return true
  }
  let visited = Array::make(n, false)
  visited[src] = true
  let queue : Array[Int] = [src]
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for w in adj[u] {
      if w == dst {
        return true
      }
      if !visited[w] {
        visited[w] = true
        queue.push(w)
      }
    }
  }
  false
}

// ---------------------------------------------------------------------------
// 生成树族谓词（kruskal / prim）—— Requirement 9.1 / 9.2
// ---------------------------------------------------------------------------

///|
/// `mst_post(n, tree_edges)` —— **生成树不变量谓词**：给定节点数 `n`（节点编号
/// `0..n-1`）与结果边集 `tree_edges`（每条为 `(u, v, w)`，`w` 为权重），当且仅当
/// `tree_edges` 构成 `n` 个节点上的一棵生成树时返回 `true`。
///
/// 判定语义（三者联立即生成树，互为充要的冗余校验以增强鲁棒性）：
///   1. **边数 == V - 1**：`tree_edges.length() == n - 1`（`n == 0` 时要求空边集）；
///   2. **无环**：以并查集逐边合并，若某条边两端已同集合即出现环 ⇒ `false`；
///   3. **连通**：全部合并后所有节点同属一个集合（覆盖全部节点）。
/// 任一端点越界（`<0` 或 `>=n`）视为非法结果 ⇒ `false`。
///
/// 该谓词同时服务 Kruskal 与 Prim：两者输出均为「覆盖全部节点的无环连通边集」，
/// 与具体选边顺序无关，故共享同一后置条件。
///
/// 运行时用法示例：
///
/// ```moonbit skip
/// let tree = @directed.kruskal(n, edges)
/// assert_true(@proofs.mst_post(n, tree))
/// ```
pub fn mst_post(n : Int, tree_edges : Array[(Int, Int, Int)]) -> Bool {
  if n < 0 {
    return false
  }
  if n == 0 {
    return tree_edges.length() == 0
  }
  // (1) 边数 == V - 1。
  if tree_edges.length() != n - 1 {
    return false
  }
  let parent = uf_make(n)
  // (2) 无环：逐边合并，任一边两端已连通即为环。
  for e in tree_edges {
    let (u, v, _w) = e
    if !in_range(u, n) || !in_range(v, n) {
      return false
    }
    if !uf_union(parent, u, v) {
      return false
    }
  }
  // (3) 连通：全部节点归于同一代表元。
  let root0 = uf_find(parent, 0)
  let mut i = 1
  while i < n {
    if uf_find(parent, i) != root0 {
      return false
    }
    i += 1
  }
  true
}

///|
/// `mst_weight_le_post(n, tree_edges, reference_weight)` —— **可选最小性辅助
/// 谓词**：在 `tree_edges` 已是合法生成树的前提下，校验其权重之和不超过参考
/// 权重 `reference_weight`（例如另一棵生成树或已知 MST 权重）。
///
/// 用于「最小生成树」最小性的对拍：若被验证的树确为最小，则其权重和应 `<=`
/// 任意其它生成树的权重和。非生成树直接返回 `false`（前提不成立）。
pub fn mst_weight_le_post(
  n : Int,
  tree_edges : Array[(Int, Int, Int)],
  reference_weight : Int,
) -> Bool {
  if !mst_post(n, tree_edges) {
    return false
  }
  let mut sum = 0
  for e in tree_edges {
    let (_u, _v, w) = e
    sum += w
  }
  sum <= reference_weight
}

// ---------------------------------------------------------------------------
// 连通分量划分谓词（connected_components）—— Requirement 9.1 / 9.2
// ---------------------------------------------------------------------------

///|
/// `components_partition_post(n, labels, edges)` —— **连通分量划分谓词**：给定
/// 节点数 `n`、每节点的分量标签 `labels`（`labels[v]` 为节点 `v` 的分量号）与
/// 无向边集 `edges`，当且仅当 `labels` 恰好刻画 `edges` 诱导的连通分量划分时
/// 返回 `true`。
///
/// 判定语义：
///   1. **标签数组形态合法**：`labels.length() == n`（每个节点恰有一个标签）；
///   2. **边端同标签**：每条边 `(u, v)` 满足 `labels[u] == labels[v]`（同分量内
///      连通的必要条件）；
///   3. **标签等价于真实连通关系**：以并查集计算真实连通分量后，两节点同标签
///      当且仅当二者真实连通（同分量内连通、跨分量不连通），即 `labels` 与真实
///      划分构成双射 —— 用「根→标签」与「标签→根」两张映射校验互为单值。
/// 任一边端点越界 ⇒ `false`。
///
/// 该谓词以「等价类划分」精确表达 connected_components 的正确性，避免仅做
/// 「边端同标签」这类必要非充分的弱校验。
pub fn components_partition_post(
  n : Int,
  labels : Array[Int],
  edges : Array[(Int, Int)],
) -> Bool {
  if n < 0 {
    return false
  }
  // (1) 标签数组形态：每节点恰一个标签。
  if labels.length() != n {
    return false
  }
  // 以并查集计算真实连通分量。
  let parent = uf_make(n)
  for e in edges {
    let (u, v) = e
    if !in_range(u, n) || !in_range(v, n) {
      return false
    }
    uf_union(parent, u, v) |> ignore
  }
  // (2) 边端同标签：连通的两端必须共享标签。
  for e in edges {
    let (u, v) = e
    if labels[u] != labels[v] {
      return false
    }
  }
  // (3) 标签 ⟺ 真实连通：根与标签互为单值（双射）。
  let root_to_label : Map[Int, Int] = Map([])
  let label_to_root : Map[Int, Int] = Map([])
  let mut i = 0
  while i < n {
    let root = uf_find(parent, i)
    let lab = labels[i]
    match root_to_label.get(root) {
      Some(existing) => if existing != lab { return false }
      None => root_to_label[root] = lab
    }
    match label_to_root.get(lab) {
      Some(existing) => if existing != root { return false }
      None => label_to_root[lab] = root
    }
    i += 1
  }
  true
}

// ---------------------------------------------------------------------------
// 强连通分量谓词（tarjan_scc）—— Requirement 9.1 / 9.2
// ---------------------------------------------------------------------------

///|
/// `scc_partition_post(n, labels, edges)` —— **强连通分量划分谓词**：给定节点数
/// `n`、每节点的 SCC 标签 `labels` 与**有向**边集 `edges`，当且仅当 `labels` 恰好
/// 刻画图的强连通分量划分时返回 `true`。
///
/// 判定语义（强连通定义）：对任意两节点 `u`、`v`，
///   `labels[u] == labels[v]`  ⟺  `u` 可达 `v` **且** `v` 可达 `u`（互相可达）。
/// 即「同一 SCC 内两两互相可达，跨 SCC 不互相可达」。可达性以本文件内自实现的
/// 有界 BFS 闭包 `reachable_directed` 计算（与边权无关）。
///   1. `labels.length() == n`；
///   2. 任一边端点越界 ⇒ `false`。
///
/// 复杂度为节点对数量级的结构计算（含循环，无字符串拼接），适配谓词在 PBT 中
/// 对中小规模随机有向图的交叉验证。
pub fn scc_partition_post(
  n : Int,
  labels : Array[Int],
  edges : Array[(Int, Int)],
) -> Bool {
  if n < 0 {
    return false
  }
  if labels.length() != n {
    return false
  }
  for e in edges {
    let (u, v) = e
    if !in_range(u, n) || !in_range(v, n) {
      return false
    }
  }
  let adj = build_adj(n, edges)
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n {
      let mutual = reachable_directed(adj, i, j, n) &&
        reachable_directed(adj, j, i, n)
      let same_label = labels[i] == labels[j]
      if mutual != same_label {
        return false
      }
      j += 1
    }
    i += 1
  }
  true
}

// ---------------------------------------------------------------------------
// 桥谓词（bridges）—— Requirement 9.1 / 9.2
// ---------------------------------------------------------------------------

///|
/// `edge_is_bridge(n, edges, bu, bv)` —— **桥定义谓词**：在无向图（`edges` 视为
/// 无向边集）中，当且仅当删除指定边 `(bu, bv)` 后其两端 `bu`、`bv` 不再连通时
/// 返回 `true`（即该边是桥）。
///
/// 实现：复制邻接关系并**仅移除一条** `(bu, bv)`（含其反向 `(bv, bu)` 一次出现，
/// 以正确处理平行边——只删一份），随后以有界 BFS 判定 `bu` 是否仍可达 `bv`；
/// 不可达即为桥。端点越界或该边不存在 ⇒ `false`。
pub fn edge_is_bridge(
  n : Int,
  edges : Array[(Int, Int)],
  bu : Int,
  bv : Int,
) -> Bool {
  if !in_range(bu, n) || !in_range(bv, n) || bu == bv {
    return false
  }
  // 构建无向邻接表，移除一条目标边（两个方向各删一次出现）。
  let adj : Array[Array[Int]] = Array::make(n, [])
  let mut i = 0
  while i < n {
    adj[i] = []
    i += 1
  }
  let mut removed_forward = false
  let mut removed_backward = false
  let mut edge_present = false
  for e in edges {
    let (u, v) = e
    if !in_range(u, n) || !in_range(v, n) {
      return false
    }
    let is_target_fwd = u == bu && v == bv
    let is_target_bwd = u == bv && v == bu
    if is_target_fwd || is_target_bwd {
      edge_present = true
    }
    if is_target_fwd && !removed_forward {
      removed_forward = true
      continue
    }
    if is_target_bwd && !removed_backward {
      removed_backward = true
      continue
    }
    // 无向边：两端互相加入邻接。
    adj[u].push(v)
    adj[v].push(u)
  }
  if !edge_present {
    return false
  }
  // 删除该边后若 bu 不再可达 bv，则该边为桥。
  !reachable_directed(adj, bu, bv, n)
}

///|
/// `bridges_post(n, edges, bridge_edges)` —— **桥集合后置条件谓词**：校验
/// `bridge_edges` 中报告的每一条边都确实是桥（删除后两端不连通）。任一条不满足
/// 桥定义即返回 `false`。用于验证 `bridges` 算法输出的合法性（充分性）。
/// 对每条报告的桥，临时从图中删去该边后判定其两端是否仍连通：仍连通则说明
/// 该边非桥，谓词判 false。纯、全函数，对任意输入恒返回 `Bool`。
pub fn bridges_post(
  n : Int,
  edges : Array[(Int, Int)],
  bridge_edges : Array[(Int, Int)],
) -> Bool {
  for be in bridge_edges {
    let (u, v) = be
    if !edge_is_bridge(n, edges, u, v) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// 缩点 DAG 谓词（condensation）—— Requirement 9.1 / 9.2
// ---------------------------------------------------------------------------

///|
/// `condensation_is_dag(n, edges)` —— **缩点无环谓词**：给定缩点后图的节点数
/// `n`（每个节点代表一个 SCC）与有向边集 `edges`，当且仅当该图无环（即为 DAG）
/// 时返回 `true`。
///
/// 实现：Kahn 拓扑排序——统计入度，反复移除入度为 0 的节点；若最终成功移除全部
/// `n` 个节点则无环，否则存在环 ⇒ `false`。自环（`u == v`）直接判为有环。端点
/// 越界 ⇒ `false`。
///
/// 缩点（condensation）将每个强连通分量收缩为单点后必为 DAG，该谓词正是其核心
/// 正确性不变量。
pub fn condensation_is_dag(n : Int, edges : Array[(Int, Int)]) -> Bool {
  if n < 0 {
    return false
  }
  let indeg = Array::make(n, 0)
  let adj : Array[Array[Int]] = Array::make(n, [])
  let mut i = 0
  while i < n {
    adj[i] = []
    i += 1
  }
  for e in edges {
    let (u, v) = e
    if !in_range(u, n) || !in_range(v, n) {
      return false
    }
    if u == v {
      return false // 自环即环。
    }
    adj[u].push(v)
    indeg[v] += 1
  }
  // Kahn 拓扑排序：从入度 0 节点起逐步剥离。
  let queue : Array[Int] = []
  let mut k = 0
  while k < n {
    if indeg[k] == 0 {
      queue.push(k)
    }
    k += 1
  }
  let mut head = 0
  let mut removed = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    removed += 1
    for w in adj[u] {
      indeg[w] -= 1
      if indeg[w] == 0 {
        queue.push(w)
      }
    }
  }
  removed == n
}
