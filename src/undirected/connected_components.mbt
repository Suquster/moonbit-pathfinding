// Connected Components of an undirected graph via BFS from each unvisited node.

///|
/// Compute the connected components of an undirected graph.
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `successors`: function returning neighbors of a node
///
/// ## Returns
/// An array of components, where each component is an array of nodes.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] connected_components(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Array[Array[N]] {
  let visited : Map[N, Bool] = Map([])
  let components : Array[Array[N]] = []
  //
  // 循环不变式（R10.1 · 连通分量主循环 · 谓词见 @proofs.components_partition_post）:
  //
  //   (布尔陈述) 已处理前若干个起点后，components 中各分量两两不相交，每个分量是
  //       一个极大连通子集，且 visited 恰等于 components 中所有节点的并集。
  //
  //   (初始化成立) 进入循环前 components 为空、visited 为空：空并集与空划分平凡满足
  //       不相交与「visited = 已收集节点」。
  //
  //   (迭代保持) 对尚未 visited 的起点 start 做一次 BFS，恰好收集到 start 所在的整个
  //       连通分量（内层 BFS 不变式保证可达即入队、入队即置 visited，故无遗漏无重复）。
  //       该分量节点此前均不在任何已记录分量中（否则 start 已被 visited），故与既有分量
  //       不相交；已 visited 的起点被 continue 跳过。每个节点至多被收集一次，循环终止。
  //
  for start in nodes {
    if visited.contains(start) {
      continue
    }
    // BFS to collect the component containing `start`.
    let queue : Array[N] = [start]
    let component : Array[N] = []
    visited[start] = true
    let mut head = 0
    while head < queue.length() {
      let cur = queue[head]
      head += 1
      component.push(cur)
      for next in successors(cur) {
        if !visited.contains(next) {
          visited[next] = true
          queue.push(next)
        }
      }
    }
    components.push(component)
  }
  components
}
