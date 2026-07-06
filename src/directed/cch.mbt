// cch.mbt —— Customizable Contraction Hierarchies（Dibbelt, Strasser,
// Wagner 2014）。
//
// CH 的预处理把「收缩序 + 捷径拓扑」与「边权」耦合在一起：权重一变
// （交通拥堵、限行、自定义代价）就要整套重建（OSM 北京 ~24.6 s）。
// CCH 把两者解耦：
//   1. **度量无关阶段**（一次性）：只看拓扑，按最小度贪心序收缩，
//      对被删节点的存活邻居对补骨架边（弦图补全，不做 witness 搜索
//      ——没有权重可搜）；
//   2. **customization**（每次换权，毫秒~秒级）：把原图权写进骨架
//      边的上/下行两个方向，再按 rank 升序枚举每个节点的上邻三角
//      做下三角 relax，使上行图恢复最短路保持性；
//   3. **查询**：与 CH 相同的双向「向上」Dijkstra（含 stall-on-
//      demand），距离与原图 Dijkstra 一致。
//
// 语义由差分 PBT（含换权重再 customize 再对拍）与 OSM 全量对拍守卫。

///|
/// CCH 产物：度量无关骨架（拓扑 + 收缩序）与当前 customize 的权。
/// 骨架边按低 rank 端点分桶存高 rank 邻居（上邻表，按节点编号有序，
/// 供三角枚举二分定位），每条骨架边带两个可换绑方向权。
pub struct CustomizableCch {
  n : Int
  /// rank[v] = 收缩序（越大越重要）。
  rank : Array[Int]
  /// rank 升序节点序（customization 处理序）。
  ord : Array[Int]
  /// 上邻 CSR：fo[u]..fo[u+1] 为低端点 u 的高 rank 邻居（按编号有序）。
  fo : Array[Int]
  ft : Array[Int]
  /// 上行方向权 u→v（customize 写入；INF_DIST = 无原图对应）。
  fw : Array[Int64]
  /// 下行方向权 v→u。
  gw : Array[Int64]
  // 查询暂存（代戳懒失效，单线程复用）。
  df : Array[Int64]
  db : Array[Int64]
  sf : Array[Int]
  sb : Array[Int]
  mut gen : Int
  hf : RadixHeap
  hb : RadixHeap
}

