// dijkstra_indexed.mbt —— 稠密整数节点 Dijkstra / A* 快路径。
//
// 通用 `dijkstra` / `astar` 以 `Map[N, W]` 承载 dist/parents，泛型 +
// 哈希 + 元组装箱在「节点即 0..n-1 整数、权重即 Int」的稠密图
// （本库基准/评测主负载）上是纯开销。本变体以扁平 Array 承载全部
// 状态 + 带权 CSR 邻接 + 单数组编码 (dist << 20 | node) 二叉堆，
// 语义与通用版一致（同一图上最短代价相同），由差分 PBT 守卫。

///|
/// 稠密整数节点带权图的 CSR 邻接：节点 u 的出边为
/// `(targets[k], weights[k])`，k ∈ [offsets[u], offsets[u+1])。
pub struct WeightedCsr {
  offsets : Array[Int]
  targets : Array[Int]
  weights : Array[Int]
}

///|
/// 由边集 (u, v, w) 构建带权 CSR。O(V + E)。
pub fn WeightedCsr::from_edges(
  n : Int,
  edges : Array[(Int, Int, Int)],
) -> WeightedCsr {
  let counts = Array::make(n + 1, 0)
  for e in edges {
    let (u, _, _) = e
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
  let weights = Array::make(edges.length(), 0)
  for e in edges {
    let (u, v, w) = e
    targets[cursor[u]] = v
    weights[cursor[u]] = w
    cursor[u] = cursor[u] + 1
  }
  { offsets, targets, weights }
}

///|
/// 节点数。
pub fn WeightedCsr::node_count(self : WeightedCsr) -> Int {
  self.offsets.length() - 1
}

///|
/// 编码堆：Int64 键 = (优先级 << 21) | node（node < 2^21）。
/// 单数组、无装箱、siftup/siftdown 手写。
priv struct EncodedHeap {
  data : Array[Int64]
  mut len : Int
}

///|
fn EncodedHeap::new(cap : Int) -> EncodedHeap {
  { data: Array::make(cap, 0L), len: 0 }
}

///|
fn EncodedHeap::push(self : EncodedHeap, key : Int64) -> Unit {
  if self.len == self.data.length() {
    self.data.push(key)
  } else {
    self.data[self.len] = key
  }
  let mut i = self.len
  self.len = self.len + 1
  while i > 0 {
    let p = (i - 1) / 2
    if self.data[p] <= self.data[i] {
      break
    }
    let t = self.data[p]
    self.data[p] = self.data[i]
    self.data[i] = t
    i = p
  }
}

///|
fn EncodedHeap::pop(self : EncodedHeap) -> Int64 {
  let top = self.data[0]
  self.len = self.len - 1
  if self.len > 0 {
    self.data[0] = self.data[self.len]
    let mut i = 0
    while true {
      let l = 2 * i + 1
      if l >= self.len {
        break
      }
      let r = l + 1
      let c = if r < self.len && self.data[r] < self.data[l] { r } else { l }
      if self.data[i] <= self.data[c] {
        break
      }
      let t = self.data[i]
      self.data[i] = self.data[c]
      self.data[c] = t
      i = c
    }
  }
  top
}

///|
/// 节点编码位宽（支持 n < 2^21 ≈ 2M 节点；更大规模用通用版）。
const NODE_BITS : Int = 21

///|
/// 稠密整数节点 Dijkstra：`start` 到 `target` 的最小代价路径。
/// 扁平 dist/parent 数组 + 编码二叉堆（懒删除），无哈希无装箱。
/// 要求：节点数 < 2^21、边权非负、总代价 < 2^42。
/// 返回 `Some((path, cost))` 或 `None`。O((V+E) log V)。
pub fn dijkstra_indexed(
  g : WeightedCsr,
  start : Int,
  target : Int,
) -> (Array[Int], Int)? {
  dijkstra_indexed_h(g, start, target, None)
}

///|
/// 稠密整数节点 A*：可采纳启发式 `h`（None 即零启发式 = Dijkstra）。
/// f = g + h 入堆、g 存 dist；其余同 `dijkstra_indexed`。
pub fn astar_indexed(
  g : WeightedCsr,
  start : Int,
  target : Int,
  h : (Int) -> Int,
) -> (Array[Int], Int)? {
  dijkstra_indexed_h(g, start, target, Some(h))
}

///|
fn dijkstra_indexed_h(
  g : WeightedCsr,
  start : Int,
  target : Int,
  h : ((Int) -> Int)?,
) -> (Array[Int], Int)? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  let inf = 0x3FFF_FFFF_FFFFL
  let dist : Array[Int64] = Array::make(n, inf)
  let parent = Array::make(n, -1)
  let heap = EncodedHeap::new(16)
  dist[start] = 0L
  let h0 : Int64 = match h {
    Some(hf) => hf(start).to_int64()
    None => 0L
  }
  heap.push((h0 << NODE_BITS) | start.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
    let f = enc >> NODE_BITS
    let du = dist[u]
    // 陈旧条目：f = du + h(u)，若 f 对应的 g 超过当前 dist 则跳过。
    let hu : Int64 = match h {
      Some(hf) => hf(u).to_int64()
      None => 0L
    }
    if f - hu > du {
      continue
    }
    if u == target {
      let path = [u]
      let mut node = u
      while node != start {
        node = parent[node]
        path.push(node)
      }
      path.rev_in_place()
      return Some((path, du.to_int()))
    }
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let v = g.targets[ei]
      let nd = du + g.weights[ei].to_int64()
      if nd < dist[v] {
        dist[v] = nd
        parent[v] = u
        let fv : Int64 = match h {
          Some(hf) => nd + hf(v).to_int64()
          None => nd
        }
        heap.push((fv << NODE_BITS) | v.to_int64())
      }
    }
  }
  None
}
