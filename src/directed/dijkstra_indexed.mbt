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
  /// 打包边：(weight << 21) | target——边扫描单数组顺序读，减半访存。
  packed : Array[Int64]
  /// 最大边权（用于 Dial 桶队列适用性判断）。
  max_weight : Int
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
  let packed = Array::make(edges.length(), 0L)
  let mut max_weight = 0
  for e in edges {
    let (u, v, w) = e
    targets[cursor[u]] = v
    weights[cursor[u]] = w
    packed[cursor[u]] = (w.to_int64() << NODE_BITS) | v.to_int64()
    cursor[u] = cursor[u] + 1
    if w > max_weight {
      max_weight = w
    }
  }
  { offsets, targets, weights, packed, max_weight }
}

///|
/// 节点数。
pub fn WeightedCsr::node_count(self : WeightedCsr) -> Int {
  self.offsets.length() - 1
}

///|
/// 编码堆：Int64 键 = (优先级 << 21) | node（node < 2^21）。
/// 4 叉堆（更浅、缓存更友好）、单数组、无装箱、siftup/siftdown 手写、
/// 上滤/下滤用「持洞」写法（每层一次赋值，避免三步交换）。
struct EncodedHeap {
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
  }
  let mut i = self.len
  self.len = self.len + 1
  while i > 0 {
    let p = (i - 1) / 4
    if self.data[p] <= key {
      break
    }
    self.data[i] = self.data[p]
    i = p
  }
  self.data[i] = key
}

///|
fn EncodedHeap::pop(self : EncodedHeap) -> Int64 {
  let top = self.data[0]
  self.len = self.len - 1
  if self.len > 0 {
    let last = self.data[self.len]
    let mut i = 0
    while true {
      let base = 4 * i + 1
      if base >= self.len {
        break
      }
      let mut c = base
      let mut ck = self.data[base]
      let stop = if base + 4 < self.len { base + 4 } else { self.len }
      for j = base + 1; j < stop; j = j + 1 {
        if self.data[j] < ck {
          c = j
          ck = self.data[j]
        }
      }
      if last <= ck {
        break
      }
      self.data[i] = ck
      i = c
    }
    self.data[i] = last
  }
  top
}

///|
/// 节点编码位宽（支持 n < 2^21 ≈ 2M 节点；更大规模用通用版）。
const NODE_BITS : Int = 21

///|
/// 可复用搜索上下文：dist/parent/代戳数组只分配一次，跨查询用
/// generation 戳懒失效（免去每查询 O(n) 清零——批量查询的主开销之一）。
pub struct SearchCtx {
  dist : Array[Int64]
  parent : Array[Int]
  stamp : Array[Int]
  closed : Array[Int]
  mut gen : Int
  heap : EncodedHeap
  bkt : Array[Array[Int64]]
  ov : Array[Int64]
}

///|
/// 为节点数 n 的图创建可复用上下文。
pub fn SearchCtx::new(n : Int) -> SearchCtx {
  {
    dist: Array::make(n, 0L),
    parent: Array::make(n, -1),
    stamp: Array::make(n, 0),
    closed: Array::make(n, 0),
    gen: 0,
    heap: EncodedHeap::new(16),
    bkt: [],
    ov: [],
  }
}

///|
/// 取出容量 ≥ m 且全空的可复用 Dial 桶数组（跨查询复用，免去每次
/// 分配 m 个空数组——小图批量查询的主要分配开销）。
fn SearchCtx::dial_buckets(self : SearchCtx, m : Int) -> Array[Array[Int64]] {
  while self.bkt.length() < m {
    self.bkt.push([])
  }
  for i in 0..<m {
    self.bkt[i].clear()
  }
  self.ov.clear()
  self.bkt
}

///|
/// Dial 桶队列适用上限：最大边权 ≤ 此值时 `dijkstra_indexed_ctx`
/// 自动切换 Dial（Dial 1969，O(E + D) D=最远结算距离）。
const DIAL_MAX_W : Int = 1024

