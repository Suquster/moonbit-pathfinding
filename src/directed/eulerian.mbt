// Eulerian path / circuit in a directed graph (Hierholzer's algorithm).
//
// An Eulerian path visits every edge exactly once. It exists iff the graph
// (ignoring isolated nodes) is connected, and either every node has equal
// in/out degree (circuit) or exactly one node has out-in = 1 (start) and one
// has in-out = 1 (end).
//
// Reference: Hierholzer, C. (1873). "Über die Möglichkeit, einen Linienzug
// ohne Wiederholung und ohne Unterbrechung zu umfahren". Math. Annalen 6.

///|
/// Find an Eulerian path (or circuit) in a directed graph, visiting every
/// edge exactly once.
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `edges`: list of `(u, v)` directed edges (parallel edges allowed)
///
/// ## Returns
/// `Some(path)` as a node sequence of length `edges.length() + 1` when an
/// Eulerian path exists, `None` otherwise. An empty edge list yields
/// `Some([])`.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V + E).
pub fn[N : Eq + Hash] eulerian_path(
  nodes : Array[N],
  edges : Array[(N, N)],
) -> Array[N]? {
  if edges.length() == 0 {
    return Some([])
  }
  let n = nodes.length()
  let index : Map[N, Int] = Map([])
  for i in 0..<n {
    index[nodes[i]] = i
  }
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { ([] : Array[Int]) })
  let out_deg : Array[Int] = Array::make(n, 0)
  let in_deg : Array[Int] = Array::make(n, 0)
  for edge in edges {
    let (u, v) = edge
    match (index.get(u), index.get(v)) {
      (Some(iu), Some(iv)) => {
        adj[iu].push(iv)
        out_deg[iu] += 1
        in_deg[iv] += 1
      }
      _ => return None
    }
  }
  // Degree conditions: at most one +1 surplus (start) and one -1 (end).
  let mut start = -1
  let mut plus_one = 0
  let mut minus_one = 0
  for i in 0..<n {
    let diff = out_deg[i] - in_deg[i]
    if diff == 1 {
      plus_one += 1
      start = i
    } else if diff == -1 {
      minus_one += 1
    } else if diff != 0 {
      return None
    }
  }
  if !((plus_one == 0 && minus_one == 0) || (plus_one == 1 && minus_one == 1)) {
    return None
  }
  if start < 0 {
    // Circuit case: start anywhere with an outgoing edge.
    for i in 0..<n {
      if out_deg[i] > 0 {
        start = i
        break
      }
    }
  }
  // Hierholzer with an explicit stack; edges consumed via per-node cursors.
  let cursor : Array[Int] = Array::make(n, 0)
  let stack : Array[Int] = [start]
  let circuit : Array[Int] = []
  //
  // 循环不变式（R10.1 · Hierholzer 欧拉路主循环 · 谓词见 @proofs.eulerian_trail_valid）:
  //
  //   (布尔陈述) cursor[u] 记录节点 u 已消费的出边数，故每条有向边至多被消费一次；显式栈
  //       stack 自底向上构成一条「未走完的当前路径」，而 circuit（逆序）累积的是已封闭的
  //       子回路节点序列，二者合起来恰覆盖所有已消费的边。
  //
  //   (初始化成立) 进入循环前 stack=[start]、circuit=[]、所有 cursor=0：尚未消费任何边，
  //       当前路径仅含起点，已封闭序列为空，命题平凡成立。
  //
  //   (迭代保持) 每步看栈顶 u：若其仍有未消费出边 (cursor[u] < 出度)，则消费一条边推进到 v
  //       并压栈（延长当前路径，cursor[u] 自增保证该边不再被走）；否则 u 无出边可走，弹栈并
  //       追加到 circuit（封闭一段子回路）。因每条边恰消费一次，循环至多迭代 O(V+E) 次后栈空
  //       终止；若最终 circuit 长度 ≠ |E|+1 说明图不连通、无欧拉路，逆转 circuit 即为所求路径。
  //
  while stack.length() > 0 {
    let u = stack[stack.length() - 1]
    if cursor[u] < adj[u].length() {
      let v = adj[u][cursor[u]]
      cursor[u] += 1
      stack.push(v)
    } else {
      circuit.push(u)
      let _ = stack.pop()
    }
  }
  // All edges must be consumed (otherwise the graph was disconnected).
  if circuit.length() != edges.length() + 1 {
    return None
  }
  circuit.rev_in_place()
  let path : Array[N] = []
  for i in circuit {
    path.push(nodes[i])
  }
  Some(path)
}
