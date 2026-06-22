// typed_query.mbt —— 结构化错误入口（bypass，不改既有 Option 签名）。
//
// 设计依据（design.md §「方向 4 · Property 20」/ Requirement 13）：
//   既有寻路算法以返回 `Option` 表达「有解 / 无解」，无法区分失败的具体原因。
//   本文件以「冻结既有签名 + bypass 新增入口」的方式（R13.8），提供返回
//   `Result[_, PathError]` 的结构化查询入口，把五类互斥失败映射到对应的
//   `PathError` 变体（R13.1~R13.6）。
//
// 关键架构约束（重要）：
//   `@graph` 生产代码只能依赖 `@core` / `@infra_text`，不得在生产代码中
//   import 任何具体算法包。因此本入口以 successor function 范式「自包含」实现
//   错误分类与最短路计算（包内自实现 Bellman-Ford 风格松弛，便于检测负权环），
//   不向任何算法方向包产生依赖。
//
// 不变量与需求映射：
//   * R13.2：源不在 nodes → `Err(SourceNotFound)`，全程只读、不修改输入。
//   * R13.3：目标不在 nodes → `Err(TargetNotFound)`，全程只读、不修改输入。
//   * R13.4：源与目标均在图中但目标不可达 → `Err(Unreachable)`。
//   * R13.5：源到目标的可达路径上存在负权环 → `Err(NegativeCycle)`。
//   * R13.6：非法参数（如 nodes 为空）→ `Err(InvalidArgument(...))`，全程只读。
//   * R13.8：既有返回 `Option` 的算法签名保持冻结——本文件仅新增函数。
//   * R22.4：诊断串经 `@infra_text.TextBuilder` 顺序追加，绝不在循环内 `+` 拼接。
//   * R22.6：以精确的数组 / 映射 / 元组 / 枚举表示数据，不用字符串模拟。

///|
/// 构造「nodes 为空」的非法参数诊断串（仅单次构造，无循环内拼接 · R22.4）。
fn empty_nodes_message() -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("typed query: 输入 nodes 为空，无法定位源/目标节点")
  tb.build()
}

///|
/// 结构化最短路查询入口（自包含、泛型，仅依赖 `@core` / `@infra_text`）。
///
/// 以 successor function 范式接收图结构（`successors(u)` 返回 `u` 的全部出边
/// `(目标, 权重)`），在包内自实现 Bellman-Ford 风格松弛计算源到目标的最短路，
/// 并把失败映射到对应的 `PathError` 变体。
///
/// ## 参数
/// - `nodes`：图的节点全集（界定节点空间与松弛轮数 V）。
/// - `source`：源节点；必须出现在 `nodes` 中。
/// - `target`：目标节点；必须出现在 `nodes` 中。
/// - `successors`：邻居函数，给定节点返回其出边 `(目标, 权重)` 数组。
///
/// ## 返回
/// - `Ok((path, cost))`：`path` 为从 `source` 到 `target`（含两端）的节点序列，
///   `cost` 为该路径的总权重。
/// - `Err(InvalidArgument(..))`：`nodes` 为空等非法参数（只读，不修改输入）。
/// - `Err(SourceNotFound)`：`source` 不在 `nodes` 中（只读，不修改输入）。
/// - `Err(TargetNotFound)`：`target` 不在 `nodes` 中（只读，不修改输入）。
/// - `Err(NegativeCycle)`：源到目标的可达路径上存在负权环。
/// - `Err(Unreachable)`：源与目标均在图中但目标从源不可达。
///
/// ## 复杂度
/// 时间 O(V * E)（V 轮松弛 + 一轮负权环探测 + 一次可达性 BFS）；空间 O(V)。
pub fn[N : Eq + Hash, W : @core.Weight] typed_shortest_path(
  nodes : Array[N],
  source : N,
  target : N,
  successors : (N) -> Array[(N, W)],
) -> Result[(Array[N], W), PathError] {
  // —— 阶段一：参数与端点合法性校验（只读，不修改输入 · R13.2/13.3/13.6）。 ——
  if nodes.length() == 0 {
    return Err(InvalidArgument(empty_nodes_message()))
  }
  let in_graph : Map[N, Unit] = Map([])
  for n in nodes {
    in_graph[n] = ()
  }
  if !(in_graph.get(source) is Some(_)) {
    return Err(SourceNotFound)
  }
  if !(in_graph.get(target) is Some(_)) {
    return Err(TargetNotFound)
  }
  // —— 阶段二：Bellman-Ford 风格松弛（V-1 轮 · 支持负权边）。 ——
  let dist : Map[N, W] = Map([])
  let pred : Map[N, N] = Map([])
  dist[source] = @core.Weight::zero()
  let v_count = nodes.length()
  for _round in 0..<(v_count - 1) {
    let mut changed = false
    for u in nodes {
      match dist.get(u) {
        None => ()
        Some(du) =>
          for edge in successors(u) {
            let (v, w) = edge
            // 仅考虑指向图内节点的边，保持节点空间与 `nodes` 一致。
            if in_graph.get(v) is Some(_) {
              let cand = @core.Weight::add(du, w)
              match dist.get(v) {
                None => {
                  dist[v] = cand
                  pred[v] = u
                  changed = true
                }
                Some(dv) =>
                  if cand < dv {
                    dist[v] = cand
                    pred[v] = u
                    changed = true
                  }
              }
            }
          }
      }
    }
    if !changed {
      break
    }
  }
  // —— 阶段三：第 V 轮探测——收集仍可被松弛的节点（疑似负权环影响域）。 ——
  let affected : Array[N] = []
  for u in nodes {
    match dist.get(u) {
      None => ()
      Some(du) =>
        for edge in successors(u) {
          let (v, w) = edge
          if in_graph.get(v) is Some(_) {
            let cand = @core.Weight::add(du, w)
            let still = match dist.get(v) {
              None => true
              Some(dv) => cand < dv
            }
            if still {
              affected.push(v)
            }
          }
        }
    }
  }
  // —— 阶段四：负权环是否影响目标——从影响域出发做可达性 BFS 看能否抵达 target。 ——
  if affected.length() > 0 {
    let visited : Map[N, Unit] = Map([])
    let queue : Array[N] = []
    for a in affected {
      if !(visited.get(a) is Some(_)) {
        visited[a] = ()
        queue.push(a)
      }
    }
    let mut head = 0
    let mut hit = false
    while head < queue.length() {
      let cur = queue[head]
      head = head + 1
      if cur == target {
        hit = true
        break
      }
      for edge in successors(cur) {
        let (v, _) = edge
        if in_graph.get(v) is Some(_) && !(visited.get(v) is Some(_)) {
          visited[v] = ()
          queue.push(v)
        }
      }
    }
    if hit {
      // 源到目标的可达路径上存在负权环，无法给出有限最短路（R13.5）。
      return Err(NegativeCycle)
    }
  }
  // —— 阶段五：回溯路径或判定不可达（R13.4）。 ——
  match dist.get(target) {
    None => Err(Unreachable)
    Some(cost) => {
      // 自 target 沿 pred 回溯到 source，得到逆序链，再翻转为正序路径。
      let chain : Array[N] = [target]
      let mut cur = target
      while cur != source {
        match pred.get(cur) {
          Some(p) => {
            chain.push(p)
            cur = p
          }
          None => break
        }
      }
      let path : Array[N] = []
      for i = chain.length() - 1; i >= 0; i = i - 1 {
        path.push(chain[i])
      }
      Ok((path, cost))
    }
  }
}

