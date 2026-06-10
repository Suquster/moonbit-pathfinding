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
  let dist : Map[N, W] = Map::new()
  dist[start] = @core.Weight::zero()
  // Relax |V| - 1 times.
  let v_count = nodes.length()
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
