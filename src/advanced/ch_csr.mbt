// ch_csr.mbt —— 生产级 Contraction Hierarchies（CSR / Int 节点特化，任务 19.1）。
//
// 参考文献：Geisberger, Sanders, Schultes, Delling (2008). "Contraction
// Hierarchies: Faster and Simpler Hierarchical Routing in Road Networks."
// WEA 2008, LNCS 5038, pp. 319-333.
//
// 与通用版 `ch.mbt`（`Map`/泛型节点）的关系与分工：
//   * `ch.mbt` 保持泛型 API 与教学清晰度，适合小图与任意节点类型；
//   * 本文件面向**大规模真实路网**（十万节点级 OSM / 合成网格），以
//     `@graph.CsrGraph[Double]`（压缩稀疏行、`0..n-1` 整型节点）为输入，
//     全程使用平坦数组 + 世代戳（epoch stamping）工作区，消除哈希与
//     每查询分配，使预处理可在十万节点上完成、查询较点对点 Dijkstra
//     达到数量级加速（R8.4/R8.5/R21.1 的「远超 baseline」证据）。
//
// 论文到代码的关键对应（paper-to-code）：
//   * §3.1 节点排序：`edge_difference + deleted_neighbours` 启发式 +
//     惰性重估（lazy re-evaluation）——`ch_csr_preprocess` 主循环。
//   * §3.2 收缩与 witness 搜索：`ch_csr_contract` 对每个入邻 `u` 做一次
//     受限 Dijkstra（结算数上界 + 代价上界双重截断），未找到不经由 `v`
//     的等优旁路时补捷径 `u -> x`（权 = w_uv + w_vx，中间点 = v）。
//   * §4 查询：`ch_csr_query` 双向「仅向上」Dijkstra，扫描双侧结算集取
//     `dist_f + dist_b` 最小的会合点，再经捷径中间点栈式展开为原图路径。
//
// 质量约束（项目 steering）：
//   * 无 `abort`/`todo`/占位；越界与不可达均以 `None`/空结果安全表达。
//   * 捷径记录携带左右子边权重，展开时按「权重精确匹配」选择分解，
//     保证展开路径的逐边权重和与查询返回代价**逐位相等**（Double 加法
//     顺序一致，三后端确定一致）。
//   * 工作区数组随结构体常驻，查询间以 `epoch` 世代戳复位，单次查询
//     摊还零分配（除输出路径本身）。

///|
/// witness 搜索的结算节点数上界：限制每次 witness Dijkstra 至多弹出
/// 这么多节点，保证预处理总代价与图规模呈近线性（路网/网格上实测足够
/// 找到绝大多数旁路；漏判仅多添无害捷径，不影响正确性）。
let ch_csr_witness_settle_limit : Int = 320

///|
/// 表示「无穷远」的哨兵距离（工作区数组的未触达语义由世代戳承担，本值
/// 仅用于比较初值）。
let ch_csr_inf : Double = @core.Weight::infinity()

///|
/// 捷径记录：`(middle, w_left, w_right)` —— 捷径 `u -> x` 由
/// `u -> middle`（权 `w_left`）与 `middle -> x`（权 `w_right`）拼接而成，
/// `w_left + w_right` 即捷径权。同一 `(u, x)` 键可积累多条不同权的捷径
/// （平行捷径），展开时按权重精确匹配选取。
struct ChCsrShortcut {
  middle : Int
  w_left : Double
  w_right : Double
}

