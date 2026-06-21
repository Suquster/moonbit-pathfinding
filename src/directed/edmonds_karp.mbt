// Edmonds-Karp maximum flow algorithm.
//
// Reference: Edmonds, J., & Karp, R. M. (1972). "Theoretical improvements in
// algorithmic efficiency for network flow problems". JACM, 19(2), 248-264.

///|
/// Sentinel for "no bottleneck found yet" — the maximum `Int` value.
const EK_INT_MAX : Int = 2147483647

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
  // Sparse residual graph: only real edges and their reverse edges are
  // materialized (capacity 0 for the reverse direction), keeping memory
  // at O(E) instead of O(V^2).
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
  ignore(nodes)
  let mut total_flow = 0
  //
  // 循环不变式（R10.1 · Edmonds-Karp 增广主循环 · 谓词见 @proofs.max_flow_valid / max_flow_equals_min_cut）:
  //
  //   (布尔陈述) total_flow 等于当前残量网络所对应的可行 s-t 流值；对每条原边 (u,v)，
  //       residual[(u,v)] + residual[(v,u)] 守恒等于其总容量，故 residual 始终编码一个
  //       满足容量约束与流量守恒的合法流。
  //
  //   (初始化成立) 进入循环前 total_flow=0、residual 等于初始容量（反向边为 0）：零流
  //       平凡可行，容量守恒等式按构造成立。
  //
  //   (迭代保持) 每轮用 BFS 在残量网络中找一条最短增广路（保证 Edmonds-Karp 的 O(VE²)
  //       界）。沿路取瓶颈 bottleneck>0，正向减、反向加该值：流量守恒与容量约束保持，
  //       total_flow 增加 bottleneck 仍等于新流值。BFS 找不到增广路（!found）时，
  //       由最大流最小割定理当前流即最大流，循环退出。每轮至少使一条边饱和，循环终止。
  //
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
    // Find bottleneck.
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
