// Iterative Deepening A* (IDA*).
//
// Reference: Korf, R. E. (1985). "Depth-first iterative-deepening: An optimal
// admissible tree search". Artificial Intelligence, 27(1), 97-109.

///|
/// IDA* search: iteratively deepens a threshold on f = g + h, running DFS
/// bounded by that threshold.
///
/// Uses O(d) memory where d is the solution depth (vs A*'s O(b^d)).
/// Recommended when memory is tight and the heuristic is admissible.
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: `(neighbor, edge_weight)` pairs
/// - `heuristic`: admissible heuristic
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// `Some((path, cost))` if reachable, `None` otherwise.
pub fn[N : Eq + Hash, W : @core.Weight] ida_star(
  start : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let zero = @core.Weight::zero()
  let inf = @core.Weight::infinity()
  let mut bound = heuristic(start)
  let path : Array[N] = [start]
  // O(1) membership test for the current path (replaces a linear scan that
  // made deep searches quadratic in the path length).
  let on_path : Map[N, Bool] = Map([])
  on_path[start] = true
  // Search returns either a found path (encoded via early exit), or the
  // smallest f-value that exceeded the bound (used to raise bound next round).
  // When the goal is found, `found_cost` carries the exact g-value, so no
  // post-hoc successor rescans are needed to recover the total cost.
  let mut found_cost : W = zero
  fn search(node : N, g : W, bound : W) -> W? {
    let f = @core.Weight::add(g, heuristic(node))
    if f > bound {
      return Some(f)
    }
    if goal(node) {
      found_cost = g
      // Signal found via returning `None` only when we already populated `path`.
      return None
    }
    let mut min_exceeded = inf
    for pair in successors(node) {
      let (next, w) = pair
      // Avoid revisiting nodes on the current path (simple cycle check).
      if on_path.get(next).unwrap_or(false) {
        continue
      }
      path.push(next)
      on_path[next] = true
      match search(next, @core.Weight::add(g, w), bound) {
        None => return None // found!
        Some(t) => if t < min_exceeded { min_exceeded = t }
      }
      ignore(path.pop())
      on_path[next] = false
    }
    Some(min_exceeded)
  }

  while true {
    match search(start, zero, bound) {
      None => return Some((path, found_cost))
      Some(t) => if t == inf { return None } else { bound = t }
    }
  }
  None
}