///|
/// 生产级 CH 预处理产物（CSR / Int 节点特化）。
///
/// 字段：
///   * `n` —— 节点数（节点标识 `0..n-1`）。
///   * `rank` —— `rank[v]` 为 `v` 被收缩的次序（越小越早收缩、层级越低）。
///   * `up_*` —— 向上邻接（CSR 三数组）：`u` 的出边 `(v, w)` 满足
///     `rank[v] > rank[u]`，供正向查询使用。
///   * `dn_*` —— 向下邻接（CSR 三数组，**按低端节点存储入边**）：键 `v`
///     的表项 `(u, w)` 表示原残差边 `u -> v` 且 `rank[u] > rank[v]`，
///     供反向查询自目标「向上」爬升使用。
///   * `shortcuts` —— 捷径中间点表：键 `u * n + x`（Int64 防溢出），值为
///     该有序对上全部捷径记录（含左右子边权），用于路径展开。
///   * `dist_f/dist_b`、`par_f/par_b`、`pw_f/pw_b`、`stamp_f/stamp_b`、
///     `epoch` —— 查询工作区（距离/父节点/父边权/世代戳），随结构体常驻、
///     查询间零重分配。
pub struct ChCsr {
  n : Int
  rank : Array[Int]
  up_row : Array[Int]
  up_col : Array[Int]
  up_w : Array[Double]
  dn_row : Array[Int]
  dn_col : Array[Int]
  dn_w : Array[Double]
  shortcuts : Map[Int64, Array[ChCsrShortcut]]
  dist_f : Array[Double]
  dist_b : Array[Double]
  par_f : Array[Int]
  par_b : Array[Int]
  pw_f : Array[Double]
  pw_b : Array[Double]
  stamp_f : Array[Int]
  stamp_b : Array[Int]
  pq_f : ChHeap
  pq_b : ChHeap
  mut epoch : Int
}

///|
/// 平坦双数组二叉最小堆（查询热路径专用）：键/值分离存储，杜绝
/// 元组装箱与逐表项分配；`pop` 结果写入 `top_key`/`top_val` 字段而非
/// 返回元组，配合 `clear` 的 O(1) 复位实现跨查询零重分配。
struct ChHeap {
  keys : Array[Double]
  vals : Array[Int]
  mut len : Int
  mut top_key : Double
  mut top_val : Int
}

///|
fn ChHeap::new() -> ChHeap {
  { keys: [], vals: [], len: 0, top_key: 0.0, top_val: -1 }
}

///|
fn ChHeap::clear(self : ChHeap) -> Unit {
  self.len = 0
}

///|
fn ChHeap::is_empty(self : ChHeap) -> Bool {
  self.len == 0
}

///|
/// 堆顶键；空堆返回正无穷（与停机准则的比较语义天然契合）。
fn ChHeap::min_key(self : ChHeap) -> Double {
  if self.len == 0 {
    ch_csr_inf
  } else {
    self.keys[0]
  }
}

///|
fn ChHeap::push(self : ChHeap, key : Double, val : Int) -> Unit {
  let mut i = self.len
  if i < self.keys.length() {
    self.keys[i] = key
    self.vals[i] = val
  } else {
    self.keys.push(key)
    self.vals.push(val)
  }
  self.len = i + 1
  while i > 0 {
    let p = (i - 1) / 2
    if self.keys[p] <= key {
      break
    }
    self.keys[i] = self.keys[p]
    self.vals[i] = self.vals[p]
    i = p
  }
  self.keys[i] = key
  self.vals[i] = val
}

///|
/// 弹出最小项写入 `top_key`/`top_val`；空堆返回 `false`。
fn ChHeap::pop(self : ChHeap) -> Bool {
  let n = self.len
  if n == 0 {
    return false
  }
  self.top_key = self.keys[0]
  self.top_val = self.vals[0]
  let last_k = self.keys[n - 1]
  let last_v = self.vals[n - 1]
  self.len = n - 1
  let m = n - 1
  if m > 0 {
    let mut i = 0
    while true {
      let l = i * 2 + 1
      if l >= m {
        break
      }
      let r = l + 1
      let c = if r < m && self.keys[r] < self.keys[l] { r } else { l }
      if self.keys[c] >= last_k {
        break
      }
      self.keys[i] = self.keys[c]
      self.vals[i] = self.vals[c]
      i = c
    }
    self.keys[i] = last_k
    self.vals[i] = last_v
  }
  true
}

///|
/// 捷径键：有序对 `(u, x)` 折叠为 `u * n + x`（Int64，避免 `n` 达十万级
/// 时 Int 乘法溢出）。
fn ch_csr_key(n : Int, u : Int, x : Int) -> Int64 {
  u.to_int64() * n.to_int64() + x.to_int64()
}

