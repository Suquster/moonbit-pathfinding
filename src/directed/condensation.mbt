// SCC condensation: collapse strongly connected components into a DAG.
//
// Builds on `tarjan_scc`; the resulting component graph is acyclic, which
// enables DAG-only algorithms (topological sort, DAG shortest path) on
// arbitrary directed graphs.

///|
/// Condensation of a directed graph: its strongly connected components plus
/// the edges between distinct components.
pub struct Condensation[N] {
  /// The strongly connected components (each an array of original nodes).
  components : Array[Array[N]]
  /// `component_of[node]` = index into `components`.
  component_of : Map[N, Int]
  /// Deduplicated edges `(from_component, to_component)` of the DAG.
  dag_edges : Array[(Int, Int)]
}

///|
/// Compute the condensation DAG of a directed graph.
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `successors`: function returning the out-neighbors of a node
///
/// ## Returns
/// A `Condensation` with the component list, a node→component map, and the
/// deduplicated inter-component edges (guaranteed acyclic).
///
/// ## Complexity
/// Time: O(V + E). Space: O(V + E).
pub fn[N : Eq + Hash] condensation(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Condensation[N] {
  let components = tarjan_scc(nodes, successors)
  let component_of : Map[N, Int] = Map([])
  for i in 0..<components.length() {
    for node in components[i] {
      component_of[node] = i
    }
  }
  let seen : Map[(Int, Int), Bool] = Map([])
  let dag_edges : Array[(Int, Int)] = []
  //
  // 循环不变式（R10.1 · SCC 缩点 DAG 构造主循环 · 谓词见 @proofs.condensation_is_dag）:
  //
  //   (布尔陈述) 已扫描前若干节点后，dag_edges 恰为「已见到的、连接两个不同 SCC 的有序对
  //       (cu,cv)」去重集合；seen 与 dag_edges 内容一致（seen[(cu,cv)]==true 当且仅当该对
  //       已入 dag_edges）。component_of 给出每个节点到其 SCC 下标的映射。
  //
  //   (初始化成立) 进入循环前 dag_edges 为空、seen 为空：无跨分量边被记录，二者平凡一致。
  //
  //   (迭代保持) 对节点 node（属 SCC cu）的每条出边 (node,v)（v 属 SCC cv），仅当 cu≠cv 且
  //       (cu,cv) 未见过时记入 dag_edges 并标记 seen，保证去重与一致性。同一 SCC 内的边
  //       (cu==cv) 被跳过，故结果不含自环；又因 SCC 是极大强连通子图，缩点后不可能有环
  //       （否则两 SCC 应合并），所得 dag_edges 必为 DAG。每节点恰扫描一次，循环终止。
  //
  for node in nodes {
    match component_of.get(node) {
      Some(cu) =>
        for v in successors(node) {
          match component_of.get(v) {
            Some(cv) =>
              if cu != cv && !seen.contains((cu, cv)) {
                seen[(cu, cv)] = true
                dag_edges.push((cu, cv))
              }
            None => ()
          }
        }
      None => ()
    }
  }
  { components, component_of, dag_edges }
}
