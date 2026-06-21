// Minimum-cost maximum flow via successive shortest augmenting paths.
//
// Uses SPFA (queue-based Bellman-Ford) to find the cheapest augmenting path
// in the residual network, which tolerates the negative reverse-edge costs
// without potentials.
//
// Reference: Edmonds, J., & Karp, R. M. (1972). "Theoretical improvements in
// algorithmic efficiency for network flow problems". JACM, 19(2), 248-264.

///|
priv struct McmfEdge {
  to : Int
  rev : Int
  mut cap : Int
  cost : Int
}

///|
/// Compute the minimum-cost maximum s-t flow in a network with integer
/// capacities and integer (non-negative) edge costs.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `edges`: list of `(u, v, capacity, cost)` directed edges
/// - `source`: source node
/// - `sink`: sink node
///
/// ## Returns
/// `(max_flow, total_cost)` — the maximum flow value and the minimum total
/// cost of routing that flow.
///
/// ## Complexity
/// Time: O(F * V * E) where F is the max flow value. Space: O(V + E).
pub fn[N : Eq + Hash] min_cost_max_flow(
  nodes : Array[N],
  edges : Array[(N, N, Int, Int)],
  source : N,
  sink : N,
) -> (Int, Int) {
  let n = nodes.length()
  let index : Map[N, Int] = Map([])
  for i in 0..<n {
    index[nodes[i]] = i
  }
  let s = match index.get(source) {
    Some(i) => i
    None => return (0, 0)
  }
  let t = match index.get(sink) {
    Some(i) => i
    None => return (0, 0)
  }
  if s == t {
    return (0, 0)
  }
  let graph : Array[Array[McmfEdge]] = Array::makei(n, fn(_) {
    ([] : Array[McmfEdge])
  })
  for edge in edges {
    let (u, v, cap, cost) = edge
    match (index.get(u), index.get(v)) {
      (Some(iu), Some(iv)) =>
        if cap > 0 {
          let pos_u = graph[iu].length()
          let pos_v = graph[iv].length()
          graph[iu].push({ to: iv, rev: pos_v, cap, cost })
          graph[iv].push({ to: iu, rev: pos_u, cap: 0, cost: -cost })
        }
      _ => ()
    }
  }
  let mut total_flow = 0
  let mut total_cost = 0
  //
  // 循环不变式（R10.1 · 最小费用最大流 SSP 主循环 · 谓词见 @proofs.min_cost_flow_valid）:
  //
  //   (布尔陈述) (total_flow, total_cost) 恰为「流值为 total_flow 时的最小费用可行流」；
  //       残量图 graph 编码该合法流（正/反向 cap 守恒、反向边费用取负），且不含负费用环
  //       （SSP 沿最短费用路增广可保证此不变量）。
  //
  //   (初始化成立) 进入循环前 total_flow=total_cost=0、graph 为初始容量残量表（反向 cap=0）：
  //       零流平凡是费用为 0 的最小费用 0-流，无负环。
  //
  //   (迭代保持) 每轮用 SPFA 求 s→t 的最小费用增广路（dist[t] 为单位增广费用）；沿路取瓶颈
  //       增广，正向减反向加，total_flow += bottleneck、total_cost += bottleneck*dist[t]。因每次
  //       选「当前最便宜」的增广路，结果对每个流值都是费用最小，故不变式保持；dist[t]=+∞ 即无
  //       增广路、已达最大流，退出。每轮至少饱和一条边，循环终止。
  //
  while true {
    // SPFA: cheapest path from s to t in the residual network.
    let dist : Array[Int] = Array::make(n, EK_INT_MAX)
    let in_queue : Array[Bool] = Array::make(n, false)
    let prev_node : Array[Int] = Array::make(n, -1)
    let prev_edge : Array[Int] = Array::make(n, -1)
    dist[s] = 0
    let queue : Array[Int] = [s]
    in_queue[s] = true
    let mut head = 0
    while head < queue.length() {
      let u = queue[head]
      head += 1
      in_queue[u] = false
      for i in 0..<graph[u].length() {
        let e = graph[u][i]
        if e.cap > 0 && dist[u] != EK_INT_MAX && dist[u] + e.cost < dist[e.to] {
          dist[e.to] = dist[u] + e.cost
          prev_node[e.to] = u
          prev_edge[e.to] = i
          if !in_queue[e.to] {
            queue.push(e.to)
            in_queue[e.to] = true
          }
        }
      }
    }
    if dist[t] == EK_INT_MAX {
      break
    }
    // Bottleneck along the cheapest path.
    let mut bottleneck = EK_INT_MAX
    let mut v = t
    while v != s {
      let e = graph[prev_node[v]][prev_edge[v]]
      if e.cap < bottleneck {
        bottleneck = e.cap
      }
      v = prev_node[v]
    }
    // Augment.
    let mut v2 = t
    while v2 != s {
      let u = prev_node[v2]
      let e = graph[u][prev_edge[v2]]
      e.cap -= bottleneck
      graph[e.to][e.rev].cap += bottleneck
      v2 = u
    }
    total_flow += bottleneck
    total_cost += bottleneck * dist[t]
  }
  (total_flow, total_cost)
}
