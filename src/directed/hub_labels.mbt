// hub_labels.mbt —— Hub Labeling（2-hop 标签，Abraham et al. 2011）。
//
// 路网点对点「距离」查询的最快档：在 CH 之上按 rank 降序为每个节点
// 构建前向/后向标签（hub, 距离），查询只需归并两条有序标签数组取
// 最小和，O(|L_s|+|L_t|)，真实路网上 µs 级以下。正确性由 CH 向上
// 覆盖性保证：最短路径的最高 rank 节点必同时出现在两侧标签中且
// 距离精确；构建期用已有标签做剪枝（可被其他 hub 支配的条目删除）
// 压缩标签规模。距离语义与 dijkstra_indexed 一致，路径还原请配合
// ContractionHierarchy::query 使用。

///|
/// Hub Labeling 预处理产物（标签 CSR 扁平化：packed=(hub<<42)|dist，
/// 按 hub 升序，归并查询缓存友好）。
pub struct HubLabels {
  n : Int
  /// 前向标签 CSR：flo[v]..flo[v+1] 为 v 的出向标签。
  flo : Array[Int]
  fla : Array[Int64]
  /// 后向标签 CSR：blo[v]..blo[v+1] 为 v 的入向标签。
  blo : Array[Int]
  bla : Array[Int64]
}

///|
/// 标签条目 hub 位移（dist 占低 42 位，路网分米权域足够）。
const HL_HUB_SHIFT : Int = 42

///|
/// 有序标签归并取最小和；skip_hub >= 0 时跳过该 hub（剪枝自查用）。
fn hl_merge_min(
  a : Array[Int64],
  a_lo : Int,
  a_hi : Int,
  b : Array[Int64],
  b_lo : Int,
  b_hi : Int,
  skip_hub : Int,
) -> Int64 {
  let dmask = (1L << HL_HUB_SHIFT) - 1L
  let mut i = a_lo
  let mut j = b_lo
  let mut best = INF_DIST
  while i < a_hi && j < b_hi {
    let ha = a[i] >> HL_HUB_SHIFT
    let hb = b[j] >> HL_HUB_SHIFT
    if ha < hb {
      i = i + 1
    } else if ha > hb {
      j = j + 1
    } else {
      if ha.to_int() != skip_hub {
        let s = (a[i] & dmask) + (b[j] & dmask)
        if s < best {
          best = s
        }
      }
      i = i + 1
      j = j + 1
    }
  }
  best
}

///|
/// 从已建 CH 构建 Hub Labeling。按 rank 降序处理：节点标签 =
/// {自身:0} ∪ (各向上邻居标签 + 边权)，同 hub 保最小距离，再用
/// 已有标签做支配剪枝（存在其他 hub 给出不更长距离则删条目）。
pub fn HubLabels::build(ch : ContractionHierarchy) -> HubLabels {
  let n = ch.n
  let dmask = (1L << HL_HUB_SHIFT) - 1L
  // rank 降序处理序
  let ord = Array::make(n, 0)
  for v in 0..<n {
    ord[n - 1 - ch.rank[v]] = v
  }
  let lf : Array[Array[Int64]] = Array::make(n, [])
  let lb : Array[Array[Int64]] = Array::make(n, [])
  // 收集缓冲（hub -> 最小距，代戳懒失效）
  let cd = Array::make(n, 0L)
  let cs = Array::make(n, 0)
  let mut cgen = 0
  let hubs : Array[Int] = []
  fn gather(
    labels : Array[Array[Int64]],
    off : Array[Int],
    tgt : Array[Int],
    wt : Array[Int64],
    v : Int,
  ) -> Array[Int64] {
    cgen = cgen + 1
    hubs.clear()
    cd[v] = 0L
    cs[v] = cgen
    hubs.push(v)
    let stop = off[v + 1]
    for ei = off[v]; ei < stop; ei = ei + 1 {
      let u = tgt[ei]
      let w = wt[ei]
      let lu = labels[u]
      for i = 0; i < lu.length(); i = i + 1 {
        let h = (lu[i] >> HL_HUB_SHIFT).to_int()
        let d = (lu[i] & dmask) + w
        if cs[h] != cgen {
          cs[h] = cgen
          cd[h] = d
          hubs.push(h)
        } else if d < cd[h] {
          cd[h] = d
        }
      }
    }
    let out : Array[Int64] = Array::make(hubs.length(), 0L)
    for i = 0; i < hubs.length(); i = i + 1 {
      let h = hubs[i]
      out[i] = (h.to_int64() << HL_HUB_SHIFT) | cd[h]
    }
    out.sort()
    out
  }

  // 支配剪枝：条目 (h,d) 若可经其他公共 hub 以 <=d 覆盖则删。
  // 前向条目用 lb[h] 自查，后向条目用 lf[h] 自查（h rank 更高已建好）。
  fn prune(
    cand : Array[Int64],
    v : Int,
    other : Array[Array[Int64]],
  ) -> Array[Int64] {
    let out : Array[Int64] = []
    for i = 0; i < cand.length(); i = i + 1 {
      let h = (cand[i] >> HL_HUB_SHIFT).to_int()
      if h == v {
        out.push(cand[i])
        continue
      }
      let d = cand[i] & dmask
      let lo = other[h]
      let q = hl_merge_min(cand, 0, cand.length(), lo, 0, lo.length(), h)
      if q > d {
        out.push(cand[i])
      }
    }
    out
  }

  for i = 0; i < n; i = i + 1 {
    let v = ord[i]
    let cf = gather(lf, ch.fo, ch.ft, ch.fw, v)
    let cb = gather(lb, ch.bo, ch.bt, ch.bw, v)
    lf[v] = prune(cf, v, lb)
    lb[v] = prune(cb, v, lf)
  }
  // 扁平化 CSR
  let flo = Array::make(n + 1, 0)
  let blo = Array::make(n + 1, 0)
  for v in 0..<n {
    flo[v + 1] = flo[v] + lf[v].length()
    blo[v + 1] = blo[v] + lb[v].length()
  }
  let fla = Array::make(flo[n], 0L)
  let bla = Array::make(blo[n], 0L)
  for v in 0..<n {
    let a = lf[v]
    for i = 0; i < a.length(); i = i + 1 {
      fla[flo[v] + i] = a[i]
    }
    let b = lb[v]
    for i = 0; i < b.length(); i = i + 1 {
      bla[blo[v] + i] = b[i]
    }
  }
  { n, flo, fla, blo, bla }
}

///|
/// 平均标签条目数（前向+后向合计 / 2n，内存/性能诊断用）。
pub fn HubLabels::avg_label_size(self : HubLabels) -> Double {
  (self.flo[self.n] + self.blo[self.n]).to_double() / (2 * self.n).to_double()
}

///|
/// 点对点最短距离：归并 s 前向标签与 t 后向标签取最小和。
/// 不可达返回 None。O(|L_s|+|L_t|)。
pub fn HubLabels::query(self : HubLabels, s : Int, t : Int) -> Int64? {
  guard s >= 0 && s < self.n && t >= 0 && t < self.n else { None }
  let best = hl_merge_min(
    self.fla,
    self.flo[s],
    self.flo[s + 1],
    self.bla,
    self.blo[t],
    self.blo[t + 1],
    -1,
  )
  if best >= INF_DIST {
    None
  } else {
    Some(best)
  }
}
