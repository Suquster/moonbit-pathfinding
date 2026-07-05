// ch.mbt —— Contraction Hierarchies（Geisberger et al. 2008）。
//
// 生产级路网点对点查询的业界标准：预处理按重要度逐个「收缩」节点，
// 为被删节点的邻居对补捷径（witness 搜索证明非必要则免补）；查询
// 只在「向上图」（边指向更高 rank）上做双向 Dijkstra，搜索空间从
// O(V) 缩到 O(polylog)，真实路网上相对双向 Dijkstra 数量级加速。
// 捷径记录中点，查询后递归展开还原原图路径。语义与 dijkstra_indexed
// 一致（同图同 s-t 最短代价相同），由差分 PBT 与 OSM 对拍守卫。

///|
/// CH 预处理产物 + 查询上下文（查询侧数组懒代戳复用，单线程）。
pub struct ContractionHierarchy {
  n : Int
  /// rank[v] = 收缩序（越大越重要，查询只沿 rank 递增方向松弛）。
  rank : Array[Int]
  /// 向上出边 CSR（u→v 且 rank[v] > rank[u]）。
  fo : Array[Int]
  ft : Array[Int]
  fw : Array[Int64]
  /// 捷径中点（-1 = 原图边）。
  fm : Array[Int]
  /// 捷径前半段权（展开用；原图边为 -1）。
  fh : Array[Int64]
  /// 向上入边 CSR（u→v 且 rank[u] > rank[v]，按 v 分桶存 u）。
  bo : Array[Int]
  bt : Array[Int]
  bw : Array[Int64]
  bm : Array[Int]
  bh : Array[Int64]
  // 查询暂存（代戳懒失效）
  df : Array[Int64]
  db : Array[Int64]
  sf : Array[Int]
  sb : Array[Int]
  pf : Array[Int]
  pb : Array[Int]
  pef : Array[Int]
  peb : Array[Int]
  mut gen : Int
  hf : RadixHeap
  hb : RadixHeap
}

///|
/// witness 搜索的结算上限（局部 Dijkstra 最多弹出这么多节点；
/// 超限保守补捷径——只影响捷径数量不影响正确性）。
const CH_WITNESS_POPS : Int = 256

///|
/// 收缩期动态邻接（出/入边平行数组：packed=(w<<21)|node、mid、前半权）。
priv struct ChAdj {
  pk : Array[Array[Int64]]
  mid : Array[Array[Int]]
  half : Array[Array[Int64]]
}

///|
fn ChAdj::new(n : Int) -> ChAdj {
  let pk : Array[Array[Int64]] = []
  let mid : Array[Array[Int]] = []
  let half : Array[Array[Int64]] = []
  for _ in 0..<n {
    pk.push([])
    mid.push([])
    half.push([])
  }
  { pk, mid, half }
}

///|
/// 加边/并行边去重（保留更小权；度数小，线性扫描足够）。
fn ChAdj::add(
  self : ChAdj,
  u : Int,
  v : Int,
  w : Int64,
  m : Int,
  h : Int64,
) -> Unit {
  let pu = self.pk[u]
  let mask = (1L << NODE_BITS) - 1L
  for i = 0; i < pu.length(); i = i + 1 {
    if (pu[i] & mask).to_int() == v {
      if pu[i] >> NODE_BITS <= w {
        return
      }
      pu[i] = (w << NODE_BITS) | v.to_int64()
      self.mid[u][i] = m
      self.half[u][i] = h
      return
    }
  }
  pu.push((w << NODE_BITS) | v.to_int64())
  self.mid[u].push(m)
  self.half[u].push(h)
}

