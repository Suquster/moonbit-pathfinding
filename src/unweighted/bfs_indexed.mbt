// bfs_indexed.mbt —— 稠密整数节点 BFS 快路径。
//
// 通用 `bfs` 以 `Map[N, _]` 承载 visited/parents，泛型 + 哈希在
// 「节点即 0..n-1 整数」的稠密图（本库基准/评测主负载）上是纯开销。
// 本变体以扁平 Array 承载全部状态 + CSR 邻接，语义与通用版逐位一致
// （同一图上返回路径边数相同），由差分 PBT 守卫。

///|
/// 稠密整数节点图的 CSR（compressed sparse row）邻接：
/// 节点 u 的后继为 `targets[offsets[u]..offsets[u+1])`。
pub struct CsrGraph {
  offsets : Array[Int]
  targets : Array[Int]
}

///|
/// 由边集 (u, v) 构建 CSR。O(V + E)。
pub fn CsrGraph::from_edges(n : Int, edges : Array[(Int, Int)]) -> CsrGraph {
  let counts = Array::make(n + 1, 0)
  for e in edges {
    let (u, _) = e
    counts[u + 1] = counts[u + 1] + 1
  }
  for i in 1..<=n {
    counts[i] = counts[i] + counts[i - 1]
  }
  let offsets = counts.copy()
  let cursor = Array::make(n, 0)
  for u in 0..<n {
    cursor[u] = offsets[u]
  }
  let targets = Array::make(edges.length(), 0)
  for e in edges {
    let (u, v) = e
    targets[cursor[u]] = v
    cursor[u] = cursor[u] + 1
  }
  { offsets, targets }
}

///|
/// 节点数。
pub fn CsrGraph::node_count(self : CsrGraph) -> Int {
  self.offsets.length() - 1
}

///|
/// 稠密整数节点 BFS：起点 `start` 到 `target` 的最短（边数）路径。
/// 状态全部为扁平数组（visited 位、parent 指针、环形队列），无哈希。
/// 返回 `Some(path)`（含两端）或 `None`。O(V + E)。
pub fn bfs_indexed(g : CsrGraph, start : Int, target : Int) -> Array[Int]? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if start == target {
    return Some([start])
  }
  let parent = Array::make(n, -2) // -2 = 未访问，-1 = 起点根
  parent[start] = -1
  let queue = Array::make(n, 0)
  queue[0] = start
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let cur = queue[head]
    head = head + 1
    let stop = g.offsets[cur + 1]
    for ei = g.offsets[cur]; ei < stop; ei = ei + 1 {
      let next = g.targets[ei]
      if parent[next] != -2 {
        continue
      }
      parent[next] = cur
      if next == target {
        let path = [next]
        let mut node = next
        while parent[node] >= 0 {
          node = parent[node]
          path.push(node)
        }
        path.rev_in_place()
        return Some(path)
      }
      queue[tail] = next
      tail = tail + 1
    }
  }
  None
}
