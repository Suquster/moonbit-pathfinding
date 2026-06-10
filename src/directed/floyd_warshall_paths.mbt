// Floyd-Warshall with path reconstruction via a next-hop table.
//
// Reference: Floyd, R. W. (1962). "Algorithm 97: Shortest Path".
// Communications of the ACM. 5 (6): 345.

///|
/// All-pairs shortest-path result with route reconstruction support.
pub struct AllPairs[N, W] {
  /// `dist[(u, v)]` = shortest distance (infinity ⇒ unreachable).
  dist : Map[(N, N), W]
  /// `next[(u, v)]` = the node following `u` on a shortest path to `v`.
  next : Map[(N, N), N]
}

///|
/// Compute shortest distances **and** a next-hop table between every pair of
/// nodes in a weighted directed graph. Supports negative edge weights
/// (without negative cycles).
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `edges`: list of `(u, v, weight)` directed edges
///
/// ## Returns
/// An `AllPairs` with the distance map and next-hop map; use
/// `AllPairs::path` to reconstruct routes.
///
/// ## Complexity
/// Time: O(V^3). Space: O(V^2).
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] floyd_warshall_paths(
  nodes : Array[N],
  edges : Array[(N, N, W)],
) -> AllPairs[N, W] {
  let zero = @core.Weight::zero()
  let inf = @core.Weight::infinity()
  let n = nodes.length()
  if n == 0 {
    return { dist: Map([]), next: Map([]) }
  }
  let index : Map[N, Int] = Map([])
  for i in 0..<n {
    index[nodes[i]] = i
  }
  let dist : Array[W] = Array::make(n * n, inf)
  // next_hop[i * n + j] = index of the node after i on a shortest i→j path,
  // or -1 when no path is known.
  let next_hop : Array[Int] = Array::make(n * n, -1)
  for i in 0..<n {
    dist[i * n + i] = zero
    next_hop[i * n + i] = i
  }
  for edge in edges {
    let (u, v, w) = edge
    match (index.get(u), index.get(v)) {
      (Some(iu), Some(iv)) => {
        let pos = iu * n + iv
        if w < dist[pos] {
          dist[pos] = w
          next_hop[pos] = iv
        }
      }
      _ => ()
    }
  }
  for k in 0..<n {
    for i in 0..<n {
      let dik = dist[i * n + k]
      if dik == inf {
        continue
      }
      for j in 0..<n {
        let dkj = dist[k * n + j]
        if dkj != inf {
          let candidate = @core.Weight::add(dik, dkj)
          if candidate < dist[i * n + j] {
            dist[i * n + j] = candidate
            next_hop[i * n + j] = next_hop[i * n + k]
          }
        }
      }
    }
  }
  let dist_out : Map[(N, N), W] = Map([])
  let next_out : Map[(N, N), N] = Map([])
  for i in 0..<n {
    for j in 0..<n {
      dist_out[(nodes[i], nodes[j])] = dist[i * n + j]
      let nh = next_hop[i * n + j]
      if nh >= 0 {
        next_out[(nodes[i], nodes[j])] = nodes[nh]
      }
    }
  }
  { dist: dist_out, next: next_out }
}

///|
/// Reconstruct a shortest path from `from` to `to`, or `None` when
/// unreachable.
///
/// ## Complexity
/// Time: O(path length). Space: O(path length).
pub fn[N : Eq + Hash, W] AllPairs::path(
  self : AllPairs[N, W],
  from : N,
  to : N,
) -> Array[N]? {
  if self.next.get((from, to)) is None {
    return None
  }
  let path = [from]
  let mut node = from
  while node != to {
    match self.next.get((node, to)) {
      Some(nh) => {
        node = nh
        path.push(node)
      }
      None => return None
    }
  }
  Some(path)
}

///|
/// Shortest distance from `from` to `to`, or `None` when the pair is
/// unknown (node not in the graph).
pub fn[N : Eq + Hash, W] AllPairs::distance(
  self : AllPairs[N, W],
  from : N,
  to : N,
) -> W? {
  self.dist.get((from, to))
}
