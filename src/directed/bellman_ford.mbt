// Bellman-Ford single-source shortest paths with negative-edge support
// and negative-cycle detection.
//
// Reference: Bellman, R. (1958). "On a routing problem".
// Quarterly of Applied Mathematics, 16(1), 87-90.

///|
/// Bellman-Ford: computes shortest distances from `start` to every node
/// reachable via the edges in `edges`. Supports negative edge weights and
/// detects reachable negative cycles.
///
/// ## Parameters
/// - `nodes`: complete list of nodes in the graph
/// - `edges`: list of `(u, v, weight)` directed edges
/// - `start`: source node
///
/// ## Returns
/// - `Ok(dist)` where `dist[v]` is the shortest distance from `start` to `v`
///   (unreachable nodes are absent from the map).
/// - `Err(NegativeCycle)` if a reachable negative cycle exists.
///
/// ## Complexity
/// Time: O(V * E). Space: O(V).
pub fn[N : Eq + Hash, W : @core.Weight] bellman_ford(
  nodes : Array[N],
  edges : Array[(N, N, W)],
  start : N,
) -> Result[Map[N, W], @core.PathError] {
  let dist : Map[N, W] = Map([])
  dist[start] = @core.Weight::zero()
  // Relax |V| - 1 times.
  let v_count = nodes.length()
  //
  // 循环不变式（R10.1 · Bellman-Ford 松弛主循环 · 谓词见 @proofs.bellman_ford_post）:
  //
  //   (布尔陈述) 第 k 轮松弛结束后，对任意节点 v，dist[v]（若有限）不大于「从
  //       start 出发、至多经过 k 条边」的任意游走总权；即 dist[v] 是「边数 ≤ k」
  //       受限最短距离的上界，且恒由某条实际游走见证（无负环时随 k 增大单调收敛）。
  //
  //   (初始化成立) 第 0 轮（进入循环前）dist 仅含 dist[start]=zero：start 经 0 条边
  //       的距离为 0，其余节点经 ≤0 条边不可达（视为 +∞），命题成立。
  //
  //   (迭代保持) 第 k 轮对每条边 (u,v,w) 尝试 dist[v] := min(dist[v], dist[u]+w)。
  //       若某条「边数 ≤ k」的最短游走以边 (u,v) 收尾，则其前缀是「边数 ≤ k-1」的
  //       游走、已被上一轮归纳保证 dist[u] 取到，本轮松弛使 dist[v] 取到该值；故命题
  //       对 k 保持。一轮无任何更新（changed=false）即已达不动点，可提前 break。
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
                changed = true
              }
            None => {
              dist[v] = cand
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
  // V-th iteration: if anything still improves, a negative cycle is reachable.
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
  Ok(dist)
}