///|
/// 收缩单节点 `v`（论文 §3.2）：枚举残差图上全部 `(u -> v -> x)` 组合；
/// 对每个未收缩入邻 `u` 先取其经由 `v` 的最大目标代价为上界，做一次
/// witness 搜索覆盖全部出端 `x`，对未找到等优旁路的组合补捷径
/// `u -> x`（权 `w_uv + w_vx`）。
///
/// `simulate_only = true` 时仅统计将要新增的捷径数（供节点排序估值），
/// 不修改任何结构；否则真实写入残差邻接、镜像与捷径表。返回（将）新增
/// 的捷径条数。
fn ch_csr_contract(
  n : Int,
  v : Int,
  fwd : Array[Array[(Int, Double)]],
  bwd : Array[Array[(Int, Double)]],
  contracted : Array[Bool],
  shortcuts : Map[Int64, Array[ChCsrShortcut]],
  wdist : Array[Double],
  wstamp : Array[Int],
  wepoch_box : Array[Int],
  pq : @core.PQueue[Int, Double],
  simulate_only : Bool,
) -> Int {
  let mut added = 0
  for in_e in bwd[v] {
    let (u, w_uv) = in_e
    if u == v || contracted[u] {
      continue
    }
    // 该 u 经由 v 可达的最大代价，作为 witness 搜索的统一上界。
    let mut bound = 0.0
    let mut has_target = false
    for out_e in fwd[v] {
      let (x, w_vx) = out_e
      if x == v || x == u || contracted[x] {
        continue
      }
      has_target = true
      let via = w_uv + w_vx
      if via > bound {
        bound = via
      }
    }
    if !has_target {
      continue
    }
    // 一次 witness Dijkstra 覆盖该 u 的全部出端：跑到上界/结算上限为止，
    // 然后逐 x 读取工作区距离判定旁路是否存在。
    wepoch_box[0] = wepoch_box[0] + 1
    let we = wepoch_box[0]
    while !pq.is_empty() {
      let _ = pq.pop()
    }
    wdist[u] = 0.0
    wstamp[u] = we
    pq.push(0.0, u)
    let mut settled = 0
    while !pq.is_empty() && settled < ch_csr_witness_settle_limit {
      let (d, y) = pq.pop().unwrap()
      if wstamp[y] == we && d > wdist[y] {
        continue
      }
      settled = settled + 1
      for e in fwd[y] {
        let (z, w) = e
        if z == v || contracted[z] {
          continue
        }
        let nd = d + w
        if nd > bound {
          continue
        }
        if wstamp[z] != we || nd < wdist[z] {
          wdist[z] = nd
          wstamp[z] = we
          pq.push(nd, z)
        }
      }
    }
    for out_e in fwd[v] {
      let (x, w_vx) = out_e
      if x == v || x == u || contracted[x] {
        continue
      }
      let via = w_uv + w_vx
      let has_witness = wstamp[x] == we && wdist[x] <= via
      if has_witness {
        continue
      }
      added = added + 1
      if !simulate_only {
        fwd[u].push((x, via))
        bwd[x].push((u, via))
        let key = ch_csr_key(n, u, x)
        let lst = shortcuts.get(key).unwrap_or([])
        lst.push({ middle: v, w_left: w_uv, w_right: w_vx })
        shortcuts[key] = lst
      }
    }
  }
  added
}

///|
/// 节点排序估值（论文 §3.1）：`将新增捷径数 - 关联残差边数 +
/// 已收缩邻居数`。值越小越先收缩；已收缩邻居项（deleted neighbours）
/// 使收缩在图上均匀展开，避免局部退化。
fn ch_csr_priority(
  n : Int,
  v : Int,
  fwd : Array[Array[(Int, Double)]],
  bwd : Array[Array[(Int, Double)]],
  contracted : Array[Bool],
  deleted_neighbours : Array[Int],
  shortcuts : Map[Int64, Array[ChCsrShortcut]],
  wdist : Array[Double],
  wstamp : Array[Int],
  wepoch_box : Array[Int],
  pq : @core.PQueue[Int, Double],
) -> Int {
  let sims = ch_csr_contract(
    n, v, fwd, bwd, contracted, shortcuts, wdist, wstamp, wepoch_box, pq, true,
  )
  let mut deg = 0
  for e in fwd[v] {
    if !contracted[e.0] && e.0 != v {
      deg = deg + 1
    }
  }
  for e in bwd[v] {
    if !contracted[e.0] && e.0 != v {
      deg = deg + 1
    }
  }
  sims - deg + deleted_neighbours[v]
}

