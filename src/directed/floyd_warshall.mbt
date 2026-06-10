// Floyd-Warshall all-pairs shortest paths.
//
// Reference: Floyd, R. W. (1962). "Algorithm 97: Shortest Path".
// Communications of the ACM. 5 (6): 345.

///|
/// Compute shortest distances between every pair of nodes in a weighted
/// directed graph. Supports negative edge weights (without negative cycles).
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `edges`: list of `(u, v, weight)` directed edges
///
/// ## Returns
/// A map from `(u, v)` pairs to shortest distance. Unreachable pairs are
/// assigned `Weight::infinity()`. Self-pairs `(u, u)` are `Weight::zero()`.
///
/// ## Complexity
/// Time: O(V^3). Space: O(V^2).
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] floyd_warshall(
  nodes : Array[N],
  edges : Array[(N, N, W)],
) -> Map[(N, N), W] {
  let dist : Map[(N, N), W] = Map::new()
  let zero = @core.Weight::zero()
  let inf = @core.Weight::infinity()
  // Initialize: self-distance is zero, all other pairs are infinity.
  for u in nodes {
    for v in nodes {
      if u == v {
        dist[(u, v)] = zero
      } else {
        dist[(u, v)] = inf
      }
    }
  }
  // Apply direct edges (take the minimum in case of parallel edges).
  for edge in edges {
    let (u, v, w) = edge
    match dist.get((u, v)) {
      Some(existing) => if w < existing { dist[(u, v)] = w }
      None => dist[(u, v)] = w
    }
  }
  // Classic triple loop: k is the allowed intermediate node.
  for k in nodes {
    for i in nodes {
      for j in nodes {
        let dik = dist.get((i, k)).unwrap()
        let dkj = dist.get((k, j)).unwrap()
        let dij = dist.get((i, j)).unwrap()
        // Skip if either half is infinity (to avoid saturating add overflow).
        if dik != inf && dkj != inf {
          let candidate = @core.Weight::add(dik, dkj)
          if candidate < dij {
            dist[(i, j)] = candidate
          }
        }
      }
    }
  }
  dist
}
