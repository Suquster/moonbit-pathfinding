// Kuhn-Munkres / Hungarian algorithm for maximum-weight bipartite matching.
//
// Reference: Kuhn, H. W. (1955). "The Hungarian method for the assignment
// problem". Naval Research Logistics Quarterly, 2(1-2), 83-97.

///|
/// Sentinel "infinite" cost used by the label-update search. Large enough
/// to dominate any realistic cost sum while staying far from Double
/// overflow.
const KM_INF : Double = 1.0e18

///|
/// Solve the assignment problem: given an n×n cost matrix, find the
/// permutation that minimizes the sum of costs.
///
/// ## Parameters
/// - `cost`: a square n×n matrix where `cost[i][j]` is the cost of assigning
///   worker `i` to job `j`.
///
/// ## Returns
/// - `Ok((assignment, total_cost))` — `assignment[i]` is the job assigned to
///   worker `i`; `total_cost` is the minimum sum.
/// - `Err(InvalidInput(...))` if the matrix is not square.
///
/// ## Complexity
/// Time: O(n^3). Space: O(n^2).
pub fn kuhn_munkres(
  cost : Array[Array[Double]],
) -> Result[(Array[Int], Double), @core.PathError] {
  let n = cost.length()
  if n == 0 {
    return Ok(([], 0.0))
  }
  for row in cost {
    if row.length() != n {
      return Err(InvalidInput("cost matrix must be square"))
    }
  }
  // Hungarian algorithm O(n^3) implementation using labels u, v and match arrays.
  let u : Array[Double] = Array::make(n + 1, 0.0)
  let v : Array[Double] = Array::make(n + 1, 0.0)
  let p : Array[Int] = Array::make(n + 1, 0) // p[j] = worker assigned to job j (0 = unassigned)
  let way : Array[Int] = Array::make(n + 1, 0)
  //
  // 循环不变式（R10.1 · Kuhn-Munkres 主循环 · 谓词见 @proofs.perfect_matching_weight）:
  //
  //   (布尔陈述) 处理完前 i-1 个工人后，对偶标号满足可行性 u[a]+v[b] <= cost[a][b]
  //       （对所有 a,b），且 p[] 编码的部分匹配恰覆盖前 i-1 个工人，在当前标号下每条
  //       匹配边都「紧」（等号成立），即匹配为当前对偶下的最优部分指派。
  //
  //   (初始化成立) i=1 时所有 u、v 为 0，p[] 全未指派：0+0 <= cost[a][b]（成本非负
  //       前提）满足可行性；空匹配平凡最优。
  //
  //   (迭代保持) 第 i 轮以工人 i 为根，重复扩展交错树并按 delta 调整对偶标号（保持
  //       u[a]+v[b] <= cost[a][b] 且已匹配边维持紧），直至触达一个未匹配工作 j0；沿
  //       way[] 回溯增广，使匹配规模 +1 仍全部为紧边。故每轮恰新增一条最优匹配边，n 轮
  //       后得到 n 个工人的最小总成本完美指派。
  //
  for i in 1..<=n {
    p[0] = i
    let mut j0 = 0
    let minv : Array[Double] = Array::make(n + 1, KM_INF)
    let used : Array[Bool] = Array::make(n + 1, false)
    while true {
      used[j0] = true
      let i0 = p[j0]
      let mut delta = KM_INF
      let mut j1 = 0
      for j in 1..<=n {
        if !used[j] {
          let cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
          if cur < minv[j] {
            minv[j] = cur
            way[j] = j0
          }
          if minv[j] < delta {
            delta = minv[j]
            j1 = j
          }
        }
      }
      for j in 0..<=n {
        if used[j] {
          u[p[j]] = u[p[j]] + delta
          v[j] = v[j] - delta
        } else {
          minv[j] = minv[j] - delta
        }
      }
      j0 = j1
      if p[j0] == 0 {
        break
      }
    }
    while j0 != 0 {
      let j1 = way[j0]
      p[j0] = p[j1]
      j0 = j1
    }
  }
  let assignment : Array[Int] = Array::make(n, -1)
  for j in 1..<=n {
    if p[j] > 0 {
      assignment[p[j] - 1] = j - 1
    }
  }
  let mut total = 0.0
  for i in 0..<n {
    if assignment[i] >= 0 {
      total = total + cost[i][assignment[i]]
    }
  }
  Ok((assignment, total))
}
