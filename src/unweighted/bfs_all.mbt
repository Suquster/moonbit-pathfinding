// Single-source BFS producing the full distance and parent tables.
//
// Complements the goal-directed `bfs`: instead of stopping at the first goal
// node, it visits every reachable node, enabling cheap repeated path queries
// from one fixed source on unweighted graphs.

///|
/// Result of a full single-source BFS: hop counts and the BFS tree encoded
/// as a parent map.
pub struct BfsTree[N] {
  /// Source node the tree is rooted at.
  source : N
  /// `dist[v]` = number of edges from `source` to `v` (absent ⇒ unreachable).
  dist : Map[N, Int]
  /// `parent[v]` = predecessor of `v` on a shortest path (absent for `source`).
  parent : Map[N, N]
}

///|
/// Compute hop distances from `start` to **every** reachable node.
///
/// ## Parameters
/// - `start`: source node
/// - `successors`: function returning the neighbors of a node
///
/// ## Returns
/// A `BfsTree` with the hop-count table and the parent map.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] bfs_all(
  start : N,
  successors : (N) -> Array[N],
) -> BfsTree[N] {
  let dist : Map[N, Int] = Map([])
  let parent : Map[N, N] = Map([])
  let queue : Array[N] = [start]
  dist[start] = 0
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    let du = dist.get(u).unwrap_or(0)
    for v in successors(u) {
      if dist.get(v) is None {
        dist[v] = du + 1
        parent[v] = u
        queue.push(v)
      }
    }
  }
  { source: start, dist, parent }
}

///|
/// Extract the shortest (fewest-edge) path from the tree's source to
/// `target`, or `None` when `target` was unreachable.
///
/// ## Complexity
/// Time: O(path length). Space: O(path length).
pub fn[N : Eq + Hash] BfsTree::path_to(
  self : BfsTree[N],
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
/// Hop count from the tree's source to `target`, or `None` when unreachable.
pub fn[N : Eq + Hash] BfsTree::distance_to(
  self : BfsTree[N],
  target : N,
) -> Int? {
  self.dist.get(target)
}
