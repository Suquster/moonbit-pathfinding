// Johnson's all-pairs shortest paths for sparse graphs with negative edges.
//
// Combines one Bellman-Ford pass (to compute vertex potentials) with one
// Dijkstra run per vertex on the reweighted graph. Beats Floyd-Warshall's
// O(V^3) on sparse graphs: O(V * E log V).
//
// Uses concrete `Int` weights because reweighting requires signed
// arithmetic (`w + h[u] - h[v]`), which the saturating `Weight` trait does
// not expose.
//
// Reference: Johnson, D. B. (1977). "Efficient algorithms for shortest paths
// in sparse networks". JACM, 24(1), 1-13.

///|
/// Compute shortest distances between every pair of nodes in a directed
/// graph with possibly negative `Int` edge weights (no negative cycles).
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `edges`: list of `(u, v, weight)` directed edges
///
/// ## Returns
/// `Ok(dist)` mapping each reachable `(u, v)` pair to its shortest distance
/// (unreachable pairs are absent from the map), or `Err(NegativeCycle)` when
/// the graph contains a negative cycle.
///
/// ## Complexity
/// Time: O(V * E log V). Space: O(V^2) for the output.
pub fn[N : Eq + Hash] johnson(
  nodes : Array[N],
  edges : Array[(N, N, Int)],
) -> Result[Map[(N, N), Int], @core.PathError] {
  let n = nodes.length()
  if n == 0 {
    return Ok(Map([]))
  }
  // Bellman-Ford from a virtual source connected to every node with a
  // zero-weight edge — equivalent to starting all potentials at 0.
  let h : Map[N, Int] = Map([])
  for node in nodes {
    h[node] = 0
  }
  for _ in 0..<(n - 1) {
    let mut changed = false
    for edge in edges {
      let (u, v, w) = edge
      match (h.get(u), h.get(v)) {
        (Some(hu), Some(hv)) =>
          if hu + w < hv {
            h[v] = hu + w
            changed = true
          }
        _ => ()
      }
    }
    if !changed {
      break
    }
  }
  // One more pass: any further improvement implies a negative cycle.
  for edge in edges {
    let (u, v, w) = edge
    match (h.get(u), h.get(v)) {
      (Some(hu), Some(hv)) => if hu + w < hv { return Err(NegativeCycle) }
      _ => ()
    }
  }
  // Build the reweighted adjacency: w'(u, v) = w + h[u] - h[v] >= 0.
  let adj : Map[N, Array[(N, Int)]] = Map([])
  for node in nodes {
    adj[node] = []
  }
  for edge in edges {
    let (u, v, w) = edge
    match (h.get(u), h.get(v), adj.get(u)) {
      (Some(hu), Some(hv), Some(lst)) => lst.push((v, w + hu - hv))
      _ => ()
    }
  }
  // One Dijkstra per source on the non-negative reweighted graph.
  let out : Map[(N, N), Int] = Map([])
  for u in nodes {
    let tree = dijkstra_all(u, fn(x : N) -> Array[(N, Int)] {
      adj.get(x).unwrap_or([])
    })
    let hu = h.get(u).unwrap_or(0)
    for v in nodes {
      match tree.distance_to(v) {
        Some(dp) => {
          let hv = h.get(v).unwrap_or(0)
          out[(u, v)] = dp - hu + hv
        }
        None => ()
      }
    }
  }
  Ok(out)
}