///|
/// 结构化无权 BFS 查询入口（自包含、泛型，仅依赖 `@core` / `@infra_text`）。
///
/// 以 successor function 范式接收图结构（`successors(u)` 返回 `u` 的后继节点
/// 数组，不带权重），用广度优先搜索求源到目标的最短跳数路径，并把失败映射到
/// 对应的 `PathError` 变体。无权 BFS 不会产生负权环，故不返回 `NegativeCycle`。
///
/// ## 参数
/// - `nodes`：图的节点全集（界定节点空间与端点合法性）。
/// - `source`：源节点；必须出现在 `nodes` 中。
/// - `target`：目标节点；必须出现在 `nodes` 中。
/// - `successors`：后继函数，给定节点返回其后继节点数组。
///
/// ## 返回
/// - `Ok((path, hops))`：`path` 为从 `source` 到 `target`（含两端）的节点序列，
///   `hops` 为路径边数（跳数，等于 `path.length() - 1`）。
/// - `Err(InvalidArgument(..))`：`nodes` 为空等非法参数（只读，不修改输入）。
/// - `Err(SourceNotFound)`：`source` 不在 `nodes` 中（只读，不修改输入）。
/// - `Err(TargetNotFound)`：`target` 不在 `nodes` 中（只读，不修改输入）。
/// - `Err(Unreachable)`：源与目标均在图中但目标从源不可达。
///
/// ## 复杂度
/// 时间 O(V + E)（一次 BFS）；空间 O(V)。
pub fn[N : Eq + Hash] typed_bfs_path(
  nodes : Array[N],
  source : N,
  target : N,
  successors : (N) -> Array[N],
) -> Result[(Array[N], Int), PathError] {
  // —— 阶段一：参数与端点合法性校验（只读，不修改输入 · R13.2/13.3/13.6）。 ——
  if nodes.length() == 0 {
    return Err(InvalidArgument(empty_nodes_message()))
  }
  let in_graph : Map[N, Unit] = Map([])
  for n in nodes {
    in_graph[n] = ()
  }
  if !(in_graph.get(source) is Some(_)) {
    return Err(SourceNotFound)
  }
  if !(in_graph.get(target) is Some(_)) {
    return Err(TargetNotFound)
  }
  // —— 阶段二：BFS 逐层扩展，记录前驱用于回溯。 ——
  let pred : Map[N, N] = Map([])
  let visited : Map[N, Unit] = Map([])
  let queue : Array[N] = [source]
  visited[source] = ()
  let mut head = 0
  let mut found = false
  while head < queue.length() {
    let cur = queue[head]
    head = head + 1
    if cur == target {
      found = true
      break
    }
    for v in successors(cur) {
      if in_graph.get(v) is Some(_) && !(visited.get(v) is Some(_)) {
        visited[v] = ()
        pred[v] = cur
        queue.push(v)
      }
    }
  }
  if !found {
    return Err(Unreachable)
  }
  // —— 阶段三：自 target 回溯到 source，翻转得到正序路径。 ——
  let chain : Array[N] = [target]
  let mut cur = target
  while cur != source {
    match pred.get(cur) {
      Some(p) => {
        chain.push(p)
        cur = p
      }
      None => break
    }
  }
  let path : Array[N] = []
  for i = chain.length() - 1; i >= 0; i = i - 1 {
    path.push(chain[i])
  }
  Ok((path, path.length() - 1))
}