///|
/// 生产级 CH 预处理入口：对 CSR 图执行完整收缩，产出可供
/// `ch_csr_query` 使用的层级结构。
///
/// 算法（论文 §3）：
///   1. 以 `edge_difference + deleted_neighbours` 估值建初始最小堆；
///   2. 惰性重估主循环——弹出估值最小者，重算其当前估值，若已劣于堆中
///      其余候选则重新入堆，否则赋 rank 并真实收缩（witness 搜索 +
///      捷径写入）；
///   3. 收缩完毕后按 rank 把最终残差边分拣为「向上/向下」CSR 邻接。
///
/// 复杂度：路网/网格类稀疏图上近似 `O(n log n)` 次受限 witness 搜索，
/// 每次结算数以常量截断；十万节点合成路网在 release/native 下秒级完成。
pub fn ch_csr_preprocess(g : @graph.CsrGraph[Double]) -> ChCsr {
  let n = g.n
  // 残差邻接（正向 + 反向镜像），初始自 CSR 物化。
  let fwd : Array[Array[(Int, Double)]] = Array::makei(n, fn(_) { [] })
  let bwd : Array[Array[(Int, Double)]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    let lo = g.row_ptr[u]
    let hi = g.row_ptr[u + 1]
    for k in lo..<hi {
      let v = g.col_idx[k]
      let w = g.weights[k]
      fwd[u].push((v, w))
      bwd[v].push((u, w))
    }
  }
  let contracted : Array[Bool] = Array::make(n, false)
  let deleted_neighbours : Array[Int] = Array::make(n, 0)
  let rank : Array[Int] = Array::make(n, 0)
  let shortcuts : Map[Int64, Array[ChCsrShortcut]] = Map([])
  // witness 工作区（距离 + 世代戳 + 复用堆）。
  let wdist : Array[Double] = Array::make(n, ch_csr_inf)
  let wstamp : Array[Int] = Array::make(n, 0)
  let wepoch_box : Array[Int] = [0]
  let wpq : @core.PQueue[Int, Double] = @core.PQueue::new()
  // 初始估值堆。
  let order : @core.PQueue[Int, Int] = @core.PQueue::new()
  for v in 0..<n {
    let p = ch_csr_priority(
      n, v, fwd, bwd, contracted, deleted_neighbours, shortcuts, wdist, wstamp, wepoch_box,
      wpq,
    )
    order.push(p, v)
  }
  let mut next_rank = 0
  while !order.is_empty() {
    let (prio, v) = order.pop().unwrap()
    if contracted[v] {
      continue
    }
    // 惰性重估：邻域收缩可能已抬高估值；若劣于当前堆顶候选则回堆重排。
    let fresh = ch_csr_priority(
      n, v, fwd, bwd, contracted, deleted_neighbours, shortcuts, wdist, wstamp, wepoch_box,
      wpq,
    )
    if fresh > prio && !order.is_empty() {
      order.push(fresh, v)
      continue
    }
    rank[v] = next_rank
    next_rank = next_rank + 1
    let _ = ch_csr_contract(
      n, v, fwd, bwd, contracted, shortcuts, wdist, wstamp, wepoch_box, wpq, false,
    )
    contracted[v] = true
    // deleted-neighbours 项：通知未收缩邻居其邻域塌缩了一格。
    for e in fwd[v] {
      if !contracted[e.0] {
        deleted_neighbours[e.0] = deleted_neighbours[e.0] + 1
      }
    }
    for e in bwd[v] {
      if !contracted[e.0] {
        deleted_neighbours[e.0] = deleted_neighbours[e.0] + 1
      }
    }
  }
  // 终局残差边按 rank 分拣为向上（正向查询用）/向下（反向查询用，按低端
  // 节点存储入边）两套 CSR 邻接。两趟：先计数后填充，保证紧凑无浪费。
  let up_cnt : Array[Int] = Array::make(n, 0)
  let dn_cnt : Array[Int] = Array::make(n, 0)
  for u in 0..<n {
    for e in fwd[u] {
      let (v, _) = e
      if v == u {
        continue
      }
      if rank[v] > rank[u] {
        up_cnt[u] = up_cnt[u] + 1
      } else {
        dn_cnt[v] = dn_cnt[v] + 1
      }
    }
  }
  let up_row : Array[Int] = Array::make(n + 1, 0)
  let dn_row : Array[Int] = Array::make(n + 1, 0)
  for i in 0..<n {
    up_row[i + 1] = up_row[i] + up_cnt[i]
    dn_row[i + 1] = dn_row[i] + dn_cnt[i]
  }
  let up_total = up_row[n]
  let dn_total = dn_row[n]
  let up_col : Array[Int] = Array::make(up_total, 0)
  let up_w : Array[Double] = Array::make(up_total, 0.0)
  let dn_col : Array[Int] = Array::make(dn_total, 0)
  let dn_w : Array[Double] = Array::make(dn_total, 0.0)
  let up_fill : Array[Int] = Array::make(n, 0)
  let dn_fill : Array[Int] = Array::make(n, 0)
  for u in 0..<n {
    for e in fwd[u] {
      let (v, w) = e
      if v == u {
        continue
      }
      if rank[v] > rank[u] {
        let k = up_row[u] + up_fill[u]
        up_col[k] = v
        up_w[k] = w
        up_fill[u] = up_fill[u] + 1
      } else {
        let k = dn_row[v] + dn_fill[v]
        dn_col[k] = u
        dn_w[k] = w
        dn_fill[v] = dn_fill[v] + 1
      }
    }
  }
  {
    n,
    rank,
    up_row,
    up_col,
    up_w,
    dn_row,
    dn_col,
    dn_w,
    shortcuts,
    dist_f: Array::make(n, ch_csr_inf),
    dist_b: Array::make(n, ch_csr_inf),
    par_f: Array::make(n, -1),
    par_b: Array::make(n, -1),
    pw_f: Array::make(n, 0.0),
    pw_b: Array::make(n, 0.0),
    stamp_f: Array::make(n, 0),
    stamp_b: Array::make(n, 0),
    pq_f: ChHeap::new(),
    pq_b: ChHeap::new(),
    epoch: 0,
  }
}

