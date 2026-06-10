// Prim's Minimum Spanning Tree algorithm.
//
// Complements Kruskal: Prim grows a single tree from a seed node using a
// priority queue, which performs better on dense adjacency-list graphs.
//
// Reference: Prim, R. C. (1957). "Shortest connection networks and some
// generalizations". Bell System Technical Journal, 36(6), 1389-1401.

///|
/// Compute a minimum spanning tree (MST) of an undirected weighted graph
/// using Prim's algorithm (lazy variant with a binary min-heap).
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `neighbors`: function returning `(neighbor, edge_weight)` pairs; the
///   graph is undirected, so if `v` is a neighbor of `u`, `u` must also be
///   reported as a neighbor of `v`
///
/// ## Returns
/// An array of `(u, v, weight)` edges forming the MST, where `u` is the
/// tree-side endpoint. For a connected graph of |V| nodes the result has
/// exactly |V| - 1 edges; for disconnected graphs each component yields its
/// own spanning tree (minimum spanning forest).
///
/// ## Complexity
/// Time: O(E log E). Space: O(V + E).
pub fn[N : Eq + Hash, W : @core.Weight] prim_mst(
  nodes : Array[N],
  neighbors : (N) -> Array[(N, W)],
) -> Array[(N, N, W)] {
  let in_tree : Map[N, Bool] = Map([])
  let result : Array[(N, N, W)] = []
  for seed in nodes {
    if in_tree.get(seed) is Some(_) {
      continue
    }
    // Grow a new tree from this component's seed.
    in_tree[seed] = true
    let pq : @core.PQueue[(N, N), W] = @core.PQueue::new()
    for pair in neighbors(seed) {
      let (v, w) = pair
      pq.push(w, (seed, v))
    }
    while !pq.is_empty() {
      let (w, edge) = pq.pop().unwrap()
      let (u, v) = edge
      if in_tree.get(v) is Some(_) {
        continue
      }
      in_tree[v] = true
      result.push((u, v, w))
      for pair in neighbors(v) {
        let (next, nw) = pair
        if in_tree.get(next) is None {
          pq.push(nw, (v, next))
        }
      }
    }
  }
  result
}