///|
/// 有序数组二分查 target，返回下标或 -1。
fn cch_bsearch(ft : Array[Int], lo0 : Int, hi0 : Int, target : Int) -> Int {
  let mut lo = lo0
  let mut hi = hi0
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let t = ft[mid]
    if t == target {
      return mid
    } else if t < target {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  -1
}

///|
/// 有序邻居表二分插入（去重）。
fn cch_adj_insert(a : Array[Int], v : Int) -> Unit {
  let mut lo = 0
  let mut hi = a.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if a[mid] == v {
      return
    } else if a[mid] < v {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  a.insert(lo, v)
}

///|
/// 有序邻居表二分删除。
fn cch_adj_remove(a : Array[Int], v : Int) -> Unit {
  let mut lo = 0
  let mut hi = a.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if a[mid] == v {
      let _ = a.remove(mid)
      return
    } else if a[mid] < v {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
}

///|
/// 无向骨架邻接（每节点有序邻居表）。
fn cch_skeleton(g : WeightedCsr) -> Array[Array[Int]] {
  let n = g.node_count()
  let mask = (1L << NODE_BITS) - 1L
  let adj : Array[Array[Int]] = []
  for _ in 0..<n {
    adj.push([])
  }
  for u in 0..<n {
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let v = (g.packed[ei] & mask).to_int()
      if v != u {
        cch_adj_insert(adj[u], v)
        cch_adj_insert(adj[v], u)
      }
    }
  }
  adj
}

///|
/// 度量无关构建：最小度贪心懒更新收缩 + 弦图补全，随后用 g 的权做
/// 首次 customization。拓扑只依赖 g 的边集（方向合并为无向骨架）。
pub fn CustomizableCch::build(g : WeightedCsr) -> CustomizableCch {
  let n = g.node_count()
  let mask = (1L << NODE_BITS) - 1L
  let adj = cch_skeleton(g)
  // 最小度贪心（懒更新：pop 后度数变了就按当前度重新入队）。
  let rank = Array::make(n, -1)
  let ord = Array::make(n, 0)
  let heap = RadixHeap::new()
  heap.reset(0L)
  for v in 0..<n {
    heap.push((adj[v].length().to_int64() << NODE_BITS) | v.to_int64())
  }
  // 收缩时定稿的上邻表（v 收缩瞬间的存活邻居即其全部高 rank 邻居）。
  let ups : Array[Array[Int]] = []
  for _ in 0..<n {
    ups.push([])
  }
  let mut next_rank = 0
  let mut edge_total = 0
  while heap.len > 0 {
    let enc = heap.pop()
    let v = (enc & mask).to_int()
    if rank[v] >= 0 {
      continue
    }
    let deg = adj[v].length()
    if (enc >> NODE_BITS).to_int() != deg {
      heap.push((deg.to_int64() << NODE_BITS) | v.to_int64())
      continue
    }
    rank[v] = next_rank
    ord[next_rank] = v
    next_rank = next_rank + 1
    let nbrs = adj[v]
    edge_total = edge_total + nbrs.length()
    for i = 0; i < nbrs.length(); i = i + 1 {
      ups[v].push(nbrs[i])
    }
    // 弦图补全：存活邻居两两连边，并把 v 从各邻接表中摘除。
    for i = 0; i < nbrs.length(); i = i + 1 {
      let a = nbrs[i]
      cch_adj_remove(adj[a], v)
      for j = i + 1; j < nbrs.length(); j = j + 1 {
        let b = nbrs[j]
        cch_adj_insert(adj[a], b)
        cch_adj_insert(adj[b], a)
      }
    }
    adj[v].clear()
  }
  cch_assemble(g, n, rank, ord, ups, edge_total)
}

///|
/// 从收缩产物组装 CCH 并做首次 customization。
fn cch_assemble(
  g : WeightedCsr,
  n : Int,
  rank : Array[Int],
  ord : Array[Int],
  ups : Array[Array[Int]],
  edge_total : Int,
) -> CustomizableCch {
  // 上邻 CSR（ups[v] 收缩时即有序，直接铺平）。
  let fo = Array::make(n + 1, 0)
  for v in 0..<n {
    fo[v + 1] = fo[v] + ups[v].length()
  }
  let ft = Array::make(edge_total, 0)
  for v in 0..<n {
    let base = fo[v]
    let uv = ups[v]
    for i = 0; i < uv.length(); i = i + 1 {
      ft[base + i] = uv[i]
    }
  }
  let cch = {
    n,
    rank,
    ord,
    fo,
    ft,
    fw: Array::make(edge_total, INF_DIST),
    gw: Array::make(edge_total, INF_DIST),
    df: Array::make(n, 0L),
    db: Array::make(n, 0L),
    sf: Array::make(n, 0),
    sb: Array::make(n, 0),
    gen: 0,
    hf: RadixHeap::new(),
    hb: RadixHeap::new(),
  }
  cch.customize(g)
  cch
}

///|
/// 按预先给定的消除序收缩（rank[v] = 序号，越大越重要），弦图补全
/// 后组装并首次 customization。供嵌套剖分等外部收缩序使用。
pub fn CustomizableCch::build_with_order(
  g : WeightedCsr,
  rank : Array[Int],
) -> CustomizableCch {
  let n = g.node_count()
  let adj = cch_skeleton(g)
  let ord = Array::make(n, 0)
  for v in 0..<n {
    ord[rank[v]] = v
  }
  let ups : Array[Array[Int]] = []
  for _ in 0..<n {
    ups.push([])
  }
  let mut edge_total = 0
  for oi = 0; oi < n; oi = oi + 1 {
    let v = ord[oi]
    let nbrs = adj[v]
    edge_total = edge_total + nbrs.length()
    for i = 0; i < nbrs.length(); i = i + 1 {
      ups[v].push(nbrs[i])
    }
    for i = 0; i < nbrs.length(); i = i + 1 {
      let a = nbrs[i]
      cch_adj_remove(adj[a], v)
      for j = i + 1; j < nbrs.length(); j = j + 1 {
        let b = nbrs[j]
        cch_adj_insert(adj[a], b)
        cch_adj_insert(adj[b], a)
      }
    }
    adj[v].clear()
  }
  cch_assemble(g, n, rank, ord, ups, edge_total)
}

///|
/// 嵌套剖分消除序（Bauer et al. / CCH 论文推荐的序族）：BFS 层集
/// 二分递归切割，分隔符拿最高 rank，两半递归；小单元用局部最小度
/// 贪心收尾。只依赖拓扑，与权重无关。
pub fn cch_nd_order(g : WeightedCsr) -> Array[Int] {
  let n = g.node_count()
  let adj = cch_skeleton(g)
  let rank = Array::make(n, -1)
  let mut next_rank = 0
  // 小单元：局部最小度贪心（在子图内动态收缩，只看 cell 内邻居）。
  let cell_threshold = 48
  let in_cell = Array::make(n, -1)
  let mut cell_id = 0
  let dist = Array::make(n, -1)
  let queue = Array::make(n, 0)
  // 显式栈：待处理节点集（分隔符先入 pending 高位，最后统一赋号）。
  // 每个子问题处理完后分隔符按弹栈序获得更高 rank。
  let sep_stack : Array[Array[Int]] = []
  let work : Array[Array[Int]] = []
  let comp : Array[Int] = []
  for v in 0..<n {
    comp.push(v)
  }
  work.push(comp)
  while work.length() > 0 {
    let cell = work.unsafe_pop()
    if cell.length() == 0 {
      continue
    }
    if cell.length() <= cell_threshold {
      // 局部最小度贪心：只计 cell 内邻居（cell 外的要么已赋号更低
      // 要么是更高层分隔符，收缩序内部相对即可）。
      cell_id = cell_id + 1
      for v in cell {
        in_cell[v] = cell_id
      }
      let remaining = cell.copy()
      while remaining.length() > 0 {
        let mut best = 0
        let mut best_deg = n + 1
        for i = 0; i < remaining.length(); i = i + 1 {
          let v = remaining[i]
          let mut d = 0
          for u in adj[v] {
            if in_cell[u] == cell_id && rank[u] < 0 {
              d = d + 1
            }
          }
          if d < best_deg {
            best_deg = d
            best = i
          }
        }
        let v = remaining[best]
        let _ = remaining.remove(best)
        rank[v] = next_rank
        next_rank = next_rank + 1
      }
      continue
    }
    // BFS 层集二分：从伪周边点出发，取累计过半的层作分隔符。
    cell_id = cell_id + 1
    for v in cell {
      in_cell[v] = cell_id
      dist[v] = -1
    }
    // 伪周边点：从 cell[0] BFS 取最远点再 BFS 一次。
    let mut src = cell[0]
    for _pass in 0..<2 {
      for v in cell {
        dist[v] = -1
      }
      let mut qh = 0
      let mut qt = 0
      dist[src] = 0
      queue[qt] = src
      qt = qt + 1
      let mut far = src
      while qh < qt {
        let u = queue[qh]
        qh = qh + 1
        far = u
        for w in adj[u] {
          if in_cell[w] == cell_id && rank[w] < 0 && dist[w] < 0 {
            dist[w] = dist[u] + 1
            queue[qt] = w
            qt = qt + 1
          }
        }
      }
      src = far
    }
    // 最后一次 BFS 的 dist 已就位；未触达节点（cell 内其他连通块）
    // 归入 part_a。找累计节点数过半的层作分隔符。
    let mut maxd = 0
    for v in cell {
      if dist[v] > maxd {
        maxd = dist[v]
      }
    }
    let layer_cnt = Array::make(maxd + 1, 0)
    let mut reached = 0
    for v in cell {
      if dist[v] >= 0 {
        layer_cnt[dist[v]] = layer_cnt[dist[v]] + 1
        reached = reached + 1
      }
    }
    let mut acc = 0
    let mut sep_layer = 0
    for d = 0; d <= maxd; d = d + 1 {
      acc = acc + layer_cnt[d]
      if acc * 2 >= reached {
        sep_layer = d
        break
      }
    }
    let part_a : Array[Int] = []
    let part_b : Array[Int] = []
    let sep : Array[Int] = []
    for v in cell {
      if dist[v] == sep_layer {
        sep.push(v)
      } else if dist[v] >= 0 && dist[v] < sep_layer {
        part_a.push(v)
      } else {
        part_b.push(v)
      }
    }
    // 退化护栏：分隔失败（某半为空）则整个 cell 降级为小单元处理。
    if part_a.length() == 0 || part_b.length() == 0 {
      cell_id = cell_id + 1
      for v in cell {
        in_cell[v] = cell_id
      }
      let remaining = cell.copy()
      while remaining.length() > 0 {
        let mut best = 0
        let mut best_deg = n + 1
        for i = 0; i < remaining.length(); i = i + 1 {
          let v = remaining[i]
          let mut d = 0
          for u in adj[v] {
            if in_cell[u] == cell_id && rank[u] < 0 {
              d = d + 1
            }
          }
          if d < best_deg {
            best_deg = d
            best = i
          }
        }
        let v = remaining[best]
        let _ = remaining.remove(best)
        rank[v] = next_rank
        next_rank = next_rank + 1
      }
      continue
    }
    sep_stack.push(sep)
    work.push(part_a)
    work.push(part_b)
  }
  // 分隔符自底向上赋最高 rank（深层分隔符先、顶层分隔符最后/最高）。
  while sep_stack.length() > 0 {
    let sep = sep_stack.unsafe_pop()
    for v in sep {
      rank[v] = next_rank
      next_rank = next_rank + 1
    }
  }
  rank
}

///|
/// 骨架边数（弦图补全后的上邻总数，衡量收缩序质量的填充规模）。
pub fn CustomizableCch::edge_count(self : CustomizableCch) -> Int {
  self.ft.length()
}

///|
/// 换绑权重：把 g 的边权写进骨架（拓扑必须与 build 时同边集），再做
/// basic customization——按 rank 升序对每个节点的上邻对做下三角
/// relax，恢复上行图的最短路保持性。O(骨架三角数)，无堆无搜索。
pub fn CustomizableCch::customize(
  self : CustomizableCch,
  g : WeightedCsr,
) -> Unit {
  let mask = (1L << NODE_BITS) - 1L
  let fw = self.fw
  let gw = self.gw
  let ft = self.ft
  let fo = self.fo
  for ei = 0; ei < fw.length(); ei = ei + 1 {
    fw[ei] = INF_DIST
    gw[ei] = INF_DIST
  }
  // 原图权注入：u→v 落在骨架边 {u,v} 的对应方向上（保留更小权）。
  for u in 0..<self.n {
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let pe = g.packed[ei]
      let v = (pe & mask).to_int()
      if v == u {
        continue
      }
      let w = pe >> NODE_BITS
      if self.rank[u] < self.rank[v] {
        let idx = cch_bsearch(ft, fo[u], fo[u + 1], v)
        if fw[idx] > w {
          fw[idx] = w
        }
      } else {
        let idx = cch_bsearch(ft, fo[v], fo[v + 1], u)
        if gw[idx] > w {
          gw[idx] = w
        }
      }
    }
  }
  // 下三角 relax：三角 {x,u,v}（rank x < u < v），经 x 的两跳收紧
  // 骨架边 {u,v} 的两个方向。
  for oi = 0; oi < self.n; oi = oi + 1 {
    let x = self.ord[oi]
    let stop = fo[x + 1]
    for i = fo[x]; i < stop; i = i + 1 {
      let a = ft[i]
      for j = i + 1; j < stop; j = j + 1 {
        let b = ft[j]
        let (u, eu, v, ev) = if self.rank[a] < self.rank[b] {
          (a, i, b, j)
        } else {
          (b, j, a, i)
        }
        let idx = cch_bsearch(ft, fo[u], fo[u + 1], v)
        // u→x→v 收紧上行 u→v；v→x→u 收紧下行 v→u。
        let up = gw[eu] + fw[ev]
        if up < fw[idx] {
          fw[idx] = up
        }
        let dn = gw[ev] + fw[eu]
        if dn < gw[idx] {
          gw[idx] = dn
        }
      }
    }
  }
}

///|
/// 点对点距离查询：双向「向上」Dijkstra（前向走上行权、后向走下行
/// 权，均含 stall-on-demand），会合取 min。不可达返回 `None`。语义
/// 与 `dijkstra_csr` 的 s→t 距离一致。
pub fn CustomizableCch::query_dist(
  self : CustomizableCch,
  start : Int,
  target : Int,
) -> Int64? {
  if start < 0 || start >= self.n || target < 0 || target >= self.n {
    return None
  }
  self.gen = self.gen + 1
  let gen = self.gen
  let mask = (1L << NODE_BITS) - 1L
  let df = self.df
  let db = self.db
  let sf = self.sf
  let sb = self.sb
  let fo = self.fo
  let ft = self.ft
  let fw = self.fw
  let gw = self.gw
  let hf = self.hf
  let hb = self.hb
  hf.reset(0L)
  hb.reset(0L)
  df[start] = 0L
  sf[start] = gen
  hf.push(start.to_int64())
  db[target] = 0L
  sb[target] = gen
  hb.push(target.to_int64())
  let mut mu = INF_DIST
  while hf.len > 0 || hb.len > 0 {
    let ff = if hf.len > 0 { hf.peek() >> NODE_BITS } else { INF_DIST }
    let fb = if hb.len > 0 { hb.peek() >> NODE_BITS } else { INF_DIST }
    if ff >= mu && fb >= mu {
      break
    }
    if ff <= fb {
      let enc = hf.pop()
      let u = (enc & mask).to_int()
      let du = enc >> NODE_BITS
      if du > df[u] {
        continue
      }
      let stop = fo[u + 1]
      // stall-on-demand：更高 rank 上邻 v 经下行 v→u 更短则免松弛。
      let mut stalled = false
      for ei = fo[u]; ei < stop; ei = ei + 1 {
        let v = ft[ei]
        if sf[v] == gen && df[v] + gw[ei] < du {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      if sb[u] == gen && du + db[u] < mu {
        mu = du + db[u]
      }
      for ei = fo[u]; ei < stop; ei = ei + 1 {
        let v = ft[ei]
        let nd = du + fw[ei]
        if nd < INF_DIST && (sf[v] != gen || nd < df[v]) {
          df[v] = nd
          sf[v] = gen
          hf.push((nd << NODE_BITS) | v.to_int64())
        }
      }
    } else {
      let enc = hb.pop()
      let u = (enc & mask).to_int()
      let du = enc >> NODE_BITS
      if du > db[u] {
        continue
      }
      let stop = fo[u + 1]
      let mut stalled = false
      for ei = fo[u]; ei < stop; ei = ei + 1 {
        let v = ft[ei]
        if sb[v] == gen && db[v] + fw[ei] < du {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      if sf[u] == gen && du + df[u] < mu {
        mu = du + df[u]
      }
      for ei = fo[u]; ei < stop; ei = ei + 1 {
        let v = ft[ei]
        let nd = du + gw[ei]
        if nd < INF_DIST && (sb[v] != gen || nd < db[v]) {
          db[v] = nd
          sb[v] = gen
          hb.push((nd << NODE_BITS) | v.to_int64())
        }
      }
    }
  }
  if mu >= INF_DIST {
    None
  } else {
    Some(mu)
  }
}