///|
/// Dial 桶队列 Dijkstra（小整数边权专用）：C+1 个循环桶按 tentative
/// 距离取模散列，逐距离推进；无堆、无比较，O(E + D)。语义与
/// `dijkstra_indexed` 一致，由差分 PBT 守卫。
fn dial_indexed_ctx(
  g : WeightedCsr,
  ctx : SearchCtx,
  start : Int,
  target : Int,
) -> (Array[Int], Int)? {
  ctx.gen = ctx.gen + 1
  let gen = ctx.gen
  let dist = ctx.dist
  let parent = ctx.parent
  let stamp = ctx.stamp
  let m = g.max_weight + 1
  let buckets = ctx.dial_buckets(m)
  dist[start] = 0L
  stamp[start] = gen
  parent[start] = -1
  buckets[0].push(start.to_int64())
  let mut pending = 1
  let mut d = 0L
  let mut cur = 0 // d 对应的桶下标（增量维护，免逐次取模除法）
  let inf = 0x3FFF_FFFF_FFFFL
  while pending > 0 {
    let b = buckets[cur]
    // 用下标推进：零权边可能在处理中向当前桶追加。
    let mut bi = 0
    while bi < b.length() {
      let u = b[bi].to_int()
      bi = bi + 1
      pending = pending - 1
      if dist[u] != d {
        continue // 陈旧条目（已被更小 tentative 距离取代）
      }
      if u == target {
        let path = [u]
        let mut node = u
        while node != start {
          node = parent[node]
          path.push(node)
        }
        path.rev_in_place()
        return Some((path, d.to_int()))
      }
      let stop = g.offsets[u + 1]
      for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
        let pe = g.packed[ei]
        let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
        let nd = d + (pe >> NODE_BITS)
        let dv = if stamp[v] == gen { dist[v] } else { inf }
        if nd < dv {
          dist[v] = nd
          stamp[v] = gen
          parent[v] = u
          let mut slot = cur + (nd - d).to_int()
          if slot >= m {
            slot = slot - m
          }
          buckets[slot].push(v.to_int64())
          pending = pending + 1
        }
      }
    }
    b.clear()
    d = d + 1L
    cur = cur + 1
    if cur == m {
      cur = 0
    }
  }
  None
}

///|
/// 复用上下文的 Dijkstra（语义与 `dijkstra_indexed` 一致；批量查询时
/// 免每次 O(n) 数组初始化）。小整数边权（≤ 1024）自动切换 Dial 桶
/// 队列，否则走 4 叉编码堆。上下文的容量必须 ≥ 图节点数。
pub fn dijkstra_indexed_ctx(
  g : WeightedCsr,
  ctx : SearchCtx,
  start : Int,
  target : Int,
) -> (Array[Int], Int)? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if g.max_weight <= DIAL_MAX_W && g.max_weight > 0 {
    return dial_indexed_ctx(g, ctx, start, target)
  }
  ctx.gen = ctx.gen + 1
  let gen = ctx.gen
  let dist = ctx.dist
  let parent = ctx.parent
  let stamp = ctx.stamp
  let heap = ctx.heap
  heap.len = 0
  let inf = 0x3FFF_FFFF_FFFFL
  dist[start] = 0L
  stamp[start] = gen
  parent[start] = -1
  heap.push(start.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
    let du = dist[u]
    if enc >> NODE_BITS > du {
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
      let pe = g.packed[ei]
      let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
      let nd = du + (pe >> NODE_BITS)
      let dv = if stamp[v] == gen { dist[v] } else { inf }
      if nd < dv {
        dist[v] = nd
        stamp[v] = gen
        parent[v] = u
        heap.push((nd << NODE_BITS) | v.to_int64())
      }
    }
  }
  None
}

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
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  let inf = 0x3FFF_FFFF_FFFFL
  let dist : Array[Int64] = Array::make(n, inf)
  let parent = Array::make(n, -1)
  let heap = EncodedHeap::new(16)
  dist[start] = 0L
  heap.push(start.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
    let du = dist[u]
    if enc >> NODE_BITS > du {
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
      let pe = g.packed[ei]
      let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
      let nd = du + (pe >> NODE_BITS)
      if nd < dist[v] {
        dist[v] = nd
        parent[v] = u
        heap.push((nd << NODE_BITS) | v.to_int64())
      }
    }
  }
  None
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
  astar_indexed_h(g, start, target, h)
}

