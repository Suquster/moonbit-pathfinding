// A* search with an admissible heuristic.
//
// Reference: Hart, P. E., Nilsson, N. J., & Raphael, B. (1968).
// "A Formal Basis for the Heuristic Determination of Minimum Cost Paths".
// IEEE Transactions on Systems Science and Cybernetics, 4(2), 100-107.

///|
/// A* shortest path from `start` to the first node satisfying `goal`,
/// using a priority queue keyed by `f(n) = g(n) + h(n)` where:
/// - `g(n)` is the known cost from `start` to `n`
/// - `h(n)` is a user-supplied heuristic estimate of remaining cost
///
/// ## Correctness
/// If `heuristic` is admissible (never overestimates), A* returns an optimal
/// path — see Hart et al. 1968 Theorem 1.
/// When `heuristic` returns `zero()` for every node, A* degenerates to
/// Dijkstra's algorithm.
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: function returning `(neighbor, edge_weight)` pairs
/// - `heuristic`: admissible estimate of remaining cost to goal
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// `Some((path, total_cost))` if reachable, `None` otherwise.
///
/// ## Complexity
/// Time: O((V + E) log V) worst case; often much better with a good heuristic.
pub fn[N : Eq + Hash, W : @core.Weight + Compare] astar(
  start : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let g_cost : Map[N, W] = Map([])
  let parents : Map[N, N] = Map([])
  // The queue payload carries the `g` value recorded when the entry was
  // pushed, so we can perform lazy deletion of superseded (stale) entries on
  // pop — avoiding redundant node re-expansions. This is the standard
  // duplicate-detection technique used by production A* implementations and
  // is correct for both consistent and merely-admissible heuristics.
  let pq : @core.PQueue[(N, W), W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  g_cost[start] = zero
  pq.push(heuristic(start), (start, zero))
  while !pq.is_empty() {
    let (_f, (u, gu_entry)) = pq.pop().unwrap()
    // Skip stale entries: if a strictly better path to `u` was discovered
    // after this entry was queued, the recorded `g` is worse than the current
    // best and this expansion would be wasted work.
    match g_cost.get(u) {
      Some(best) => if gu_entry > best { continue }
      None => continue
    }
    if goal(u) {
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
      let total = g_cost.get(u).unwrap()
      return Some((path, total))
    }
    let gu = gu_entry
    for pair in successors(u) {
      let (v, w) = pair
      let tentative = @core.Weight::add(gu, w)
      let improve = match g_cost.get(v) {
        Some(existing) => tentative < existing
        None => true
      }
      if improve {
        g_cost[v] = tentative
        parents[v] = u
        let f = @core.Weight::add(tentative, heuristic(v))
        pq.push(f, (v, tentative))
      }
    }
  }
  None
}
