// Bellman-Ford with parent tracking for path reconstruction.
//
// Same relaxation scheme as `bellman_ford`, but additionally records the
// predecessor of each settled node so full shortest paths (not just
// distances) can be recovered, mirroring `dijkstra_all` for graphs with
// negative edges.
//
// Reference: Bellman, R. (1958). "On a routing problem".
// Quarterly of Applied Mathematics, 16(1), 87-90.

///|
/// Bellman-Ford computing a full shortest-path tree from `start`, with
/// support for negative edge weights and negative-cycle detection.
///
/// ## Parameters
/// - `nodes`: complete list of nodes in the graph
/// - `edges`: list of `(u, v, weight)` directed edges
/// - `start`: source node
///
/// ## Returns
/// - `Ok(tree)` — query it with `ShortestPathTree::path_to` and
///   `ShortestPathTree::distance_to`.
/// - `Err(NegativeCycle)` if a reachable negative cycle exists.
///
/// ## Complexity
/// Time: O(V * E). Space: O(V).
pub fn[N : Eq + Hash, W : @core.Weight] bellman_ford_paths(
  nodes : Array[N],
  edges : Array[(N, N, W)],
  start : N,
) -> Result[ShortestPathTree[N, W], @core.PathError] {
  let dist : Map[N, W] = Map([])
  let parent : Map[N, N] = Map([])
  dist[start] = @core.Weight::zero()
  let v_count = nodes.length()
  //
  // 循环不变式（R10.1 · Bellman-Ford 带路径松弛主循环 · 谓词见 @proofs.bellman_ford_post）:
  //
  //   (布尔陈述) 第 k 轮松弛后，对任意节点 v，dist[v]（若有限）不大于「从 start 出发、
  //       至多经过 k 条边」的最短游走总权，且 parent[v] 指向该游走上 v 的前驱，故沿
  //       parent 回溯可重构一条总权恰为 dist[v] 的实际路径。
  //
  //   (初始化成立) 第 0 轮（进入循环前）dist 仅含 dist[start]=zero、parent 为空：start 经
  //       0 条边距离为 0，其余不可达，路径见证平凡（start 自身）。
  //
  //   (迭代保持) 第 k 轮对每条边 (u,v,w) 尝试松弛 dist[v]:=min(dist[v], dist[u]+w)，更新时
  //       同步置 parent[v]=u。若某「边数 ≤ k」最短游走以 (u,v) 收尾，其前缀为「边数 ≤ k-1」
  //       游走、由上一轮归纳取到 dist[u]，本轮使 dist[v] 与 parent[v] 同步取到该值。一轮
  //       无更新即达不动点提前 break；第 V 轮仍可改进则报告负环。
  //
  for _ in 0..<(v_count - 1) {
    let mut changed = false
    for edge in edges {
      let (u, v, w) = edge
      match dist.get(u) {
        Some(du) => {
          let cand = @core.Weight::add(du, w)
          match dist.get(v) {
            Some(dv) =>
              if cand < dv {
                dist[v] = cand
                parent[v] = u
                changed = true
              }
            None => {
              dist[v] = cand
              parent[v] = u
              changed = true
            }
          }
        }
        None => ()
      }
    }
    if !changed {
      break
    }
  }
  // V-th iteration: any further improvement implies a negative cycle.
  for edge in edges {
    let (u, v, w) = edge
    match dist.get(u) {
      Some(du) => {
        let cand = @core.Weight::add(du, w)
        match dist.get(v) {
          Some(dv) => if cand < dv { return Err(NegativeCycle) }
          None => return Err(NegativeCycle)
        }
      }
      None => ()
    }
  }
  Ok({ source: start, dist, parent })
}