///|
/// 桶式 A*（小整数边权 + 一致启发式专用）：f = g + h 落 Dial 循环桶，
/// 一致性保证弹出 f 单调不减；f 增量超窗（> max_weight，一般有向图
/// 下 h 落差可致）的条目进 overflow，窗口推进整圈时再重分发——正确性
/// 不依赖增量上界。无堆无比较。
fn astar_dial_ctx(
  g : WeightedCsr,
  ctx : SearchCtx,
  start : Int,
  target : Int,
  h : (Int) -> Int,
) -> (Array[Int], Int)? {
  ctx.gen = ctx.gen + 1
  let gen = ctx.gen
  let dist = ctx.dist
  let parent = ctx.parent
  let stamp = ctx.stamp
  let closed = ctx.closed
  let m = g.max_weight + 1
  let m64 = m.to_int64()
  let buckets = ctx.dial_buckets(m)
  let overflow = ctx.ov
  dist[start] = 0L
  stamp[start] = gen
  parent[start] = -1
  let f0 = h(start).to_int64()
  let mut d = f0 // 当前扫描的 f 值
  let mut cur = (f0 % m64).to_int() // d 对应的桶下标（增量维护，免逐次取模除法）
  let mut window_end = f0 + m64 // 桶窗口 [d, window_end)
  buckets[cur].push((f0 << NODE_BITS) | start.to_int64())
  let mut pending = 1
  while pending > 0 {
    if d >= window_end {
      // 窗口推进整圈：把 overflow 中落入新窗口的条目重分发。
      // 若剩余条目全在 overflow 且都超窗，直接把窗口跳到最小 f，
      // 避免逐 d 空扫。
      if overflow.length() == pending && overflow.length() > 0 {
        let mut fmin = overflow[0] >> NODE_BITS
        for w in 1..<overflow.length() {
          let f = overflow[w] >> NODE_BITS
          if f < fmin {
            fmin = f
          }
        }
        if fmin > d {
          d = fmin
        }
      }
      cur = (d % m64).to_int()
      window_end = d + m64
      let mut w = 0
      while w < overflow.length() {
        let enc = overflow[w]
        if enc >> NODE_BITS < window_end {
          let mut slot = cur + ((enc >> NODE_BITS) - d).to_int()
          if slot >= m {
            slot = slot - m
          }
          buckets[slot].push(enc)
          let last = overflow.length() - 1
          overflow[w] = overflow[last]
          overflow.pop() |> ignore
        } else {
          w = w + 1
        }
      }
    }
    let b = buckets[cur]
    let mut bi = 0
    while bi < b.length() {
      let enc = b[bi]
      bi = bi + 1
      pending = pending - 1
      let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
      if closed[u] == gen {
        continue
      }
      closed[u] = gen
      let du = dist[u]
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
        let pe = g.packed[ei]
        let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
        let nd = du + (pe >> NODE_BITS)
        let dv = if stamp[v] == gen { dist[v] } else { INF_DIST }
        if nd < dv {
          dist[v] = nd
          stamp[v] = gen
          parent[v] = u
          let nf = nd + h(v).to_int64()
          let nenc = (nf << NODE_BITS) | v.to_int64()
          if nf < window_end {
            let mut slot = cur + (nf - d).to_int()
            if slot >= m {
              slot = slot - m
            }
            buckets[slot].push(nenc)
          } else {
            overflow.push(nenc)
          }
          pending = pending + 1
        }
      }
    }
    b.clear()
    d = d + 1L
    cur = cur + 1
    if cur == m {
      cur = 0
    }
  }
  None
}

///|
const INF_DIST : Int64 = 0x3FFF_FFFF_FFFFL

