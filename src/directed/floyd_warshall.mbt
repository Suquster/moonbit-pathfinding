// Floyd-Warshall all-pairs shortest paths.
//
// Reference: Floyd, R. W. (1962). "Algorithm 97: Shortest Path".
// Communications of the ACM. 5 (6): 345.

///|
/// Compute shortest distances between every pair of nodes in a weighted
/// directed graph. Supports negative edge weights (without negative cycles).
///
/// ## Parameters
/// - `nodes`: complete list of nodes
/// - `edges`: list of `(u, v, weight)` directed edges
///
/// ## Returns
/// A map from `(u, v)` pairs to shortest distance. Unreachable pairs are
/// assigned `Weight::infinity()`. Self-pairs `(u, u)` are `Weight::zero()`.
///
/// ## Complexity
/// Time: O(V^3). Space: O(V^2).
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] floyd_warshall(
  nodes : Array[N],
  edges : Array[(N, N, W)],
) -> Map[(N, N), W] {
  let zero = @core.Weight::zero()
  let inf = @core.Weight::infinity()
  let n = nodes.length()
  if n == 0 {
    return Map([])
  }
  // Work on a dense index-based matrix internally: O(1) array access in the
  // O(V^3) triple loop instead of hashing tuple keys on every read/write.
  let index : Map[N, Int] = Map([])
  for i in 0..<n {
    index[nodes[i]] = i
  }
  let dist : Array[W] = Array::make(n * n, inf)
  for i in 0..<n {
    dist[i * n + i] = zero
  }
  // Apply direct edges (take the minimum in case of parallel edges).
  for edge in edges {
    let (u, v, w) = edge
    match (index.get(u), index.get(v)) {
      (Some(iu), Some(iv)) => {
        let pos = iu * n + iv
        if w < dist[pos] {
          dist[pos] = w
        }
      }
      _ => ()
    }
  }
  // Classic triple loop: k is the allowed intermediate node.
  //
  // 循环不变式（R10.1 · Floyd-Warshall 三重主循环 · 谓词见 @proofs.floyd_warshall_post）:
  //
  //   (布尔陈述) 外层进入第 k 轮前，dist[i*n+j] 等于「仅允许以索引 < k 的节点作为
  //       中间点」时从 i 到 j 的最短距离（不可达记为 +∞，自身为 zero）。
  //
  //   (初始化成立) k = 0 时不允许任何中间点：dist 仅由直接边与对角 zero 初始化，
  //       恰为「无中间点」的最短距离，命题成立。
  //
  //   (迭代保持) 第 k 轮以 k 为新允许中间点，对所有 (i,j) 取
  //       min(dist[i,j], dist[i,k] + dist[k,j])。任意「中间点 ⊆ {0..k}」的最短路要么
  //       不经过 k（被旧值覆盖），要么经过 k 恰一次（被 dist[i,k]+dist[k,j] 覆盖，
  //       两段中间点均 ⊆ {0..k-1} 由归纳成立）；故第 k 轮后命题对 k+1 成立。
  //
  for k in 0..<n {
    for i in 0..<n {
      let dik = dist[i * n + k]
      // Skip if the first half is infinity (avoids saturating add overflow
      // and prunes the whole inner row in one check).
      if dik == inf {
        continue
      }
      for j in 0..<n {
        let dkj = dist[k * n + j]
        if dkj != inf {
          let candidate = @core.Weight::add(dik, dkj)
          if candidate < dist[i * n + j] {
            dist[i * n + j] = candidate
          }
        }
      }
    }
  }
  // Export back to the (u, v) keyed map for the public API.
  let out : Map[(N, N), W] = Map([])
  for i in 0..<n {
    for j in 0..<n {
      out[(nodes[i], nodes[j])] = dist[i * n + j]
    }
  }
  out
}
