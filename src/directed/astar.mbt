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
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] astar(
  start : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let g_cost : Map[N, W] = Map::new()
  let parents : Map[N, N] = Map::new()
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  g_cost[start] = zero
  pq.push(heuristic(start), start)
  while !pq.is_empty() {
    let (_f, u) = pq.pop().unwrap()
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
    let gu = g_cost.get(u).unwrap()
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
        pq.push(f, v)
      }
    }
  }
  None
}
