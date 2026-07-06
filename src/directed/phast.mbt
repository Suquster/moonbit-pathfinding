// phast.mbt —— PHAST（Delling et al. 2011）：CH 之上的一到全 SSSP。
//
// 批量最短路的行业标准：先从源点在向上图做（小规模）Dijkstra，再按
// rank 降序对全部节点做一次线性扫描，用「向下入边」（高 rank → 低
// rank，即 CH 的 bo 侧 CSR）松弛。扫描无堆、顺序访存，整体
// O(n + m_ch + 向上搜索)，真实路网上相对全量 Dijkstra 成倍加速，
// 且距离与原图 Dijkstra 完全一致（CH 向上/向下覆盖性保证）。

///|
/// 一到全最短距离（PHAST）。dist 长度须为 n，结果写入其中，
/// 不可达为 INF_DIST（可用 `is_unreachable` 判定）。
pub fn ContractionHierarchy::one_to_all(
  self : ContractionHierarchy,
  s : Int,
  dist : Array[Int64],
) -> Unit {
  let n = self.n
  guard s >= 0 && s < n && dist.length() == n
  for v in 0..<n {
    dist[v] = INF_DIST
  }
  // 阶段 1：向上 Dijkstra（搜索空间 O(polylog)，radix heap）。
  let mask = (1L << NODE_BITS) - 1L
  let heap = self.hf
  heap.reset(0L)
  dist[s] = 0L
  heap.push(s.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & mask).to_int()
    let du = enc >> NODE_BITS
    if du > dist[u] {
      continue
    }
    let stop = self.fo[u + 1]
    for ei = self.fo[u]; ei < stop; ei = ei + 1 {
      let v = self.ft[ei]
      let nd = du + self.fw[ei]
      if nd < dist[v] {
        dist[v] = nd
        heap.push((nd << NODE_BITS) | v.to_int64())
      }
    }
  }
  // 阶段 2：位置空间（rank 降序）线性扫描，向下入边松弛（无堆，
  // 边与源距离均顺序/近期访存，缓存友好）。先散射到位置空间。
  let pd = self.pd
  let ord = self.ord
  for i = 0; i < n; i = i + 1 {
    pd[i] = dist[ord[i]]
  }
  let dofs = self.dofs
  let dsrc = self.dsrc
  let dwt = self.dwt
  for i = 0; i < n; i = i + 1 {
    let stop = dofs[i + 1]
    let mut dv = pd[i]
    for ei = dofs[i]; ei < stop; ei = ei + 1 {
      let du = pd[dsrc[ei]]
      if du < INF_DIST {
        let nd = du + dwt[ei]
        if nd < dv {
          dv = nd
        }
      }
    }
    pd[i] = dv
  }
  // 收集回节点空间。
  for i = 0; i < n; i = i + 1 {
    dist[ord[i]] = pd[i]
  }
}

///|
/// 一到全最短路「树」（PHAST + 一次原图边扫描定父指针）。
/// dist/parent 长度须为 n；parent[v] 为树上前驱（源点与不可达
/// 节点为 -1）。g 须为构建本 CH 时的同一原图。距离先由 PHAST
/// 得到，再对每条原图边 u→v 以 dist[u]+w == dist[v] 认定树边，
/// 总计 O(n + m + 向上搜索)。
pub fn ContractionHierarchy::one_to_all_tree(
  self : ContractionHierarchy,
  g : WeightedCsr,
  s : Int,
  dist : Array[Int64],
  parent : Array[Int],
) -> Unit {
  let n = self.n
  guard g.node_count() == n && parent.length() == n
  self.one_to_all(s, dist)
  let mask = (1L << NODE_BITS) - 1L
  for v in 0..<n {
    parent[v] = -1
  }
  for u in 0..<n {
    if dist[u] >= INF_DIST {
      continue
    }
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let pe = g.packed[ei]
      let v = (pe & mask).to_int()
      // dist[u] < dist[v] 保证父链距离严格递减（无环；正权下必然）。
      if v != s &&
        parent[v] < 0 &&
        dist[u] < dist[v] &&
        dist[u] + (pe >> NODE_BITS) == dist[v] {
        parent[v] = u
      }
    }
  }
}

///|
/// PHAST 距离数组中的不可达判定。
pub fn ContractionHierarchy::is_unreachable(d : Int64) -> Bool {
  d >= INF_DIST
}
