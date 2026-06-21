// Topological sort via Kahn's algorithm (BFS over in-degree 0 nodes).
//
// Reference: Kahn, A. B. (1962). "Topological sorting of large networks".
// Communications of the ACM, 5(11), 558-562.

///|
/// Return a topological ordering of a DAG, or `Err(CycleDetected)` if the
/// graph contains a cycle.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `successors`: function returning outgoing edges of a node
///
/// ## Returns
/// - `Ok(order)` where `order` is a permutation of `nodes` such that for
///   every edge `(u, v)`, `u` appears before `v`.
/// - `Err(CycleDetected)` if the graph has a cycle.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] topological_sort(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Result[Array[N], @core.PathError] {
  let in_degree : Map[N, Int] = Map([])
  for n in nodes {
    in_degree[n] = 0
  }
  for u in nodes {
    for v in successors(u) {
      match in_degree.get(v) {
        Some(d) => in_degree[v] = d + 1
        None => in_degree[v] = 1
      }
    }
  }
  let queue : Array[N] = []
  for n in nodes {
    if in_degree.get(n).unwrap() == 0 {
      queue.push(n)
    }
  }
  let result : Array[N] = []
  let mut head = 0
  //
  // 循环不变式（R10.1 · Kahn 拓扑排序主循环 · 谓词见 @proofs.topo_order_post）:
  //
  //   (布尔陈述) result 是已确定的合法前缀：其中节点互不重复，且对每个已出队节点 u，
  //       其所有「在 result 中的前驱」都排在 u 之前；in_degree[w] 恒等于 w 尚未在
  //       result 中的前驱数目；queue[head..] 恰为当前 in_degree 为 0 且未入 result 的节点。
  //
  //   (初始化成立) 进入循环前 result 为空、head=0，queue 恰含所有入度为 0 的节点，
  //       in_degree[w] 等于 w 的全部前驱数：空前缀平凡合法，队列与计数定义自洽。
  //
  //   (迭代保持) 出队 cur（其 in_degree 已为 0，即所有前驱已在 result 中）并追加到
  //       result，保持「前驱先于后继」；随后对每条出边 (cur,next) 将 in_degree[next]
  //       减一，减到 0 时入队。每个节点至多入队/出队一次，故循环终止；若结束时
  //       result 未覆盖全部节点，说明存在环（剩余节点入度恒 >0）。
  //
  while head < queue.length() {
    let cur = queue[head]
    head += 1
    result.push(cur)
    for next in successors(cur) {
      let d = in_degree.get(next).unwrap() - 1
      in_degree[next] = d
      if d == 0 {
        queue.push(next)
      }
    }
  }
  if result.length() != nodes.length() {
    Err(CycleDetected)
  } else {
    Ok(result)
  }
}
