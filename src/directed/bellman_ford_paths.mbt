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