///|
/// 双向 Dial Dijkstra（小整数边权专用）：正向沿 `g`、反向沿 `rg`
/// （g 的逆图）各自跑 Dial 桶扫描，每轮推进当前扫描距离较小的一侧；
/// 松弛时用对侧 tentative 距离维护会合上界 μ，d_f + d_b > μ 时终止
/// （meet-in-the-middle 经典判据）。语义与 `dijkstra_indexed` 一致
/// （代价最优；路径可能不同但逐边合法），差分 PBT 守卫。
pub fn dijkstra_bidirectional_ctx(
  g : WeightedCsr,
  rg : WeightedCsr,
  ctx_f : SearchCtx,
  ctx_b : SearchCtx,
  start : Int,
  target : Int,
) -> (Array[Int], Int)? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if start == target {
    return Some(([start], 0))
  }
  if g.max_weight > DIAL_MAX_W || g.max_weight <= 0 {
    // 大权/零权：走堆式双向（零启发式 NBA*，meet-in-the-middle）。
    return astar_biheap_ctx(g, rg, ctx_f, ctx_b, start, target, zero_h, zero_h)
  }
  ctx_f.gen = ctx_f.gen + 1
  ctx_b.gen = ctx_b.gen + 1
  let gf = ctx_f.gen
  let gb = ctx_b.gen
  let df = ctx_f.dist
  let db = ctx_b.dist
  let pf = ctx_f.parent
  let pb = ctx_b.parent
  let sf = ctx_f.stamp
  let sb = ctx_b.stamp
  let m = g.max_weight + 1
  let bf = ctx_f.dial_buckets(m)
  let bb = ctx_b.dial_buckets(m)
  df[start] = 0L
  sf[start] = gf
  pf[start] = -1
  bf[0].push(start.to_int64())
  db[target] = 0L
  sb[target] = gb
  pb[target] = -1
  bb[0].push(target.to_int64())
  let mut pend_f = 1
  let mut pend_b = 1
  let mut d_f = 0L
  let mut d_b = 0L
  let mut cur_f = 0 // d_f 对应的桶下标（增量维护，免逐次取模除法）
  let mut cur_b = 0
  let mut mu = INF_DIST
  let mut meet = -1
  while pend_f > 0 && pend_b > 0 {
    if d_f + d_b > mu {
      break
    }
    if d_f <= d_b {
      // 正向推进一个距离值。
      let b = bf[cur_f]
      let mut bi = 0
      while bi < b.length() {
        let u = b[bi].to_int()
        bi = bi + 1
        pend_f = pend_f - 1
        if df[u] != d_f {
          continue
        }
        let stop = g.offsets[u + 1]
        for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
          let pe = g.packed[ei]
          let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
          let nd = d_f + (pe >> NODE_BITS)
          let dv = if sf[v] == gf { df[v] } else { INF_DIST }
          if nd < dv {
            df[v] = nd
            sf[v] = gf
            pf[v] = u
            let mut slot = cur_f + (nd - d_f).to_int()
            if slot >= m {
              slot = slot - m
            }
            bf[slot].push(v.to_int64())
            pend_f = pend_f + 1
            if sb[v] == gb && nd + db[v] < mu {
              mu = nd + db[v]
              meet = v
            }
          }
        }
      }
      b.clear()
      d_f = d_f + 1L
      cur_f = cur_f + 1
      if cur_f == m {
        cur_f = 0
      }
    } else {
      // 反向推进一个距离值（rg 出边 = g 入边）。
      let b = bb[cur_b]
      let mut bi = 0
      while bi < b.length() {
        let u = b[bi].to_int()
        bi = bi + 1
        pend_b = pend_b - 1
        if db[u] != d_b {
          continue
        }
        let stop = rg.offsets[u + 1]
        for ei = rg.offsets[u]; ei < stop; ei = ei + 1 {
          let pe = rg.packed[ei]
          let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
          let nd = d_b + (pe >> NODE_BITS)
          let dv = if sb[v] == gb { db[v] } else { INF_DIST }
          if nd < dv {
            db[v] = nd
            sb[v] = gb
            pb[v] = u
            let mut slot = cur_b + (nd - d_b).to_int()
            if slot >= m {
              slot = slot - m
            }
            bb[slot].push(v.to_int64())
            pend_b = pend_b + 1
            if sf[v] == gf && nd + df[v] < mu {
              mu = nd + df[v]
              meet = v
            }
          }
        }
      }
      b.clear()
      d_b = d_b + 1L
      cur_b = cur_b + 1
      if cur_b == m {
        cur_b = 0
      }
    }
  }
  if meet < 0 {
    return None
  }
  let path = [meet]
  let mut node = meet
  while pf[node] >= 0 {
    node = pf[node]
    path.push(node)
  }
  path.rev_in_place()
  node = meet
  while pb[node] >= 0 {
    node = pb[node]
    path.push(node)
  }
  Some((path, mu.to_int()))
}

