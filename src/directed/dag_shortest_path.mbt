// Single-source shortest path on a DAG via topological-order relaxation.
//
// Unlike Dijkstra, this handles negative edge weights (but no cycles), and
// runs in linear O(V + E) time instead of O((V + E) log V).
//
// Reference: Cormen, Leiserson, Rivest, Stein. "Introduction to Algorithms",
// 3rd ed., section 24.2 "Single-source shortest paths in directed acyclic
// graphs".

///|
/// Shortest path from `start` to the first node satisfying `goal` in a
/// directed acyclic graph, by relaxing edges in topological order.
///
/// Edge weights may be negative (the topological order guarantees each node
/// is finalized before its successors are relaxed), making this the right
/// tool for DAGs where Dijkstra's non-negativity precondition does not hold.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `start`: starting node
/// - `successors`: function returning `(neighbor, edge_weight)` pairs
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// - `Ok(Some((path, total_cost)))` if a goal node is reachable
/// - `Ok(None)` if no goal node is reachable from `start`
/// - `Err(CycleDetected)` if the graph is not acyclic
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash, W : @core.Weight] dag_shortest_path(
  nodes : Array[N],
  start : N,
  successors : (N) -> Array[(N, W)],
  goal : (N) -> Bool,
) -> Result[(Array[N], W)?, @core.PathError] {
  let order = match
    topological_sort(nodes, fn(u) {
      let out : Array[N] = []
      for pair in successors(u) {
        let (v, _) = pair
        out.push(v)
      }
      out
    }) {
    Ok(o) => o
    Err(e) => return Err(e)
  }
  let dist : Map[N, W] = Map([])
  let parents : Map[N, N] = Map([])
  dist[start] = @core.Weight::zero()
  for u in order {
    let du = match dist.get(u) {
      Some(d) => d
      None => continue // unreachable from start
    }
    for pair in successors(u) {
      let (v, w) = pair
      let new_dist = @core.Weight::add(du, w)
      let improve = match dist.get(v) {
        Some(existing) => new_dist < existing
        None => true
      }
      if improve {
        dist[v] = new_dist
        parents[v] = u
      }
    }
  }
  // Pick the best-reaching goal node (topological order does not imply the
  // first goal encountered is the cheapest).
  let mut best : (N, W)? = None
  for u in order {
    if goal(u) {
      match dist.get(u) {
        Some(d) =>
          best = match best {
            Some((_, bd)) => if d < bd { Some((u, d)) } else { best }
            None => Some((u, d))
          }
        None => ()
      }
    }
  }
  match best {
    Some((target, d)) => {
      let path = [target]
      let mut node = target
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
      Ok(Some((path, d)))
    }
    None => Ok(None)
  }
}