///|
/// 构建 CH：贪心按「边差 + 已删邻居数」优先级懒更新收缩全部节点。
/// O(E log V) 级预处理（witness 搜索有结算上限）。
pub fn ContractionHierarchy::build(g : WeightedCsr) -> ContractionHierarchy {
  let n = g.node_count()
  let outs = ChAdj::new(n)
  let ins = ChAdj::new(n)
  let mask = (1L << NODE_BITS) - 1L
  for u in 0..<n {
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let pe = g.packed[ei]
      let v = (pe & mask).to_int()
      if v == u {
        continue // 自环对最短路无用
      }
      let w = pe >> NODE_BITS
      outs.add(u, v, w, -1, -1L)
      ins.add(v, u, w, -1, -1L)
    }
  }
  let contracted = Array::make(n, false)
  let rank = Array::make(n, 0)
  let del_nbr = Array::make(n, 0)
  // witness 局部 Dijkstra 暂存
  let wdist = Array::make(n, 0L)
  let wstamp = Array::make(n, 0)
  let mut wgen = 0
  let wheap = EncodedHeap::new(16)
  // 优先级 = witness 实测捷径数 − indeg − outdeg + 2*已删邻居
  // （Geisberger 边差启发；偏置编码防负数）。
  let bias = 1L << 30
  fn live_deg(a : ChAdj, v : Int) -> Int {
    let pv = a.pk[v]
    let mut c = 0
    for i = 0; i < pv.length(); i = i + 1 {
      if !contracted[(pv[i] & mask).to_int()] {
        c = c + 1
      }
    }
    c
  }
  // 收缩 v（apply=false 仅数捷径）：对每对 (u→v, v→x) 活跃邻居做
  // witness 搜索，非必要则免补。返回补（或需要补）的捷径数。
  fn contract(v : Int, apply : Bool) -> Int {
    let pin = ins.pk[v]
    let pout = outs.pk[v]
    let mut max_out = 0L
    for j = 0; j < pout.length(); j = j + 1 {
      let x = (pout[j] & mask).to_int()
      if !contracted[x] && pout[j] >> NODE_BITS > max_out {
        max_out = pout[j] >> NODE_BITS
      }
    }
    let mut added = 0
    for i = 0; i < pin.length(); i = i + 1 {
      let u = (pin[i] & mask).to_int()
      if contracted[u] {
        continue
      }
      let w1 = pin[i] >> NODE_BITS
      let limit = w1 + max_out
      // witness：u 出发、绕过 v 的有界局部 Dijkstra。
      wgen = wgen + 1
      wheap.len = 0
      wdist[u] = 0L
      wstamp[u] = wgen
      wheap.push(u.to_int64())
      let mut pops = 0
      while wheap.len > 0 && pops < CH_WITNESS_POPS {
        let we = wheap.pop()
        let a = (we & mask).to_int()
        let da = we >> NODE_BITS
        if wstamp[a] != wgen || da > wdist[a] {
          continue
        }
        if da > limit {
          break
        }
        pops = pops + 1
        let pa = outs.pk[a]
        for t = 0; t < pa.length(); t = t + 1 {
          let b = (pa[t] & mask).to_int()
          if b == v || contracted[b] {
            continue
          }
          let nd = da + (pa[t] >> NODE_BITS)
          if nd <= limit && (wstamp[b] != wgen || nd < wdist[b]) {
            wdist[b] = nd
            wstamp[b] = wgen
            wheap.push((nd << NODE_BITS) | b.to_int64())
          }
        }
      }
      for j = 0; j < pout.length(); j = j + 1 {
        let x = (pout[j] & mask).to_int()
        if contracted[x] || x == u {
          continue
        }
        let via = w1 + (pout[j] >> NODE_BITS)
        if wstamp[x] == wgen && wdist[x] <= via {
          continue // witness 路径不经 v 且不更长，免捷径
        }
        added = added + 1
        if apply {
          outs.add(u, x, via, v, w1)
          ins.add(x, u, via, v, w1)
        }
      }
    }
    added
  }
  fn prio(v : Int) -> Int64 {
    let di = live_deg(ins, v)
    let dout = live_deg(outs, v)
    (contract(v, false) - di - dout + 2 * del_nbr[v]).to_int64()
  }
  let pq = EncodedHeap::new(16)
  for v in 0..<n {
    pq.push(((prio(v) + bias) << NODE_BITS) | v.to_int64())
  }
  let mut next_rank = 0
  while pq.len > 0 {
    let enc = pq.pop()
    let v = (enc & mask).to_int()
    if contracted[v] {
      continue
    }
    // 懒重估：优先级过期且劣于当前堆顶则重新入队。
    let p = prio(v)
    if pq.len > 0 && (p + bias) << NODE_BITS > pq.data[0] {
      pq.push(((p + bias) << NODE_BITS) | v.to_int64())
      continue
    }
    contract(v, true) |> ignore
    let pin = ins.pk[v]
    let pout = outs.pk[v]
    contracted[v] = true
    rank[v] = next_rank
    next_rank = next_rank + 1
    for i = 0; i < pin.length(); i = i + 1 {
      let u = (pin[i] & mask).to_int()
      if !contracted[u] {
        del_nbr[u] = del_nbr[u] + 1
      }
    }
    for j = 0; j < pout.length(); j = j + 1 {
      let x = (pout[j] & mask).to_int()
      if !contracted[x] {
        del_nbr[x] = del_nbr[x] + 1
      }
    }
  }
  // 组装向上 CSR：全部边（原图 + 捷径）按 rank 方向分正/反两侧。
  let fcnt = Array::make(n + 1, 0)
  let bcnt = Array::make(n + 1, 0)
  for u in 0..<n {
    let pu = outs.pk[u]
    for i = 0; i < pu.length(); i = i + 1 {
      let v = (pu[i] & mask).to_int()
      if rank[v] > rank[u] {
        fcnt[u + 1] = fcnt[u + 1] + 1
      } else {
        bcnt[v + 1] = bcnt[v + 1] + 1
      }
    }
  }
  for i in 1..<=n {
    fcnt[i] = fcnt[i] + fcnt[i - 1]
    bcnt[i] = bcnt[i] + bcnt[i - 1]
  }
  let fo = fcnt.copy()
  let bo = bcnt.copy()
  let fcur = Array::make(n, 0)
  let bcur = Array::make(n, 0)
  for u in 0..<n {
    fcur[u] = fo[u]
    bcur[u] = bo[u]
  }
  let fe = fo[n]
  let be = bo[n]
  let ft = Array::make(fe, 0)
  let fw = Array::make(fe, 0L)
  let fm = Array::make(fe, -1)
  let fh = Array::make(fe, -1L)
  let bt = Array::make(be, 0)
  let bw = Array::make(be, 0L)
  let bm = Array::make(be, -1)
  let bh = Array::make(be, -1L)
  for u in 0..<n {
    let pu = outs.pk[u]
    for i = 0; i < pu.length(); i = i + 1 {
      let v = (pu[i] & mask).to_int()
      let w = pu[i] >> NODE_BITS
      if rank[v] > rank[u] {
        let c = fcur[u]
        ft[c] = v
        fw[c] = w
        fm[c] = outs.mid[u][i]
        fh[c] = outs.half[u][i]
        fcur[u] = c + 1
      } else {
        let c = bcur[v]
        bt[c] = u
        bw[c] = w
        bm[c] = outs.mid[u][i]
        bh[c] = outs.half[u][i]
        bcur[v] = c + 1
      }
    }
  }
  {
    n,
    rank,
    fo,
    ft,
    fw,
    fm,
    fh,
    bo,
    bt,
    bw,
    bm,
    bh,
    df: Array::make(n, 0L),
    db: Array::make(n, 0L),
    sf: Array::make(n, 0),
    sb: Array::make(n, 0),
    pf: Array::make(n, -1),
    pb: Array::make(n, -1),
    pef: Array::make(n, -1),
    peb: Array::make(n, -1),
    gen: 0,
    hf: RadixHeap::new(),
    hb: RadixHeap::new(),
  }
}