///|
/// 桶式双向 A*（小整数边权 + 双侧一致启发式专用）：正/反两侧各自
/// 用 Dial 循环桶（f 取模散列 + 超窗 overflow 重分发）扫描，每轮
/// 推进当前扫描 f 较小一侧一个 f 值；NBA* 剪枝（f(u) ≥ μ 或
/// g(u) + F_other − h_other(u) ≥ μ）+ 双侧 f 扫描值均 ≥ μ 即终止。
/// 无堆无比较。
fn astar_bidial_ctx(
  g : WeightedCsr,
  rg : WeightedCsr,
  ctx_f : SearchCtx,
  ctx_b : SearchCtx,
  start : Int,
  target : Int,
  h_f : (Int) -> Int,
  h_b : (Int) -> Int,
) -> (Array[Int], Int)? {
  ctx_f.gen = ctx_f.gen + 1
  ctx_b.gen = ctx_b.gen + 1
  let gf = ctx_f.gen
  let gb = ctx_b.gen
  let df = ctx_f.dist
  let db = ctx_b.dist
  let pf = ctx_f.parent
  let pb = ctx_b.parent
  let sf = ctx_f.stamp
  let sb = ctx_b.stamp
  let cf = ctx_f.closed
  let cb = ctx_b.closed
  let m = g.max_weight + 1
  let m64 = m.to_int64()
  let bkf = ctx_f.dial_buckets(m)
  let bkb = ctx_b.dial_buckets(m)
  let ovf = ctx_f.ov
  let ovb = ctx_b.ov
  df[start] = 0L
  sf[start] = gf
  pf[start] = -1
  db[target] = 0L
  sb[target] = gb
  pb[target] = -1
  let f0f = h_f(start).to_int64()
  let f0b = h_b(target).to_int64()
  let mut d_f = f0f
  let mut d_b = f0b
  let mut cur_f = (f0f % m64).to_int() // d_f 对应的桶下标（增量维护，免逐次取模除法）
  let mut cur_b = (f0b % m64).to_int()
  let mut wend_f = f0f + m64
  let mut wend_b = f0b + m64
  bkf[cur_f].push((f0f << NODE_BITS) | start.to_int64())
  bkb[cur_b].push((f0b << NODE_BITS) | target.to_int64())
  let mut pend_f = 1
  let mut pend_b = 1
  let mut mu = INF_DIST
  let mut meet = -1
  while pend_f > 0 && pend_b > 0 {
    if meet >= 0 && d_f >= mu && d_b >= mu {
      break
    }
    if d_f <= d_b {
      // 正向推进一个 f 值。
      if d_f >= wend_f {
        if ovf.length() == pend_f && ovf.length() > 0 {
          let mut fmin = ovf[0] >> NODE_BITS
          for w in 1..<ovf.length() {
            let f = ovf[w] >> NODE_BITS
            if f < fmin {
              fmin = f
            }
          }
          if fmin > d_f {
            d_f = fmin
          }
        }
        cur_f = (d_f % m64).to_int()
        wend_f = d_f + m64
        let mut w = 0
        while w < ovf.length() {
          let enc = ovf[w]
          if enc >> NODE_BITS < wend_f {
            let mut slot = cur_f + ((enc >> NODE_BITS) - d_f).to_int()
            if slot >= m {
              slot = slot - m
            }
            bkf[slot].push(enc)
            let last = ovf.length() - 1
            ovf[w] = ovf[last]
            ovf.pop() |> ignore
          } else {
            w = w + 1
          }
        }
      }
      let b = bkf[cur_f]
      let mut bi = 0
      while bi < b.length() {
        let enc = b[bi]
        bi = bi + 1
        pend_f = pend_f - 1
        let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
        if cf[u] == gf {
          continue
        }
        cf[u] = gf
        let du = df[u]
        // 首次弹出时 enc 的 f = du + h_f(u)（同一节点最小 f 先出），免重算 h。
        if meet >= 0 &&
          (enc >> NODE_BITS >= mu || du + d_b - h_b(u).to_int64() >= mu) {
          continue
        }
        let stop = g.offsets[u + 1]
        for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
          let pe = g.packed[ei]
          let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
          let nd = du + (pe >> NODE_BITS)
          let dv = if sf[v] == gf { df[v] } else { INF_DIST }
          if nd < dv {
            df[v] = nd
            sf[v] = gf
            pf[v] = u
            let nf = nd + h_f(v).to_int64()
            let nenc = (nf << NODE_BITS) | v.to_int64()
            if nf < wend_f {
              let mut slot = cur_f + (nf - d_f).to_int()
              if slot >= m {
                slot = slot - m
              }
              bkf[slot].push(nenc)
            } else {
              ovf.push(nenc)
            }
            pend_f = pend_f + 1
            if sb[v] == gb && nd + db[v] < mu {
              mu = nd + db[v]
              meet = v
            }
          }
        }
      }
      b.clear()
      d_f = d_f + 1L
      cur_f = cur_f + 1
      if cur_f == m {
        cur_f = 0
      }
    } else {
      // 反向推进一个 f 值（rg 出边 = g 入边）。
      if d_b >= wend_b {
        if ovb.length() == pend_b && ovb.length() > 0 {
          let mut fmin = ovb[0] >> NODE_BITS
          for w in 1..<ovb.length() {
            let f = ovb[w] >> NODE_BITS
            if f < fmin {
              fmin = f
            }
          }
          if fmin > d_b {
            d_b = fmin
          }
        }
        cur_b = (d_b % m64).to_int()
        wend_b = d_b + m64
        let mut w = 0
        while w < ovb.length() {
          let enc = ovb[w]
          if enc >> NODE_BITS < wend_b {
            let mut slot = cur_b + ((enc >> NODE_BITS) - d_b).to_int()
            if slot >= m {
              slot = slot - m
            }
            bkb[slot].push(enc)
            let last = ovb.length() - 1
            ovb[w] = ovb[last]
            ovb.pop() |> ignore
          } else {
            w = w + 1
          }
        }
      }
      let b = bkb[cur_b]
      let mut bi = 0
      while bi < b.length() {
        let enc = b[bi]
        bi = bi + 1
        pend_b = pend_b - 1
        let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
        if cb[u] == gb {
          continue
        }
        cb[u] = gb
        let du = db[u]
        if meet >= 0 &&
          (enc >> NODE_BITS >= mu || du + d_f - h_f(u).to_int64() >= mu) {
          continue
        }
        let stop = rg.offsets[u + 1]
        for ei = rg.offsets[u]; ei < stop; ei = ei + 1 {
          let pe = rg.packed[ei]
          let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
          let nd = du + (pe >> NODE_BITS)
          let dv = if sb[v] == gb { db[v] } else { INF_DIST }
          if nd < dv {
            db[v] = nd
            sb[v] = gb
            pb[v] = u
            let nf = nd + h_b(v).to_int64()
            let nenc = (nf << NODE_BITS) | v.to_int64()
            if nf < wend_b {
              let mut slot = cur_b + (nf - d_b).to_int()
              if slot >= m {
                slot = slot - m
              }
              bkb[slot].push(nenc)
            } else {
              ovb.push(nenc)
            }
            pend_b = pend_b + 1
            if sf[v] == gf && nd + df[v] < mu {
              mu = nd + df[v]
              meet = v
            }
          }
        }
      }
      b.clear()
      d_b = d_b + 1L
      cur_b = cur_b + 1
      if cur_b == m {
        cur_b = 0
      }
    }
  }
  if meet < 0 {
    return None
  }
  let path = [meet]
  let mut node = meet
  while pf[node] >= 0 {
    node = pf[node]
    path.push(node)
  }
  path.rev_in_place()
  node = meet
  while pb[node] >= 0 {
    node = pb[node]
    path.push(node)
  }
  Some((path, mu.to_int()))
}

