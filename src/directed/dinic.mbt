// Dinic's maximum flow algorithm.
//
// Builds level graphs with BFS and saturates blocking flows with iterative
// DFS. O(V^2 * E) in general — markedly faster than Edmonds-Karp on dense
// networks, and O(E * sqrt(V)) on unit-capacity (bipartite matching) graphs.
//
// Reference: Dinitz, Y. (1970). "Algorithm for solution of a problem of
// maximum flow in networks with power estimation". Soviet Math. Doklady.

///|
priv struct DinicEdge {
  to : Int
  /// Index of the reverse edge in `graph[to]`.
  rev : Int
  mut cap : Int
}

///|
/// Compute the maximum s-t flow in a flow network with integer capacities
/// using Dinic's algorithm.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `capacity`: map from `(u, v)` directed edges to edge capacity
/// - `source`: source node
/// - `sink`: sink node
///
/// ## Returns
/// The maximum flow value (integer).
///
/// ## Complexity
/// Time: O(V^2 * E). Space: O(V + E).
pub fn[N : Eq + Hash] dinic(
  nodes : Array[N],
  capacity : Map[(N, N), Int],
  source : N,
  sink : N,
) -> Int {
  let n = nodes.length()
  let index : Map[N, Int] = Map([])
  for i in 0..<n {
    index[nodes[i]] = i
  }
  let s = match index.get(source) {
    Some(i) => i
    None => return 0
  }
  let t = match index.get(sink) {
    Some(i) => i
    None => return 0
  }
  if s == t {
    return 0
  }
  // Adjacency list of residual edges; parallel edges are merged.
  let graph : Array[Array[DinicEdge]] = Array::makei(n, fn(_) {
    ([] : Array[DinicEdge])
  })
  let slot : Map[(Int, Int), Int] = Map([])
  fn add_edge(u : Int, v : Int, cap : Int) -> Unit {
    match slot.get((u, v)) {
      Some(i) => graph[u][i].cap += cap
      None => {
        let iu = graph[u].length()
        let iv = graph[v].length()
        graph[u].push({ to: v, rev: iv, cap })
        graph[v].push({ to: u, rev: iu, cap: 0 })
        slot[(u, v)] = iu
        slot[(v, u)] = iv
      }
    }
  }

  for k_v in capacity {
    let (edge, cap) = k_v
    let (u, v) = edge
    match (index.get(u), index.get(v)) {
      (Some(iu), Some(iv)) => if cap > 0 { add_edge(iu, iv, cap) }
      _ => ()
    }
  }
  let level : Array[Int] = Array::make(n, -1)
  let iter : Array[Int] = Array::make(n, 0)
  let mut total_flow = 0
  while true {
    // BFS: build the level graph on residual capacity.
    for i in 0..<n {
      level[i] = -1
    }
    level[s] = 0
    let queue : Array[Int] = [s]
    let mut head = 0
    while head < queue.length() {
      let u = queue[head]
      head += 1
      for e in graph[u] {
        if e.cap > 0 && level[e.to] < 0 {
          level[e.to] = level[u] + 1
          queue.push(e.to)
        }
      }
    }
    if level[t] < 0 {
      break
    }
    for i in 0..<n {
      iter[i] = 0
    }
    // Iterative DFS for a blocking flow: repeatedly walk forward along
    // admissible edges; on dead ends advance the parent's edge cursor.
    while true {
      let path_nodes : Array[Int] = [s]
      let path_edges : Array[Int] = []
      let mut advanced = true
      while advanced {
        let u = path_nodes[path_nodes.length() - 1]
        if u == t {
          break
        }
        advanced = false
        while iter[u] < graph[u].length() {
          let e = graph[u][iter[u]]
          if e.cap > 0 && level[e.to] == level[u] + 1 {
            path_edges.push(iter[u])
            path_nodes.push(e.to)
            advanced = true
            break
          }
          iter[u] += 1
        }
        if !advanced {
          // Dead end: prune `u` from this phase and backtrack.
          level[u] = -1
          if path_nodes.length() == 1 {
            break
          }
          let _ = path_nodes.pop()
          let _ = path_edges.pop()
          let p = path_nodes[path_nodes.length() - 1]
          iter[p] += 1
          advanced = true
        }
      }
      if path_nodes[path_nodes.length() - 1] != t {
        break
      }
      // Augment along the found path by its bottleneck.
      let mut bottleneck = EK_INT_MAX
      for i in 0..<path_edges.length() {
        let e = graph[path_nodes[i]][path_edges[i]]
        if e.cap < bottleneck {
          bottleneck = e.cap
        }
      }
      for i in 0..<path_edges.length() {
        let u = path_nodes[i]
        let e = graph[u][path_edges[i]]
        e.cap -= bottleneck
        graph[e.to][e.rev].cap += bottleneck
      }
      total_flow += bottleneck
    }
  }
  total_flow
}
