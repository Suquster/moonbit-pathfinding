// Kruskal's Minimum Spanning Tree algorithm.
//
// Reference: Kruskal, J. B. (1956). "On the shortest spanning subtree of a
// graph and the traveling salesman problem". Proceedings of the American
// Mathematical Society, 7(1), 48-50.

///|
/// Compute a minimum spanning tree (MST) of an undirected weighted graph
/// using Kruskal's algorithm (sort edges by weight, use DSU for cycle check).
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `edges`: list of `(u, v, weight)` edges (undirected; each edge listed once)
///
/// ## Returns
/// An array of edges that form the MST. For a connected graph of |V| nodes,
/// the result contains exactly |V| - 1 edges. For disconnected graphs, the
/// result is a minimum spanning forest (fewer edges).
///
/// ## Complexity
/// Time: O(E log E). Space: O(V + E).
pub fn[N : Eq + Hash, W : @core.Weight] kruskal_mst(
  nodes : Array[N],
  edges : Array[(N, N, W)],
) -> Array[(N, N, W)] {
  let sorted_edges = edges.copy()
  sorted_edges.sort_by(fn(a, b) {
    let (_, _, wa) = a
    let (_, _, wb) = b
    if wa < wb {
      -1
    } else if wa > wb {
      1
    } else {
      0
    }
  })
  let dsu : @core.DSU[N] = @core.DSU::new()
  for n in nodes {
    dsu.make_set(n)
  }
  let result : Array[(N, N, W)] = []
  for edge in sorted_edges {
    let (u, v, _w) = edge
    if dsu.union(u, v) {
      result.push(edge)
      if result.length() == nodes.length() - 1 {
        break
      }
    }
  }
  result
}