///|
/// 双向 A*（NBA* 剪枝式，Pijls & Post 2009）：正向用 `h_f`（到 target
/// 的一致下界）、反向沿 `rg` 用 `h_b`（到 start 的一致下界）各跑一支
/// A*，每轮扩展堆顶 f 较小的一侧；松弛时维护会合上界 μ；弹出节点满足
/// `f(u) ≥ μ` 或 `g(u) + F_other − h_other(u) ≥ μ` 即剪枝。两堆有一侧
/// 排空即终止（剪枝式终止，正确性不依赖势函数变换）。h 全零时退化为
/// 双向 Dijkstra 的搜索空间。语义与 `astar_indexed` 一致（代价最优；
/// 路径可能不同但逐边合法），差分 PBT 守卫。
pub fn astar_bidirectional_ctx(
  g : WeightedCsr,
  rg : WeightedCsr,
  ctx_f : SearchCtx,
  ctx_b : SearchCtx,
  start : Int,
  target : Int,
  h_f : (Int) -> Int,
  h_b : (Int) -> Int,
) -> (Array[Int], Int)? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if start == target {
    return Some(([start], 0))
  }
  if g.max_weight >= 1 && g.max_weight <= DIAL_MAX_W {
    return astar_bidial_ctx(g, rg, ctx_f, ctx_b, start, target, h_f, h_b)
  }
  astar_biheap_ctx(g, rg, ctx_f, ctx_b, start, target, h_f, h_b)
}

