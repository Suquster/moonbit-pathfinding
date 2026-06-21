// Single-source Dijkstra producing the full distance and parent tables.
//
// Complements the goal-directed `dijkstra`: instead of stopping at the first
// goal node, it settles every reachable node, enabling cheap repeated path
// queries from one fixed source.
//
// Reference: Dijkstra, E. W. (1959). "A note on two problems in connexion
// with graphs". Numerische Mathematik, 1(1), 269-271.

///|
/// Result of a full single-source shortest-path computation: shortest
/// distances and the shortest-path tree encoded as a parent map.
pub struct ShortestPathTree[N, W] {
  /// Source node the tree is rooted at.
  source : N
  /// `dist[v]` = shortest distance from `source` to `v` (absent ⇒ unreachable).
  dist : Map[N, W]
  /// `parent[v]` = predecessor of `v` on a shortest path (absent for `source`).
  parent : Map[N, N]
}

///|
/// Compute shortest distances from `start` to **every** reachable node using
/// Dijkstra's algorithm on non-negative edge weights.
///
/// ## Parameters
/// - `start`: source node
/// - `successors`: function returning `(neighbor, edge_weight)` pairs
///
/// ## Returns
/// A `ShortestPathTree` with the distance table and the parent map.
///
/// ## Complexity
/// Time: O((V + E) log V). Space: O(V).
pub fn[N : Eq + Hash, W : @core.Weight + Compare] dijkstra_all(
  start : N,
  successors : (N) -> Array[(N, W)],
) -> ShortestPathTree[N, W] {
  let dist : Map[N, W] = Map([])
  let parent : Map[N, N] = Map([])
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  dist[start] = zero
  pq.push(zero, start)
  //
  // 循环不变式（R10.1 · 全表 Dijkstra 主循环 · 谓词见 @proofs.dijkstra_post / dijkstra_pop_monotonic）:
  //
  //   (布尔陈述) 「按弹出顺序记录的已确定距离」单调非降；任一已被非陈旧弹出的节点 u，
  //       dist[u] 已是 start 到 u 的最终最短距离，且 parent 链见证一条对应最短路；凡
  //       dist[v] 有限者均存在 start⇝v 的实际游走。
  //
  //   (初始化成立) 进入循环前仅 (zero, start) 入队、dist[start]=zero：单元素序列单调非降，
  //       start 到自身距离 0 已最终化，parent 为空（start 无前驱）平凡见证。
  //
  //   (迭代保持) 最小堆每次弹出最小键 d；非负边权使后续松弛键 new_dist=d+w>=d，故非陈旧
  //       弹出键单调非降，弹出即定稿。松弛仅在 new_dist<现有 dist[v] 时更新 dist[v]、
  //       parent[v] 并入队，保持「有限距离有游走见证」。陈旧条目（d>dist[u]）被 continue
  //       跳过。每节点至多定稿一次，循环终止后得到完整最短路树。
  //
  while !pq.is_empty() {
    let (d, u) = pq.pop().unwrap()
    match dist.get(u) {
      Some(current) => if d > current { continue }
      None => continue
    }
    for pair in successors(u) {
      let (v, w) = pair
      let new_dist = @core.Weight::add(d, w)
      let improve = match dist.get(v) {
        Some(existing) => new_dist < existing
        None => true
      }
      if improve {
        dist[v] = new_dist
        parent[v] = u
        pq.push(new_dist, v)
      }
    }
  }
  { source: start, dist, parent }
}

///|
/// Extract the shortest path from the tree's source to `target`, or `None`
/// when `target` was unreachable.
///
/// ## Complexity
/// Time: O(path length). Space: O(path length).
pub fn[N : Eq + Hash, W] ShortestPathTree::path_to(
  self : ShortestPathTree[N, W],
  target : N,
) -> Array[N]? {
  if self.dist.get(target) is None {
    return None
  }
  let path = [target]
  let mut node = target
  while node != self.source {
    match self.parent.get(node) {
      Some(p) => {
        node = p
        path.push(node)
      }
      None => break
    }
  }
  path.rev_in_place()
  Some(path)
}

///|
/// Shortest distance from the tree's source to `target`, or `None` when
/// unreachable.
pub fn[N : Eq + Hash, W] ShortestPathTree::distance_to(
  self : ShortestPathTree[N, W],
  target : N,
) -> W? {
  self.dist.get(target)
}
