// Minimum s-t cut via max-flow (max-flow min-cut theorem).
//
// Runs Edmonds-Karp to saturate the network, then the cut is the set of
// original edges crossing from the source-reachable side of the final
// residual graph to the unreachable side.
//
// Reference: Ford, L. R., & Fulkerson, D. R. (1956). "Maximal flow through a
// network". Canadian Journal of Mathematics, 8, 399-404.

///|
/// Compute the minimum s-t cut of a flow network with integer capacities.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `capacity`: map from `(u, v)` directed edges to edge capacity
/// - `source`: source node
/// - `sink`: sink node
///
/// ## Returns
/// `(cut_value, cut_edges, source_side)` where `cut_value` equals the
/// maximum flow, `cut_edges` are the saturated original edges crossing the
/// cut, and `source_side` is the set of nodes reachable from `source` in the
/// final residual graph.
///
/// ## Complexity
/// Time: O(V * E^2). Space: O(V + E).
pub fn[N : Eq + Hash] min_cut(
  nodes : Array[N],
  capacity : Map[(N, N), Int],
  source : N,
  sink : N,
) -> (Int, Array[(N, N)], Array[N]) {
  // Rebuild the residual network and saturate it (same procedure as
  // `edmonds_karp`, but we need the final residual state afterwards).
  let residual : Map[(N, N), Int] = Map([])
  let adj : Map[N, Array[N]] = Map([])
  fn add_neighbor(a : N, b : N) -> Unit {
    let lst = adj.get(a).unwrap_or([])
    let mut present = false
    for x in lst {
      if x == b {
        present = true
        break
      }
    }
    if !present {
      lst.push(b)
      adj[a] = lst
    }
  }

  for k_v in capacity {
    let (edge, cap) = k_v
    let (u, v) = edge
    residual[edge] = residual.get(edge).unwrap_or(0) + cap
    if !residual.contains((v, u)) {
      residual[(v, u)] = 0
    }
    add_neighbor(u, v)
    add_neighbor(v, u)
  }
  let mut total_flow = 0
  //
  // 循环不变式（R10.1 · 最小割（最大流增广）主循环 · 谓词见 @proofs.max_flow_equals_min_cut）:
  //
  //   (布尔陈述) total_flow 等于残量图当前编码的可行 s-t 流值；对每条原边 (u,v)，
  //       residual[(u,v)]+residual[(v,u)] 守恒等于其容量，故 residual 始终是合法流的残量表示。
  //
  //   (初始化成立) 进入循环前 total_flow=0、residual 等于初始容量（反向边 0）：零流平凡可行。
  //
  //   (迭代保持) 每轮 BFS 在残量图找一条 s-t 增广路；沿路取瓶颈 bottleneck>0，正向减反向加，
  //       保持流量守恒与容量约束，total_flow 增加 bottleneck 仍等于新流值。BFS 找不到增广路时
  //       退出——此时从 source 在残量图可达的节点集 reachable 与其补集构成一个 s-t 割，由最大流
  //       最小割定理其容量恰等于 total_flow，即最小割；割边为 reachable→非 reachable 的原边。
  //
  while true {
    let parent : Map[N, N] = Map([])
    let visited : Map[N, Bool] = Map([])
    visited[source] = true
    let queue : Array[N] = [source]
    let mut head = 0
    let mut found = false
    while head < queue.length() && !found {
      let u = queue[head]
      head += 1
      for v in adj.get(u).unwrap_or([]) {
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
    let mut bottleneck = EK_INT_MAX
    let mut v = sink
    while v != source {
      let u = parent.get(v).unwrap()
      let c = residual.get((u, v)).unwrap()
      if c < bottleneck {
        bottleneck = c
      }
      v = u
    }
    let mut v2 = sink
    while v2 != source {
      let u = parent.get(v2).unwrap()
      residual[(u, v2)] = residual.get((u, v2)).unwrap() - bottleneck
      residual[(v2, u)] = residual.get((v2, u)).unwrap() + bottleneck
      v2 = u
    }
    total_flow += bottleneck
  }
  // Source side = nodes reachable in the final residual graph.
  let reachable : Map[N, Bool] = Map([])
  reachable[source] = true
  let queue : Array[N] = [source]
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for v in adj.get(u).unwrap_or([]) {
      if !reachable.contains(v) && residual.get((u, v)).unwrap_or(0) > 0 {
        reachable[v] = true
        queue.push(v)
      }
    }
  }
  // Cut edges: original edges from the reachable side to the rest.
  let cut_edges : Array[(N, N)] = []
  for k_v in capacity {
    let (edge, cap) = k_v
    let (u, v) = edge
    if cap > 0 && reachable.contains(u) && !reachable.contains(v) {
      cut_edges.push(edge)
    }
  }
  let source_side : Array[N] = []
  for node in nodes {
    if reachable.contains(node) {
      source_side.push(node)
    }
  }
  (total_flow, cut_edges, source_side)
}
