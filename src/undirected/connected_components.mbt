// Connected Components of an undirected graph via BFS from each unvisited node.

///|
/// Compute the connected components of an undirected graph.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `successors`: function returning neighbors of a node
///
/// ## Returns
/// An array of components, where each component is an array of nodes.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] connected_components(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Array[Array[N]] {
  let visited : Map[N, Bool] = Map([])
  let components : Array[Array[N]] = []
  for start in nodes {
    if visited.contains(start) {
      continue
    }
    // BFS to collect the component containing `start`.
    let queue : Array[N] = [start]
    let component : Array[N] = []
    visited[start] = true
    let mut head = 0
    while head < queue.length() {
      let cur = queue[head]
      head += 1
      component.push(cur)
      for next in successors(cur) {
        if !visited.contains(next) {
          visited[next] = true
          queue.push(next)
        }
      }
    }
    components.push(component)
  }
  components
}
