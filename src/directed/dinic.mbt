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
  //
  // 循环不变式（R10.1 · Dinic 阶段主循环 · 谓词见 @proofs.max_flow_valid / max_flow_equals_min_cut）:
  //
  //   (布尔陈述) total_flow 等于残量图 graph 当前编码的可行 s-t 流值；每对正/反向边
  //       (e.cap 与其 rev 的 cap) 之和守恒等于原始容量，故残量图始终表示满足容量约束与
  //       流量守恒的合法流；每个阶段的 level[] 给出 BFS 分层（s 到各点的残量最短边数）。
  //
  //   (初始化成立) 进入循环前 total_flow=0、graph 为初始容量的残量表（反向边 cap=0）：
  //       零流平凡可行，容量守恒按 add_edge 构造成立。
  //
  //   (迭代保持) 每个阶段先用 BFS 在残量图上建分层 level；若 sink 不可达（level[t]<0）则
  //       当前流即最大流（由最大流最小割定理），退出。否则用迭代 DFS 沿「层级恰 +1」的
  //       admissible 边反复增广出阻塞流，每条增广路按瓶颈更新正反向 cap：流量守恒与容量
  //       约束保持，total_flow 增加且仍等于新流值。每阶段 s-t 最短残量距离严格增大，故至多
  //       V 个阶段，循环终止。
  //
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
