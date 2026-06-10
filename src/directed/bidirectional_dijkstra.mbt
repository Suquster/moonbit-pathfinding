// Bidirectional Dijkstra: simultaneous forward search from the start and
// backward search from the goal, meeting in the middle.
//
// On large graphs this explores roughly half the nodes plain Dijkstra would,
// since each frontier only needs to grow to about half the path length.
//
// Reference: Pohl, I. (1971). "Bi-directional search". Machine Intelligence 6.

///|
/// Shortest path between `start` and `goal` using bidirectional Dijkstra.
///
/// Requires non-negative edge weights, like plain Dijkstra. Because the
/// backward search relaxes edges in reverse, the caller must supply both
/// `successors` (outgoing edges) and `predecessors` (incoming edges). For an
/// undirected graph, pass the same adjacency function for both.
///
/// ## Parameters
/// - `start`: starting node
/// - `goal`: target node
/// - `successors`: outgoing `(neighbor, weight)` pairs of a node
/// - `predecessors`: incoming `(neighbor, weight)` pairs of a node
///
/// ## Returns
/// `Some((path, total_cost))` with the path from `start` to `goal`, or
/// `None` if `goal` is unreachable.
///
/// ## Complexity
/// Time: O((V + E) log V) worst case, typically ~2x faster than
/// unidirectional Dijkstra on long paths. Space: O(V).
pub fn[N : Eq + Hash, W : @core.Weight + Compare] bidirectional_dijkstra(
  start : N,
  goal : N,
  successors : (N) -> Array[(N, W)],
  predecessors : (N) -> Array[(N, W)],
) -> (Array[N], W)? {
  if start == goal {
    return Some(([start], @core.Weight::zero()))
  }
  let dist_f : Map[N, W] = Map([])
  let dist_b : Map[N, W] = Map([])
  let parent_f : Map[N, N] = Map([])
  let parent_b : Map[N, N] = Map([])
  let settled_f : Map[N, Bool] = Map([])
  let settled_b : Map[N, Bool] = Map([])
  let pq_f : @core.PQueue[N, W] = @core.PQueue::new()
  let pq_b : @core.PQueue[N, W] = @core.PQueue::new()
  dist_f[start] = @core.Weight::zero()
  dist_b[goal] = @core.Weight::zero()
  pq_f.push(@core.Weight::zero(), start)
  pq_b.push(@core.Weight::zero(), goal)
  let mut best : W = @core.Weight::infinity()
  let mut meeting : N? = None

  fn expand(
    pq : @core.PQueue[N, W],
    dist : Map[N, W],
    parent : Map[N, N],
    settled : Map[N, Bool],
    other_dist : Map[N, W],
    edges : (N) -> Array[(N, W)],
  ) -> Unit {
    match pq.pop() {
      Some((du, u)) => {
        if settled.get(u) is Some(_) {
          return
        }
        settled[u] = true
        for pair in edges(u) {
          let (v, w) = pair
          let nd = @core.Weight::add(du, w)
          let improve = match dist.get(v) {
            Some(existing) => nd < existing
            None => true
          }
          if improve {
            dist[v] = nd
            parent[v] = u
            pq.push(nd, v)
          }
          // Check for a meeting with the opposite frontier.
          match other_dist.get(v) {
            Some(od) => {
              let total = @core.Weight::add(nd, od)
              if total < best {
                best = total
                meeting = Some(v)
              }
            }
            None => ()
          }
        }
      }
      None => ()
    }
  }

  while !pq_f.is_empty() || !pq_b.is_empty() {
    // Stop once neither frontier can possibly improve the best meeting.
    let top_f = match pq_f.peek() {
      Some((d, _)) => d
      None => @core.Weight::infinity()
    }
    let top_b = match pq_b.peek() {
      Some((d, _)) => d
      None => @core.Weight::infinity()
    }
    if @core.Weight::add(top_f, top_b) >= best && meeting is Some(_) {
      break
    }
    if top_f <= top_b {
      expand(pq_f, dist_f, parent_f, settled_f, dist_b, successors)
    } else {
      expand(pq_b, dist_b, parent_b, settled_b, dist_f, predecessors)
    }
  }
  match meeting {
    Some(m) => {
      // Forward half: m back to start, reversed.
      let path : Array[N] = [m]
      let mut node = m
      while node != start {
        match parent_f.get(node) {
          Some(p) => {
            node = p
            path.push(node)
          }
          None => break
        }
      }
      path.rev_in_place()
      // Backward half: m towards goal.
      node = m
      while node != goal {
        match parent_b.get(node) {
          Some(p) => {
            node = p
            path.push(node)
          }
          None => break
        }
      }
      Some((path, best))
    }
    None => None
  }
}