///|
/// 在 mid 节点的向上入边表中找 u→mid 的权 w 边，返回边下标。
fn ContractionHierarchy::find_bwd(
  self : ContractionHierarchy,
  u : Int,
  mid : Int,
  w : Int64,
) -> Int {
  let stop = self.bo[mid + 1]
  for ei = self.bo[mid]; ei < stop; ei = ei + 1 {
    if self.bt[ei] == u && self.bw[ei] == w {
      return ei
    }
  }
  -1
}

///|
/// 在 mid 节点的向上出边表中找 mid→x 的权 w 边，返回边下标。
fn ContractionHierarchy::find_fwd(
  self : ContractionHierarchy,
  mid : Int,
  x : Int,
  w : Int64,
) -> Int {
  let stop = self.fo[mid + 1]
  for ei = self.fo[mid]; ei < stop; ei = ei + 1 {
    if self.ft[ei] == x && self.fw[ei] == w {
      return ei
    }
  }
  -1
}

///|
/// 展开一条（可能是捷径的）边 u→x（权 w、中点 m、前半权 h），把
/// 除 u 外的节点按序追加到 path。显式栈防深递归。
fn ContractionHierarchy::unpack_edge(
  self : ContractionHierarchy,
  u0 : Int,
  x0 : Int,
  w0 : Int64,
  m0 : Int,
  h0 : Int64,
  path : Array[Int],
) -> Unit {
  // 栈内条目倒序处理（先压后半段）。
  let stk : Array[(Int, Int, Int64, Int, Int64)] = [(u0, x0, w0, m0, h0)]
  while stk.length() > 0 {
    let (u, x, w, m, h) = stk.unsafe_pop()
    if m < 0 {
      path.push(x)
      continue
    }
    // 捷径 = u→m（权 h，位于 m 的向上入边）+ m→x（权 w−h，向上出边）。
    let e1 = self.find_bwd(u, m, h)
    let e2 = self.find_fwd(m, x, w - h)
    stk.push((m, x, w - h, self.fm[e2], self.fh[e2]))
    stk.push((u, m, h, self.bm[e1], self.bh[e1]))
  }
}

