// rphast.mbt —— RPHAST（restricted PHAST，Delling et al. 2011）：
// 目标子集限定的批量最短路。
//
// 固定目标集 T 时，一次预处理提取「T 的后向搜索空间并集」R
// （沿反向向上图从 T 可达的全部节点）及其 rank 降序受限下行
// CSR；之后每个源只需一次向上 Dijkstra + 对 R 的线性扫描即可
// 得到到全部 T 的距离。|R| 通常远小于 n，适合大 |S| × 小 |T|
// 的批量场景（如到少量设施点的可达性矩阵）。

///|
/// 目标子集的 RPHAST 预处理产物（R 集与受限下行 CSR）。
pub struct RphastTargets {
  /// R 的 rank 降序节点表（位置 → 节点 id）。
  nodes : Array[Int]
  /// 各 target 在 R 中的位置（与构建时 targets 顺序一致）。
  tpos : Array[Int]
  /// 受限下行 CSR（按目标位置分桶，源存 R 位置）。
  dofs : Array[Int]
  dsrc : Array[Int]
  dwt : Array[Int64]
  /// R 位置空间距离暂存。
  rd : Array[Int64]
  /// 前向向上搜索暂存（代戳懒失效）。
  fd : Array[Int64]
  fs : Array[Int]
  mut fgen : Int
}

///|
/// 受限搜索空间 |R| 的大小（诊断/回本分析用）。
pub fn RphastTargets::restricted_size(self : RphastTargets) -> Int {
  self.nodes.length()
}

///|
/// 对固定目标集做 RPHAST 预处理：反向向上 BFS 收集 R，
/// 并构建 rank 降序受限下行 CSR。O(|R| + 相关边数)。
pub fn ContractionHierarchy::rphast_targets(
  self : ContractionHierarchy,
  targets : Array[Int],
) -> RphastTargets {
  let n = self.n
  let inr = Array::make(n, false)
  let stack : Array[Int] = []
  for t in targets {
    guard t >= 0 && t < n
    if !inr[t] {
      inr[t] = true
      stack.push(t)
    }
  }
  while stack.length() > 0 {
    let v = stack.unsafe_pop()
    let stop = self.bo[v + 1]
    for ei = self.bo[v]; ei < stop; ei = ei + 1 {
      let u = self.bt[ei]
      if !inr[u] {
        inr[u] = true
        stack.push(u)
      }
    }
  }
  // rank 降序排列 R（借 ord：全局 rank 降序过滤）。
  let nodes : Array[Int] = []
  let pos = Array::make(n, -1)
  for i in 0..<n {
    let v = self.ord[i]
    if inr[v] {
      pos[v] = nodes.length()
      nodes.push(v)
    }
  }
  let r = nodes.length()
  let dofs = Array::make(r + 1, 0)
  for i in 0..<r {
    let v = nodes[i]
    let mut c = 0
    let stop = self.bo[v + 1]
    for ei = self.bo[v]; ei < stop; ei = ei + 1 {
      if pos[self.bt[ei]] >= 0 {
        c = c + 1
      }
    }
    dofs[i + 1] = dofs[i] + c
  }
  let dsrc = Array::make(dofs[r], 0)
  let dwt = Array::make(dofs[r], 0L)
  for i in 0..<r {
    let v = nodes[i]
    let mut c = dofs[i]
    let stop = self.bo[v + 1]
    for ei = self.bo[v]; ei < stop; ei = ei + 1 {
      let p = pos[self.bt[ei]]
      if p >= 0 {
        dsrc[c] = p
        dwt[c] = self.bw[ei]
        c = c + 1
      }
    }
  }
  let tpos = Array::make(targets.length(), 0)
  for j in 0..<targets.length() {
    tpos[j] = pos[targets[j]]
  }
  {
    nodes,
    tpos,
    dofs,
    dsrc,
    dwt,
    rd: Array::make(r, 0L),
    fd: Array::make(n, 0L),
    fs: Array::make(n, 0),
    fgen: 0,
  }
}

///|
/// RPHAST 查询：源 s 到全部预处理 targets 的最短距离，
/// 写入 out（长度须为 |targets|），不可达为 `INF_DIST`。
pub fn ContractionHierarchy::rphast_query(
  self : ContractionHierarchy,
  rt : RphastTargets,
  s : Int,
  out : Array[Int64],
) -> Unit {
  let n = self.n
  guard s >= 0 && s < n && out.length() == rt.tpos.length()
  // 阶段 1：前向向上 Dijkstra（代戳懒失效）。
  let mask = (1L << NODE_BITS) - 1L
  rt.fgen = rt.fgen + 1
  let gen = rt.fgen
  let fd = rt.fd
  let fs = rt.fs
  let heap = self.hf
  heap.reset(0L)
  fd[s] = 0L
  fs[s] = gen
  heap.push(s.to_int64())
  while heap.len > 0 {
    let enc = heap.pop()
    let u = (enc & mask).to_int()
    let du = enc >> NODE_BITS
    if du > fd[u] {
      continue
    }
    let stop = self.fo[u + 1]
    for ei = self.fo[u]; ei < stop; ei = ei + 1 {
      let v = self.ft[ei]
      let nd = du + self.fw[ei]
      if fs[v] != gen || nd < fd[v] {
        fd[v] = nd
        fs[v] = gen
        heap.push((nd << NODE_BITS) | v.to_int64())
      }
    }
  }
  // 阶段 2：R 位置空间线性扫描（受限下行边，无堆）。
  let nodes = rt.nodes
  let rd = rt.rd
  let r = nodes.length()
  for i = 0; i < r; i = i + 1 {
    let v = nodes[i]
    rd[i] = if fs[v] == gen { fd[v] } else { INF_DIST }
  }
  let dofs = rt.dofs
  let dsrc = rt.dsrc
  let dwt = rt.dwt
  for i = 0; i < r; i = i + 1 {
    let stop = dofs[i + 1]
    let mut dv = rd[i]
    for ei = dofs[i]; ei < stop; ei = ei + 1 {
      let du = rd[dsrc[ei]]
      if du < INF_DIST {
        let nd = du + dwt[ei]
        if nd < dv {
          dv = nd
        }
      }
    }
    rd[i] = dv
  }
  for j = 0; j < out.length(); j = j + 1 {
    out[j] = rd[rt.tpos[j]]
  }
}
