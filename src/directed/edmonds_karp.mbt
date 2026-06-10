// Edmonds-Karp maximum flow algorithm.
//
// Reference: Edmonds, J., & Karp, R. M. (1972). "Theoretical improvements in
// algorithmic efficiency for network flow problems". JACM, 19(2), 248-264.

///|
/// Compute the maximum s-t flow in a flow network with integer capacities,
/// using BFS to find shortest augmenting paths. Runs in O(V * E^2).
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `capacity`: map from `(u, v)` directed edges to edge capacity
/// - `source`: source node
/// - `sink`: sink node
///
/// ## Returns
/// The maximum flow value (integer).
pub fn[N : Eq + Hash] edmonds_karp(
  nodes : Array[N],
  capacity : Map[(N, N), Int],
  source : N,
  sink : N,
) -> Int {
  // Build adjacency: for max flow with residual graph, every edge (u,v) has
  // a reverse edge (v,u) with initial capacity 0.
  let residual : Map[(N, N), Int] = Map([])
  for k_v in capacity {
    let (edge, cap) = k_v
    residual[edge] = cap
  }
  for u in nodes {
    for v in nodes {
      if !residual.contains((u, v)) {
        residual[(u, v)] = 0
      }
    }
  }
  let mut total_flow = 0
  while true {
    // BFS to find an augmenting path from source to sink.
    let parent : Map[N, N] = Map([])
    let visited : Map[N, Bool] = Map([])
    visited[source] = true
    let queue : Array[N] = [source]
    let mut head = 0
    let mut found = false
    while head < queue.length() && !found {
      let u = queue[head]
      head += 1
      for v in nodes {
        if visited.contains(v) {
          continue
        }
        let c = residual.get((u, v)).unwrap_or(0)
        if c > 0 {
          visited[v] = true
          parent[v] = u
          if v == sink {
            found = true
            break
          }
          queue.push(v)
        }
      }
    }
    if !found {
      break
    }
    // Find bottleneck.
    let mut bottleneck = 2147483647
    let mut v = sink
    while v != source {
      let u = parent.get(v).unwrap()
      let c = residual.get((u, v)).unwrap()
      if c < bottleneck {
        bottleneck = c
      }
      v = u
    }
    // Update residual capacities along the path.
    let mut v2 = sink
    while v2 != source {
      let u = parent.get(v2).unwrap()
      residual[(u, v2)] = residual.get((u, v2)).unwrap() - bottleneck
      residual[(v2, u)] = residual.get((v2, u)).unwrap() + bottleneck
      v2 = u
    }
    total_flow += bottleneck
  }
  total_flow
}