///|
/// 点对点查询：双向「向上」Dijkstra + 会合点取 min，捷径展开还原
/// 原图路径。返回 `Some((path, cost))` 或不可达 `None`。
pub fn ContractionHierarchy::query(
  self : ContractionHierarchy,
  start : Int,
  target : Int,
) -> (Array[Int], Int)? {
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
  let pf = self.pf
  let pb = self.pb
  let pef = self.pef
  let peb = self.peb
  let hf = self.hf
  let hb = self.hb
  hf.reset(0L)
  hb.reset(0L)
  df[start] = 0L
  sf[start] = gen
  pf[start] = -1
  pef[start] = -1
  hf.push(start.to_int64())
  db[target] = 0L
  sb[target] = gen
  pb[target] = -1
  peb[target] = -1
  hb.push(target.to_int64())
  let mut mu = INF_DIST
  let mut meet = -1
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
      // stall-on-demand：若存在更高 rank 的 v 经下行边 v→u 给出更短
      // 距离，则 u 不在任何最短上行路径上，免松弛。
      let bstop = self.bo[u + 1]
      let mut stalled = false
      for ei = self.bo[u]; ei < bstop; ei = ei + 1 {
        let v = self.bt[ei]
        if sf[v] == gen && df[v] + self.bw[ei] < du {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      if sb[u] == gen && du + db[u] < mu {
        mu = du + db[u]
        meet = u
      }
      let stop = self.fo[u + 1]
      for ei = self.fo[u]; ei < stop; ei = ei + 1 {
        let v = self.ft[ei]
        let nd = du + self.fw[ei]
        if sf[v] != gen || nd < df[v] {
          df[v] = nd
          sf[v] = gen
          pf[v] = u
          pef[v] = ei
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
      let fstop = self.fo[u + 1]
      let mut stalled = false
      for ei = self.fo[u]; ei < fstop; ei = ei + 1 {
        let v = self.ft[ei]
        if sb[v] == gen && db[v] + self.fw[ei] < du {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      if sf[u] == gen && du + df[u] < mu {
        mu = du + df[u]
        meet = u
      }
      let stop = self.bo[u + 1]
      for ei = self.bo[u]; ei < stop; ei = ei + 1 {
        let v = self.bt[ei]
        let nd = du + self.bw[ei]
        if sb[v] != gen || nd < db[v] {
          db[v] = nd
          sb[v] = gen
          pb[v] = u
          peb[v] = ei
          hb.push((nd << NODE_BITS) | v.to_int64())
        }
      }
    }
  }
  if meet < 0 {
    return None
  }
  // 前向上行链 s→meet（自底向上收集后反转展开）。
  let ups : Array[Int] = [] // 前向树边下标序列（meet 端在前）
  let mut node = meet
  while pf[node] >= 0 {
    ups.push(pef[node])
    node = pf[node]
  }
  let path = [start]
  for i = ups.length() - 1; i >= 0; i = i - 1 {
    let ei = ups[i]
    let u = path[path.length() - 1]
    self.unpack_edge(
      u,
      self.ft[ei],
      self.fw[ei],
      self.fm[ei],
      self.fh[ei],
      path,
    )
  }
  // 反向上行链 meet→t：peb[v] 记录松弛 v 时命中的向上入边下标，
  // 该边原方向为 v→pb[v]；沿 pb 从 meet 走到 target 逐边展开。
  node = meet
  while pb[node] >= 0 {
    let ei = peb[node]
    let nxt = pb[node]
    self.unpack_edge(node, nxt, self.bw[ei], self.bm[ei], self.bh[ei], path)
    node = nxt
  }
  Some((path, mu.to_int()))
}