///|
let zero_h : (Int) -> Int = fn(_v) { 0 }

///|
/// 堆式双向 A*（NBA* 剪枝）主体：`astar_bidirectional_ctx` 的编码堆
/// 分支；也作为大权/零权图 `dijkstra_bidirectional_ctx` 的零启发式
/// 双向 Dijkstra 后端。
fn astar_biheap_ctx(
  g : WeightedCsr,
  rg : WeightedCsr,
  ctx_f : SearchCtx,
  ctx_b : SearchCtx,
  start : Int,
  target : Int,
  h_f : (Int) -> Int,
  h_b : (Int) -> Int,
) -> (Array[Int], Int)? {
  ctx_f.gen = ctx_f.gen + 1
  ctx_b.gen = ctx_b.gen + 1
  let gf = ctx_f.gen
  let gb = ctx_b.gen
  let df = ctx_f.dist
  let db = ctx_b.dist
  let pf = ctx_f.parent
  let pb = ctx_b.parent
  let sf = ctx_f.stamp
  let sb = ctx_b.stamp
  let cf = ctx_f.closed
  let cb = ctx_b.closed
  let hf = ctx_f.heap
  let hb = ctx_b.heap
  hf.len = 0
  hb.len = 0
  df[start] = 0L
  sf[start] = gf
  pf[start] = -1
  hf.push((h_f(start).to_int64() << NODE_BITS) | start.to_int64())
  db[target] = 0L
  sb[target] = gb
  pb[target] = -1
  hb.push((h_b(target).to_int64() << NODE_BITS) | target.to_int64())
  let mut mu = INF_DIST
  let mut meet = -1
  while hf.len > 0 && hb.len > 0 {
    let ff = hf.data[0] >> NODE_BITS
    let fb = hb.data[0] >> NODE_BITS
    // 两侧堆顶 f 均 ≥ μ 时后续弹出全被剪枝，直接终止。
    if meet >= 0 && ff >= mu && fb >= mu {
      break
    }
    if ff <= fb {
      let enc = hf.pop()
      let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
      if cf[u] == gf {
        continue
      }
      cf[u] = gf
      let du = df[u]
      // NBA* 剪枝：该节点不可能位于比 μ 更短的 s-t 路径上。
      // 首次弹出时 enc 的 f = du + h_f(u)，免重算本侧 h。
      if meet >= 0 &&
        (enc >> NODE_BITS >= mu || du + fb - h_b(u).to_int64() >= mu) {
        continue
      }
      let stop = g.offsets[u + 1]
      for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
        let pe = g.packed[ei]
        let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
        let nd = du + (pe >> NODE_BITS)
        let dv = if sf[v] == gf { df[v] } else { INF_DIST }
        if nd < dv {
          df[v] = nd
          sf[v] = gf
          pf[v] = u
          hf.push(((nd + h_f(v).to_int64()) << NODE_BITS) | v.to_int64())
          if sb[v] == gb && nd + db[v] < mu {
            mu = nd + db[v]
            meet = v
          }
        }
      }
    } else {
      let enc = hb.pop()
      let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
      if cb[u] == gb {
        continue
      }
      cb[u] = gb
      let du = db[u]
      if meet >= 0 &&
        (enc >> NODE_BITS >= mu || du + ff - h_f(u).to_int64() >= mu) {
        continue
      }
      let stop = rg.offsets[u + 1]
      for ei = rg.offsets[u]; ei < stop; ei = ei + 1 {
        let pe = rg.packed[ei]
        let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
        let nd = du + (pe >> NODE_BITS)
        let dv = if sb[v] == gb { db[v] } else { INF_DIST }
        if nd < dv {
          db[v] = nd
          sb[v] = gb
          pb[v] = u
          hb.push(((nd + h_b(v).to_int64()) << NODE_BITS) | v.to_int64())
          if sf[v] == gf && nd + df[v] < mu {
            mu = nd + df[v]
            meet = v
          }
        }
      }
    }
  }
  if meet < 0 {
    return None
  }
  let path = [meet]
  let mut node = meet
  while pf[node] >= 0 {
    node = pf[node]
    path.push(node)
  }
  path.rev_in_place()
  node = meet
  while pb[node] >= 0 {
    node = pb[node]
    path.push(node)
  }
  Some((path, mu.to_int()))
}

