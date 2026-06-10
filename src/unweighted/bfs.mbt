// Breadth-First Search on an unweighted graph.
//
// Ported from: https://github.com/evenfurther/pathfinding (MIT OR Apache-2.0)
//   — API philosophy only; implementation is independently derived.

///|
/// BFS shortest path in an unweighted graph.
///
/// Computes a shortest-edge-count path from `start` to any node satisfying
/// `goal`, using the successor function to lazily explore the graph.
///
/// ## Parameters
/// - `start`: starting node (any type with `Eq + Hash`)
/// - `successors`: function returning the neighbors of a node
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// `Some(path)` if reachable (path includes both `start` and goal node).
/// `None` if no path exists.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
///
/// ## Example
/// ```moonbit skip
/// let adj = [[1], [2], [3], []]
/// let path = bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
/// inspect(path, content="Some([0, 1, 2, 3])")
/// ```
pub fn[N : Eq + Hash] bfs(
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
) -> Array[N]? {
  if goal(start) {
    return Some([start])
  }
  let queue : Array[N] = [start]
  let parents : Map[N, N] = Map::new()
  let visited : Map[N, Bool] = Map::new()
  visited[start] = true
  let mut head = 0
  //
  // Loop invariant (R8.1 / R8.4 · tasks.md 33.3 · target of `moon prove`):
  //
  //   (I1) Queue-visited consistency:
  //          forall n in queue[head..], visited.contains(n) == true
  //        — every node still pending expansion has been recorded in
  //        `visited`, so BFS never enqueues the same node twice.
  //
  //   (I2) Parent-well-formedness:
  //          forall n with parents[n] = p, visited.contains(p)
  //        — each parent pointer points to a node that was expanded
  //        earlier, which guarantees the reconstructed path ends at `start`.
  //
  //   (I3) Visited-Root coverage:
  //          forall n in visited, n == start \/ parents.contains(n)
  //        — every visited node except `start` has a recorded parent,
  //        so path reconstruction terminates at `start` rather than
  //        looping forever.
  //
  //   (I4) BFS level monotonicity (shortest-path witness):
  //          for any n reached at step i, depth(n) <= i
  //        — expressed informally as "the parent-chain length of every
  //        node in `visited` is bounded by `queue[0..head]` length";
  //        this is the heart of the "BFS returns a shortest unweighted
  //        path" theorem, discharged by induction on `head`.
  //
  //   (I5) No revisit on discovery:
  //          `visited.contains(next)` is always checked before enqueue,
  //        so the reachable subgraph is traversed at most once.
  //
  // When `moon prove` matures these invariants will be replaced by
  // executable `#invariant(...)` annotations referring to predicates in
  // `src/proofs/predicates.mbt` (see `is_valid_path`, `is_reachable`).
  //
  while head < queue.length() {
    let cur = queue[head]
    head += 1
    for next in successors(cur) {
      if visited.contains(next) {
        continue
      }
      visited[next] = true
      parents[next] = cur
      if goal(next) {
        // reconstruct path by walking parents back to start
        let path = [next]
        let mut node = next
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
        return Some(path)
      }
      queue.push(next)
    }
  }
  None
}
