// Topological sort via Kahn's algorithm (BFS over in-degree 0 nodes).
//
// Reference: Kahn, A. B. (1962). "Topological sorting of large networks".
// Communications of the ACM, 5(11), 558-562.

///|
/// Return a topological ordering of a DAG, or `Err(CycleDetected)` if the
/// graph contains a cycle.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `successors`: function returning outgoing edges of a node
///
/// ## Returns
/// - `Ok(order)` where `order` is a permutation of `nodes` such that for
///   every edge `(u, v)`, `u` appears before `v`.
/// - `Err(CycleDetected)` if the graph has a cycle.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] topological_sort(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Result[Array[N], @core.PathError] {
  let in_degree : Map[N, Int] = Map::new()
  for n in nodes {
    in_degree[n] = 0
  }
  for u in nodes {
    for v in successors(u) {
      match in_degree.get(v) {
        Some(d) => in_degree[v] = d + 1
        None => in_degree[v] = 1
      }
    }
  }
  let queue : Array[N] = []
  for n in nodes {
    if in_degree.get(n).unwrap() == 0 {
      queue.push(n)
    }
  }
  let result : Array[N] = []
  let mut head = 0
  while head < queue.length() {
    let cur = queue[head]
    head += 1
    result.push(cur)
    for next in successors(cur) {
      let d = in_degree.get(next).unwrap() - 1
      in_degree[next] = d
      if d == 0 {
        queue.push(next)
      }
    }
  }
  if result.length() != nodes.length() {
    Err(CycleDetected)
  } else {
    Ok(result)
  }
}