///|
/// 复用上下文的 A*（要求 `h` 一致/单调，consistent；批量查询时免
/// 每次 O(n) 数组初始化，弹出时用 closed 戳代替 h(u) 重算）。
/// 小整数边权（≤ 1024）自动切换桶式 Dial 变体。
/// 上下文容量必须 ≥ 图节点数。
pub fn astar_indexed_ctx(
  g : WeightedCsr,
  ctx : SearchCtx,
  start : Int,
  target : Int,
  h : (Int) -> Int,
) -> (Array[Int], Int)? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if g.max_weight <= DIAL_MAX_W && g.max_weight > 0 {
    return astar_dial_ctx(g, ctx, start, target, h)
  }
  ctx.gen = ctx.gen + 1
  let gen = ctx.gen
  let dist = ctx.dist
  let parent = ctx.parent
  let stamp = ctx.stamp
  let closed = ctx.closed
  let heap = ctx.heap
  heap.len = 0
  let inf = 0x3FFF_FFFF_FFFFL
  dist[start] = 0L
  stamp[start] = gen
  parent[start] = -1
  heap.push((h(start).to_int64() << NODE_BITS) | start.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
    let du = dist[u]
    // 一致启发式下首次弹出即最优：closed 戳直接跳过陈旧条目，
    // 免每弹出一次 h(u) 重算。
    if closed[u] == gen {
      continue
    }
    closed[u] = gen
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
      let pe = g.packed[ei]
      let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
      let nd = du + (pe >> NODE_BITS)
      let dv = if stamp[v] == gen { dist[v] } else { inf }
      if nd < dv {
        dist[v] = nd
        stamp[v] = gen
        parent[v] = u
        heap.push(((nd + h(v).to_int64()) << NODE_BITS) | v.to_int64())
      }
    }
  }
  None
}

///|
fn astar_indexed_h(
  g : WeightedCsr,
  start : Int,
  target : Int,
  h : (Int) -> Int,
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
  heap.push((h(start).to_int64() << NODE_BITS) | start.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & ((1L << NODE_BITS) - 1L)).to_int()
    let f = enc >> NODE_BITS
    let du = dist[u]
    // 陈旧条目：f = g + h(u)，若对应的 g 超过当前 dist 则跳过。
    if f - h(u).to_int64() > du {
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
      let pe = g.packed[ei]
      let v = (pe & ((1L << NODE_BITS) - 1L)).to_int()
      let nd = du + (pe >> NODE_BITS)
      if nd < dist[v] {
        dist[v] = nd
        parent[v] = u
        heap.push(((nd + h(v).to_int64()) << NODE_BITS) | v.to_int64())
      }
    }
  }
  None
}
