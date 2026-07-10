// alt.mbt —— ALT（A* + Landmarks + Triangle inequality，Goldberg &
// Harrelson 2005）地标启发式预处理。
//
// 预处理：farthest 策略选 k 个地标 L_i，分别在 g / rg 上跑全量
// Dijkstra，得 d(L_i, ·)（正向可达距离）与 d(·, L_i)（反向，经逆图）。
// 查询：三角不等式给出一致（consistent）下界
//   dist(u, t) ≥ max_i max( d(u,L_i) − d(t,L_i), d(L_i,t) − d(L_i,u) )
// 该下界可直接喂给 `astar_indexed_ctx` / `astar_bidirectional_ctx`，
// 批量查询（同图多 s-t 对）时预处理成本被摊薄。

///|
/// ALT 地标距离表：k 个地标的正/反向全源距离。内存布局为
/// **节点主序**（`u * k + i`，已经 `alt_cap` 截断）：h 求値时 k 个
/// 地标项连续读，缓存友好。
pub struct AltLandmarks {
  /// 地标数。
  k : Int
  /// 图节点数。
  n : Int
  /// dist_from[u*k + i] = cap(d(L_i, u))（沿 g）。
  dist_from : Array[Int64]
  /// dist_to[u*k + i] = cap(d(u, L_i))（沿 rg，即 g 的逆图）。
  dist_to : Array[Int64]
}

///|
/// 全量 Dijkstra 一到全最短距离（无目标提前退出），dist 长度须为 n，
/// 不可达为 `INF_DIST`（PHAST 的原图基线，语义一致）。
pub fn dijkstra_one_to_all(
  g : WeightedCsr,
  src : Int,
  dist : Array[Int64],
) -> Unit {
  guard src >= 0 && src < g.node_count() && dist.length() == g.node_count()
  alt_sssp(g, src, dist, 0)
}

///|
/// 全量 Dijkstra（无目标提前退出），结果写入 out[base + u]；
/// 不可达为 `INF_DIST`。
fn alt_sssp(g : WeightedCsr, src : Int, out : Array[Int64], base : Int) -> Unit {
  let n = g.node_count()
  for u in 0..<n {
    out[base + u] = INF_DIST
  }
  let heap = RadixHeap::new()
  out[base + src] = 0L
  heap.push(src.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
    let du = enc >> NODE_BITS
    if du > out[base + u] {
      continue
    }
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let pe = g.packed[ei]
      let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
      let nd = du + (pe >> NODE_BITS)
      if nd < out[base + v] {
        out[base + v] = nd
        heap.push((nd << NODE_BITS) | v.to_int64())
      }
    }
  }
}

///|
/// 构建 k 个地标（farthest 选点：迭代取「到已选地标集的最小距离」
/// 最大的可达节点）。预处理共 (k+1) 次 g 上 + k 次 rg 上的全量
/// Dijkstra，O(k (E + V log V))。不同可达分量之间的距离视为无穷，
/// 因而优先为尚未覆盖的分量播种；k 会被截到 [1, n]，空图取 0。
pub fn AltLandmarks::build(
  g : WeightedCsr,
  rg : WeightedCsr,
  k : Int,
) -> AltLandmarks {
  let n = g.node_count()
  if n == 0 {
    return { k: 0, n: 0, dist_from: [], dist_to: [] }
  }
  let kk = if k < 1 { 1 } else if k > n { n } else { k }
  let dist_from = Array::make(kk * n, ALT_CAP)
  let dist_to = Array::make(kk * n, ALT_CAP)
  // 种子扫描：从节点 0 出发，取最远可达点为第一个地标。
  let row_f = Array::make(n, INF_DIST)
  let row_t = Array::make(n, INF_DIST)
  alt_sssp(g, 0, row_f, 0)
  let mut first = 0
  let mut best = -1L
  for u in 0..<n {
    if row_f[u] < INF_DIST && row_f[u] > best {
      best = row_f[u]
      first = u
    }
  }
  let lms = Array::make(kk, first)
  let selected = Array::make(n, false)
  selected[first] = true
  // min_d[u] = u 到已选地标集的最小（取正/反向较小者）距离。
  let min_d = Array::make(n, INF_DIST)
  for i in 0..<kk {
    alt_sssp(g, lms[i], row_f, 0)
    alt_sssp(rg, lms[i], row_t, 0)
    for u in 0..<n {
      dist_from[u * kk + i] = alt_cap(row_f[u])
      dist_to[u * kk + i] = alt_cap(row_t[u])
    }
    if i + 1 < kk {
      for u in 0..<n {
        let d1 = row_f[u]
        let d2 = row_t[u]
        let dm = if d1 < d2 { d1 } else { d2 }
        if dm < min_d[u] {
          min_d[u] = dm
        }
      }
      let mut nxt = 0
      while selected[nxt] {
        nxt = nxt + 1
      }
      let mut far = min_d[nxt]
      for u in (nxt + 1)..<n {
        if selected[u] {
          continue
        }
        if far < INF_DIST && (min_d[u] >= INF_DIST || min_d[u] > far) {
          far = min_d[u]
          nxt = u
        }
      }
      lms[i + 1] = nxt
      selected[nxt] = true
    }
  }
  { k: kk, n, dist_from, dist_to }
}

