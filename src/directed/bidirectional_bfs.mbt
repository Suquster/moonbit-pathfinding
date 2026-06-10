// Bidirectional BFS: simultaneously expand from start and goal, meeting in
// the middle. Useful when both forward and backward successor functions are
// available — cuts the search space from O(b^d) to O(b^(d/2)).

///|
/// Bidirectional BFS between `start` and `goal`.
///
/// ## Parameters
/// - `start`: source node
/// - `goal`: target node
/// - `successors`: forward neighbors (edges u -> v)
/// - `predecessors`: backward neighbors (edges v -> u; needed for reverse BFS)
///
/// ## Returns
/// `Some(path)` from `start` to `goal`, or `None` if unreachable.
pub fn[N : Eq + Hash] bidirectional_bfs(
  start : N,
  goal : N,
  successors : (N) -> Array[N],
  predecessors : (N) -> Array[N],
) -> Array[N]? {
  if start == goal {
    return Some([start])
  }
  let fwd_parent : Map[N, N] = Map::new()
  let bwd_parent : Map[N, N] = Map::new()
  let fwd_visited : Map[N, Bool] = Map::new()
  let bwd_visited : Map[N, Bool] = Map::new()
  fwd_visited[start] = true
  bwd_visited[goal] = true
  let fwd_queue : Array[N] = [start]
  let bwd_queue : Array[N] = [goal]
  let mut fwd_head = 0
  let mut bwd_head = 0
  let mut meeting : N? = None
  while fwd_head < fwd_queue.length() && bwd_head < bwd_queue.length() {
    // Expand the smaller frontier first (cheaper).
    if fwd_queue.length() - fwd_head <= bwd_queue.length() - bwd_head {
      let cur = fwd_queue[fwd_head]
      fwd_head += 1
      for next in successors(cur) {
        if fwd_visited.contains(next) {
          continue
        }
        fwd_visited[next] = true
        fwd_parent[next] = cur
        if bwd_visited.contains(next) {
          meeting = Some(next)
          break
        }
        fwd_queue.push(next)
      }
    } else {
      let cur = bwd_queue[bwd_head]
      bwd_head += 1
      for next in predecessors(cur) {
        if bwd_visited.contains(next) {
          continue
        }
        bwd_visited[next] = true
        bwd_parent[next] = cur
        if fwd_visited.contains(next) {
          meeting = Some(next)
          break
        }
        bwd_queue.push(next)
      }
    }
    if meeting is Some(_) {
      break
    }
  }
  match meeting {
    Some(m) => {
      // Reconstruct: start -> ... -> m via fwd_parent, then m -> ... -> goal via bwd_parent.
      let left : Array[N] = [m]
      let mut n = m
      while n != start {
        match fwd_parent.get(n) {
          Some(p) => {
            n = p
            left.push(n)
          }
          None => break
        }
      }
      left.rev_in_place()
      let mut n2 = m
      while n2 != goal {
        match bwd_parent.get(n2) {
          Some(p) => {
            n2 = p
            left.push(n2)
          }
          None => break
        }
      }
      Some(left)
    }
    None => None
  }
}
