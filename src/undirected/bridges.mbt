// Bridges and articulation points of an undirected graph.
//
// A bridge is an edge whose removal disconnects its component; an
// articulation point (cut vertex) is a node whose removal does the same.
// Both are found in one DFS pass using discovery times and low-links.
//
// Reference: Tarjan, R. (1974). "A note on finding the bridges of a graph".
// Information Processing Letters, 2(6), 160-161.

///|
/// Find all bridges (cut edges) of an undirected graph.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `neighbors`: adjacency function; the graph is undirected, so adjacency
///   must be symmetric. Parallel edges are honored: an edge duplicated in the
///   adjacency lists is never a bridge.
///
/// ## Returns
/// An array of `(u, v)` bridge edges, where `u` is the DFS-parent endpoint.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] bridges(
  nodes : Array[N],
  neighbors : (N) -> Array[N],
) -> Array[(N, N)] {
  let (bridge_edges, _) = bridges_and_articulation_points(nodes, neighbors)
  bridge_edges
}

///|
/// Find all articulation points (cut vertices) of an undirected graph.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] articulation_points(
  nodes : Array[N],
  neighbors : (N) -> Array[N],
) -> Array[N] {
  let (_, points) = bridges_and_articulation_points(nodes, neighbors)
  points
}

///|
/// Compute bridges and articulation points in a single DFS pass.
///
/// Uses an iterative DFS (explicit stack), so it is safe on deep graphs
/// where recursion would overflow.
pub fn[N : Eq + Hash] bridges_and_articulation_points(
  nodes : Array[N],
  neighbors : (N) -> Array[N],
) -> (Array[(N, N)], Array[N]) {
  let disc : Map[N, Int] = Map([])
  let low : Map[N, Int] = Map([])
  let is_cut : Map[N, Bool] = Map([])
  let bridge_edges : Array[(N, N)] = []
  let points : Array[N] = []
  let mut timer = 0
  for root in nodes {
    if disc.get(root) is Some(_) {
      continue
    }
    // Stack frames: (node, parent option, neighbor list, next index,
    // whether the edge back to parent has already been skipped once).
    let stack : Array[(N, N?, Array[N], Int, Bool)] = []
    disc[root] = timer
    low[root] = timer
    timer += 1
    stack.push((root, None, neighbors(root), 0, false))
    let mut root_children = 0
    while stack.length() > 0 {
      let (u, parent, adj, idx, parent_skipped) = stack.pop().unwrap()
      if idx < adj.length() {
        let v = adj[idx]
        // Resume this frame at the next neighbor afterwards.
        let mut skipped = parent_skipped
        let mut descend = false
        if parent is Some(p) && v == p && !parent_skipped {
          // Skip the tree edge back to the parent exactly once, so that
          // parallel edges still update low correctly.
          skipped = true
        } else {
          match disc.get(v) {
            Some(dv) => if dv < low.get(u).unwrap() { low[u] = dv }
            None => descend = true
          }
        }
        stack.push((u, parent, adj, idx + 1, skipped))
        if descend {
          if parent is None && stack.length() >= 1 && u == root {
            root_children += 1
          }
          disc[v] = timer
          low[v] = timer
          timer += 1
          stack.push((v, Some(u), neighbors(v), 0, false))
        }
      } else {
        // Post-order: propagate low to parent and classify.
        match parent {
          Some(p) => {
            let lu = low.get(u).unwrap()
            if lu < low.get(p).unwrap() {
              low[p] = lu
            }
            if lu > disc.get(p).unwrap() {
              bridge_edges.push((p, u))
            }
            if p != root && lu >= disc.get(p).unwrap() {
              if is_cut.get(p) is None {
                is_cut[p] = true
                points.push(p)
              }
            }
          }
          None => ()
        }
      }
    }
    if root_children > 1 && is_cut.get(root) is None {
      is_cut[root] = true
      points.push(root)
    }
  }
  (bridge_edges, points)
}
