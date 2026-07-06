// many_to_many.mbt —— Bucket-based many-to-many（Knopp et al. 2007）：
// CH 之上一次算出 |S|×|T| 全对最短距离表。
//
// 两阶段：
//   1. 后向阶段：对每个 t_j 做「反向向上」搜索（走 bo 入边 CSR），
//      在每个 settle 的节点 v 上挂桶项 (j, d(v→t_j))。
//   2. 前向阶段：对每个 s_i 做「前向向上」搜索（走 fo 出边 CSR），
//      在每个 settle 的节点 v 上扫 v 的桶，用 d(s_i→v)+桶距 更新
//      D[i*|T|+j]。
//
// 交汇正确性同 CH 双向查询：s→t 的最短路必在某最高 rank 节点分界，
// 该节点同时被前向、后向搜索 settle。相比逐对 CH 查询，桶复用把
// 每个 target 的后向搜索摊到全部 source 上，是批量距离表的标准做法。

///|
/// 计算 sources × targets 的全对最短距离表（行主序，长度
/// |S|*|T|），不可达为 `INF_DIST`。
pub fn ContractionHierarchy::many_to_many(
  self : ContractionHierarchy,
  sources : Array[Int],
  targets : Array[Int],
) -> Array[Int64] {
  let n = self.n
  let ns = sources.length()
  let nt = targets.length()
  let out = Array::make(ns * nt, INF_DIST)
  if ns == 0 || nt == 0 {
    return out
  }
  // 每节点的桶：并行数组 (target 序号, 距离)。
  let bkt_j : Array[Array[Int]] = Array::make(n, [])
  let bkt_d : Array[Array[Int64]] = Array::make(n, [])
  for v in 0..<n {
    bkt_j[v] = []
    bkt_d[v] = []
  }
  let mask = (1L << NODE_BITS) - 1L
  // 后向搜索复用暂存（代戳懒失效）。
  let dist = Array::make(n, INF_DIST)
  let stamp = Array::make(n, 0)
  let mut gen = 0
  let heap = self.hb
  // —— 阶段 1：后向向上搜索，填桶 ——
  for j in 0..<nt {
    let t = targets[j]
    guard t >= 0 && t < n
    gen = gen + 1
    heap.reset(0L)
    dist[t] = 0L
    stamp[t] = gen
    heap.push(t.to_int64())
    while heap.len > 0 {
      let enc = heap.pop()
      let u = (enc & mask).to_int()
      let du = enc >> NODE_BITS
      if stamp[u] == gen && du > dist[u] {
        continue
      }
      bkt_j[u].push(j)
      bkt_d[u].push(du)
      let stop = self.bo[u + 1]
      for ei = self.bo[u]; ei < stop; ei = ei + 1 {
        let v = self.bt[ei]
        let nd = du + self.bw[ei]
        if stamp[v] != gen || nd < dist[v] {
          dist[v] = nd
          stamp[v] = gen
          heap.push((nd << NODE_BITS) | v.to_int64())
        }
      }
    }
  }
  // —— 阶段 2：前向向上搜索，扫桶合并 ——
  let hf = self.hf
  for i in 0..<ns {
    let s = sources[i]
    guard s >= 0 && s < n
    gen = gen + 1
    hf.reset(0L)
    dist[s] = 0L
    stamp[s] = gen
    hf.push(s.to_int64())
    let brow = i * nt
    while hf.len > 0 {
      let enc = hf.pop()
      let u = (enc & mask).to_int()
      let du = enc >> NODE_BITS
      if stamp[u] == gen && du > dist[u] {
        continue
      }
      // 扫 u 的桶：s→u→t_j 候选。
      let bj = bkt_j[u]
      let bd = bkt_d[u]
      for k = 0; k < bj.length(); k = k + 1 {
        let idx = brow + bj[k]
        let cand = du + bd[k]
        if cand < out[idx] {
          out[idx] = cand
        }
      }
      let stop = self.fo[u + 1]
      for ei = self.fo[u]; ei < stop; ei = ei + 1 {
        let v = self.ft[ei]
        let nd = du + self.fw[ei]
        if stamp[v] != gen || nd < dist[v] {
          dist[v] = nd
          stamp[v] = gen
          hf.push((nd << NODE_BITS) | v.to_int64())
        }
      }
    }
  }
  out
}
