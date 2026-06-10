// SCC condensation: collapse strongly connected components into a DAG.
//
// Builds on `tarjan_scc`; the resulting component graph is acyclic, which
// enables DAG-only algorithms (topological sort, DAG shortest path) on
// arbitrary directed graphs.

///|
/// Condensation of a directed graph: its strongly connected components plus
/// the edges between distinct components.
pub struct Condensation[N] {
  /// The strongly connected components (each an array of original nodes).
  components : Array[Array[N]]
  /// `component_of[node]` = index into `components`.
  component_of : Map[N, Int]
  /// Deduplicated edges `(from_component, to_component)` of the DAG.
  dag_edges : Array[(Int, Int)]
}

///|
/// Compute the condensation DAG of a directed graph.
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `successors`: function returning the out-neighbors of a node
///
/// ## Returns
/// A `Condensation` with the component list, a node→component map, and the
/// deduplicated inter-component edges (guaranteed acyclic).
///
/// ## Complexity
/// Time: O(V + E). Space: O(V + E).
pub fn[N : Eq + Hash] condensation(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Condensation[N] {
  let components = tarjan_scc(nodes, successors)
  let component_of : Map[N, Int] = Map([])
  for i in 0..<components.length() {
    for node in components[i] {
      component_of[node] = i
    }
  }
  let seen : Map[(Int, Int), Bool] = Map([])
  let dag_edges : Array[(Int, Int)] = []
  for node in nodes {
    match component_of.get(node) {
      Some(cu) =>
        for v in successors(node) {
          match component_of.get(v) {
            Some(cv) =>
              if cu != cv && !seen.contains((cu, cv)) {
                seen[(cu, cv)] = true
                dag_edges.push((cu, cv))
              }
            None => ()
          }
        }
      None => ()
    }
  }
  { components, component_of, dag_edges }
}
