// Depth-First Search on a directed graph (non-recursive, explicit stack).
//
// Uses an iterative stack-based implementation to avoid potential stack
// overflows on deep graphs (MoonBit's default stack depth is limited).

///|
/// DFS path from `start` to any node satisfying `goal`.
///
/// Returns `Some(path)` where `path` includes both endpoints, or `None` if
/// no path exists. The path is not guaranteed to be the shortest — DFS
/// prioritizes depth. For shortest-path semantics on unweighted graphs, use
/// `@unweighted.bfs` instead.
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: function returning neighbors of a node
/// - `goal`: predicate testing whether a node is the target
///
/// ## Complexity
/// Time: O(V + E). Space: O(V) for the explicit stack.
pub fn[N : Eq + Hash] dfs(
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
) -> Array[N]? {
  if goal(start) {
    return Some([start])
  }
  // Stack entries are (node, parent_index_in_path_so_far).
  // We track parents via a Map to reconstruct the path on success.
  let stack : Array[N] = [start]
  let parents : Map[N, N] = Map([])
  let visited : Map[N, Bool] = Map([])
  visited[start] = true
  while stack.length() > 0 {
    let cur = stack.pop().unwrap()
    for next in successors(cur) {
      if visited.contains(next) {
        continue
      }
      visited[next] = true
      parents[next] = cur
      if goal(next) {
        // Reconstruct path by walking parents back to start.
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
      stack.push(next)
    }
  }
  None
}