///|
/// CH 点对点**代价**查询（不构造路径，与只返回代价的基线 Dijkstra
/// 同口径）：双向「仅向上」Dijkstra + stall-on-demand + 会合点扫描，
/// 省去父指针写入与捷径展开。不可达返回 `None`。
pub fn ch_csr_query_cost(g : ChCsr, source : Int, target : Int) -> Double? {
  if source < 0 || source >= g.n || target < 0 || target >= g.n {
    return None
  }
  if source == target {
    return Some(0.0)
  }
  g.epoch = g.epoch + 1
  let ep = g.epoch
  g.pq_f.clear()
  g.pq_b.clear()
  g.dist_f[source] = 0.0
  g.stamp_f[source] = ep
  g.pq_f.push(0.0, source)
  g.dist_b[target] = 0.0
  g.stamp_b[target] = ep
  g.pq_b.push(0.0, target)
  let mut best = ch_csr_inf
  while !g.pq_f.is_empty() || !g.pq_b.is_empty() {
    let f_top = g.pq_f.min_key()
    let b_top = g.pq_b.min_key()
    if f_top >= best && b_top >= best {
      break
    }
    if f_top <= b_top {
      let _ = g.pq_f.pop()
      let d = g.pq_f.top_key
      let u = g.pq_f.top_val
      if g.stamp_f[u] == ep && d > g.dist_f[u] {
        continue
      }
      if g.stamp_b[u] == ep {
        let total = d + g.dist_b[u]
        if total < best {
          best = total
        }
      }
      let mut stalled = false
      for k in g.dn_row[u]..<g.dn_row[u + 1] {
        let v = g.dn_col[k]
        if g.stamp_f[v] == ep && g.dist_f[v] + g.dn_w[k] < d {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      for k in g.up_row[u]..<g.up_row[u + 1] {
        let v = g.up_col[k]
        let nd = d + g.up_w[k]
        if g.stamp_f[v] != ep || nd < g.dist_f[v] {
          g.dist_f[v] = nd
          g.stamp_f[v] = ep
          g.pq_f.push(nd, v)
        }
      }
    } else {
      let _ = g.pq_b.pop()
      let d = g.pq_b.top_key
      let u = g.pq_b.top_val
      if g.stamp_b[u] == ep && d > g.dist_b[u] {
        continue
      }
      if g.stamp_f[u] == ep {
        let total = d + g.dist_f[u]
        if total < best {
          best = total
        }
      }
      let mut stalled = false
      for k in g.up_row[u]..<g.up_row[u + 1] {
        let v = g.up_col[k]
        if g.stamp_b[v] == ep && g.dist_b[v] + g.up_w[k] < d {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      for k in g.dn_row[u]..<g.dn_row[u + 1] {
        let v = g.dn_col[k]
        let nd = d + g.dn_w[k]
        if g.stamp_b[v] != ep || nd < g.dist_b[v] {
          g.dist_b[v] = nd
          g.stamp_b[v] = ep
          g.pq_b.push(nd, v)
        }
      }
    }
  }
  if best == ch_csr_inf {
    None
  } else {
    Some(best)
  }
}

///|
/// 在捷径表中为有序对 `(a, b)` 挑选权重与 `w` 逐位相等的分解记录。
///
/// 展开阶段的层级守卫（与通用版 `ch_shortcut_mid` 同源，R8.1）：中间点
/// 的 rank 必须**严格低于**两端点，保证每次分解使 `rank` 之和严格下降，
/// 栈式展开必然终止；权重精确匹配则保证展开出的原图路径逐边权重和与
/// 查询代价逐位一致（同一加法顺序，三后端确定）。
fn ch_csr_find_shortcut(
  g : ChCsr,
  a : Int,
  b : Int,
  w : Double,
) -> ChCsrShortcut? {
  match g.shortcuts.get(ch_csr_key(g.n, a, b)) {
    Some(records) => {
      for r in records {
        if r.middle == a || r.middle == b {
          continue
        }
        if g.rank[r.middle] >= g.rank[a] || g.rank[r.middle] >= g.rank[b] {
          continue
        }
        if r.w_left + r.w_right == w {
          return Some(r)
        }
      }
      None
    }
    None => None
  }
}

///|
/// 把一条（可能是捷径的）带权边 `(u, v, w)` 栈式展开为原图节点序列
/// `[u, …, v]`。左子边后进先出，保证输出保持正向次序；无匹配捷径记录
/// 时按原始直边输出（安全降级，R8.1）。
fn ch_csr_expand_edge(g : ChCsr, u : Int, v : Int, w : Double) -> Array[Int] {
  let out : Array[Int] = [u]
  let stack : Array[(Int, Int, Double)] = [(u, v, w)]
  while stack.length() > 0 {
    let (a, b, wab) = stack.pop().unwrap()
    match ch_csr_find_shortcut(g, a, b, wab) {
      Some(r) => {
        stack.push((r.middle, b, r.w_right))
        stack.push((a, r.middle, r.w_left))
      }
      None => out.push(b)
    }
  }
  out
}

///|
/// CH 点对点查询（论文 §4）：双向「仅向上」Dijkstra + 会合点扫描 +
/// 捷径展开。返回 `(原图节点路径, 最短代价)`；不可达返回 `None`。
///
/// 性能要点：
///   * 距离/父指针/父边权工作区常驻结构体，世代戳复位，单查询摊还零分配；
///   * 双侧堆顶均超过当前最优会合代价时提前终止（标准双向停机准则）；
///   * 向上搜索空间在路网/网格上呈多对数规模，故查询较点对点 Dijkstra
///     快出数量级（R8.5 加速比证据由基准采集器复核）。
pub fn ch_csr_query(
  g : ChCsr,
  source : Int,
  target : Int,
) -> (Array[Int], Double)? {
  if source < 0 || source >= g.n || target < 0 || target >= g.n {
    return None
  }
  if source == target {
    return Some(([source], 0.0))
  }
  g.epoch = g.epoch + 1
  let ep = g.epoch
  let pq_f = g.pq_f
  let pq_b = g.pq_b
  pq_f.clear()
  pq_b.clear()
  g.dist_f[source] = 0.0
  g.stamp_f[source] = ep
  g.par_f[source] = -1
  pq_f.push(0.0, source)
  g.dist_b[target] = 0.0
  g.stamp_b[target] = ep
  g.par_b[target] = -1
  pq_b.push(0.0, target)
  let mut best = ch_csr_inf
  let mut meet = -1
  // 交替推进双侧搜索；两侧堆顶均不小于当前最优会合代价时停机。
  while !pq_f.is_empty() || !pq_b.is_empty() {
    let f_top = pq_f.min_key()
    let b_top = pq_b.min_key()
    if f_top >= best && b_top >= best {
      break
    }
    if f_top <= b_top {
      let _ = pq_f.pop()
      let d = pq_f.top_key
      let u = pq_f.top_val
      if g.stamp_f[u] == ep && d > g.dist_f[u] {
        continue
      }
      if g.stamp_b[u] == ep {
        let total = d + g.dist_b[u]
        if total < best {
          best = total
          meet = u
        }
      }
      // stall-on-demand（论文 §4 优化）：若存在更高层节点 v 经向下边
      // v -> u 给出比 dist_f[u] 更短的入距，则 u 上的标签必非最短前缀，
      // 跳过其松弛（不影响正确性，显著剪小向上搜索空间）。
      let slo = g.dn_row[u]
      let shi = g.dn_row[u + 1]
      let mut stalled = false
      for k in slo..<shi {
        let v = g.dn_col[k]
        if g.stamp_f[v] == ep && g.dist_f[v] + g.dn_w[k] < d {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      let lo = g.up_row[u]
      let hi = g.up_row[u + 1]
      for k in lo..<hi {
        let v = g.up_col[k]
        let w = g.up_w[k]
        let nd = d + w
        if g.stamp_f[v] != ep || nd < g.dist_f[v] {
          g.dist_f[v] = nd
          g.stamp_f[v] = ep
          g.par_f[v] = u
          g.pw_f[v] = w
          pq_f.push(nd, v)
        }
      }
    } else {
      let _ = pq_b.pop()
      let d = pq_b.top_key
      let u = pq_b.top_val
      if g.stamp_b[u] == ep && d > g.dist_b[u] {
        continue
      }
      if g.stamp_f[u] == ep {
        let total = d + g.dist_f[u]
        if total < best {
          best = total
          meet = u
        }
      }
      // stall-on-demand（反向对称）：若存在更高层 v 经向上边 u -> v 给出
      // 更短的到目标距离，则 u 的反向标签必非最短，跳过其松弛。
      let slo = g.up_row[u]
      let shi = g.up_row[u + 1]
      let mut stalled = false
      for k in slo..<shi {
        let v = g.up_col[k]
        if g.stamp_b[v] == ep && g.dist_b[v] + g.up_w[k] < d {
          stalled = true
          break
        }
      }
      if stalled {
        continue
      }
      let lo = g.dn_row[u]
      let hi = g.dn_row[u + 1]
      for k in lo..<hi {
        let v = g.dn_col[k]
        let w = g.dn_w[k]
        let nd = d + w
        if g.stamp_b[v] != ep || nd < g.dist_b[v] {
          g.dist_b[v] = nd
          g.stamp_b[v] = ep
          g.par_b[v] = u
          g.pw_b[v] = w
          pq_b.push(nd, v)
        }
      }
    }
  }
  if meet < 0 {
    return None
  }
  // 正向半程：source -> … -> meet（父指针回溯后反转）。
  let fwd_nodes : Array[Int] = []
  let fwd_ws : Array[Double] = []
  let mut cur = meet
  while cur != source {
    fwd_nodes.push(cur)
    fwd_ws.push(g.pw_f[cur])
    cur = g.par_f[cur]
  }
  fwd_nodes.push(source)
  fwd_nodes.rev_in_place()
  fwd_ws.rev_in_place()
  // 反向半程：meet -> … -> target（par_b[u] = v 意味残差边 u -> v）。
  let bwd_nodes : Array[Int] = []
  let bwd_ws : Array[Double] = []
  let mut cur2 = meet
  while cur2 != target {
    let p = g.par_b[cur2]
    bwd_nodes.push(p)
    bwd_ws.push(g.pw_b[cur2])
    cur2 = p
  }
  // 组装 CH 级链：[source..meet] ++ [meet 之后的反向段]，随后逐边展开。
  let out : Array[Int] = [fwd_nodes[0]]
  for i in 0..<(fwd_nodes.length() - 1) {
    let seg = ch_csr_expand_edge(g, fwd_nodes[i], fwd_nodes[i + 1], fwd_ws[i])
    for j in 1..<seg.length() {
      out.push(seg[j])
    }
  }
  let mut prev = meet
  for i in 0..<bwd_nodes.length() {
    let nxt = bwd_nodes[i]
    let seg = ch_csr_expand_edge(g, prev, nxt, bwd_ws[i])
    for j in 1..<seg.length() {
      out.push(seg[j])
    }
    prev = nxt
  }
  Some((out, best))
}
