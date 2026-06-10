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