///|
/// 不可达距离的统一截断常数：把 INF 截为同一有限値后，三角不等式
/// 下界对任意可达性组合仍可采纳且一致（截断项为正仅当对应
/// s-t 不可达）；取 2^30−1 避免 f 编码（左移 21 位）溢出。
const ALT_CAP : Int64 = 0x3FFF_FFFFL

///|
fn alt_cap(d : Int64) -> Int64 {
  if d > ALT_CAP {
    ALT_CAP
  } else {
    d
  }
}

///|
/// 正向下界：dist(u, target) 的一致下界（喂给正向 A* 的 h_f）。
pub fn AltLandmarks::h_to(self : AltLandmarks, u : Int, target : Int) -> Int {
  let k = self.k
  let bu = u * k
  let bt = target * k
  let mut best = 0L
  for i in 0..<k {
    let d1 = self.dist_to[bu + i] - self.dist_to[bt + i] // d(u,L)−d(t,L)
    if d1 > best {
      best = d1
    }
    let d2 = self.dist_from[bt + i] - self.dist_from[bu + i] // d(L,t)−d(L,u)
    if d2 > best {
      best = d2
    }
  }
  best.to_int()
}

///|
/// 反向下界：dist(start, u) 的一致下界（喂给反向 A* 的 h_b）。
pub fn AltLandmarks::h_from(self : AltLandmarks, u : Int, start : Int) -> Int {
  let k = self.k
  let bu = u * k
  let bs = start * k
  let mut best = 0L
  for i in 0..<k {
    let d1 = self.dist_from[bu + i] - self.dist_from[bs + i] // d(L,u)−d(L,s)
    if d1 > best {
      best = d1
    }
    let d2 = self.dist_to[bs + i] - self.dist_to[bu + i] // d(s,L)−d(u,L)
    if d2 > best {
      best = d2
    }
  }
  best.to_int()
}

///|
/// 预绑定 target 的正向下界闭包（批量同 target 查询时免重复寻址）。
pub fn AltLandmarks::h_to_closure(
  self : AltLandmarks,
  target : Int,
) -> (Int) -> Int {
  let k = self.k
  let dist_to = self.dist_to
  let dist_from = self.dist_from
  let bt = target * k
  fn(u) {
    let bu = u * k
    let mut best = 0L
    for i in 0..<k {
      let d1 = dist_to[bu + i] - dist_to[bt + i]
      if d1 > best {
        best = d1
      }
      let d2 = dist_from[bt + i] - dist_from[bu + i]
      if d2 > best {
        best = d2
      }
    }
    best.to_int()
  }
}

///|
/// 预绑定 start 的反向下界闭包。
pub fn AltLandmarks::h_from_closure(
  self : AltLandmarks,
  start : Int,
) -> (Int) -> Int {
  let k = self.k
  let dist_to = self.dist_to
  let dist_from = self.dist_from
  let bs = start * k
  fn(u) {
    let bu = u * k
    let mut best = 0L
    for i in 0..<k {
      let d1 = dist_from[bu + i] - dist_from[bs + i]
      if d1 > best {
        best = d1
      }
      let d2 = dist_to[bs + i] - dist_to[bu + i]
      if d2 > best {
        best = d2
      }
    }
    best.to_int()
  }
}
