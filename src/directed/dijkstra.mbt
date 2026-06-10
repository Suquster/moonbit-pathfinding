// Dijkstra's single-source shortest-path algorithm for non-negative weights.
//
// Uses a binary min-heap priority queue with lazy deletion of stale entries.
//
// Reference: Dijkstra, E. W. (1959). "A note on two problems in connexion
// with graphs". Numerische Mathematik, 1(1), 269-271.

///|
/// Shortest path from `start` to the first node satisfying `goal`, using
/// Dijkstra's algorithm on non-negative edge weights.
///
/// Loop invariants (for future `moon prove` integration):
///   1. Every popped node has its final shortest distance assigned to `dist`.
///   2. For any node `v` with `dist[v] < infinity`, there exists a walk from
///      `start` to `v` of total weight `dist[v]`.
///   3. With all edge weights >= zero(), every dist value is >= zero().
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: function returning `(neighbor, edge_weight)` pairs
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// `Some((path, total_cost))` if reachable, `None` otherwise.
///
/// ## Complexity
/// Time: O((V + E) log V). Space: O(V).
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] dijkstra(
  start : N,
  successors : (N) -> Array[(N, W)],
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let dist : Map[N, W] = Map::new()
  let parents : Map[N, N] = Map::new()
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  dist[start] = zero
  pq.push(zero, start)
  while !pq.is_empty() {
    let (d, u) = pq.pop().unwrap()
    // Skip stale entries: the popped distance may be worse than a later update.
    match dist.get(u) {
      Some(current) => if d > current { continue }
      None => continue
    }
    /// invariant: after this point `d == dist[u]` and `dist[u]` is the final
    ///            shortest distance from `start` to `u` — no future relaxation
    ///            can improve it (proof: heap yields non-decreasing keys and
    ///            edge weights are non-negative). Anchor for M4 `moon prove`.
    if goal(u) {
      // Reconstruct path.
      let path = [u]
      let mut node = u
      while node != start {
        match parents.get(node) {
          Some(p) => {
            node = p
            path.push(node)
          }
          None => break
        }
      }
      path.rev_in_place()
      return Some((path, d))
    }
    for pair in successors(u) {
      let (v, w) = pair
      let new_dist = @core.Weight::add(d, w)
      /// invariant: `new_dist >= zero()` because `d >= zero()` holds for every
      ///            popped entry and all edge weights `w >= zero()` by the
      ///            Dijkstra precondition (Weight::add preserves non-negativity
      ///            for non-negative operands). Anchor for M4 `moon prove`.
      let improve = match dist.get(v) {
        Some(existing) => new_dist < existing
        None => true
      }
      if improve {
        /// invariant: whenever `dist[v] < infinity` becomes true, a concrete
        ///            walk `start ⇝ u → v` of total weight `new_dist` exists,
        ///            witnessed by `parents` chain set on the next line.
        ///            Anchor for M4 `moon prove` reachability lemma.
        dist[v] = new_dist
        parents[v] = u
        pq.push(new_dist, v)
      }
    }
  }
  None
}
