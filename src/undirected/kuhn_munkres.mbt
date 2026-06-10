// Kuhn-Munkres / Hungarian algorithm for maximum-weight bipartite matching.
//
// Reference: Kuhn, H. W. (1955). "The Hungarian method for the assignment
// problem". Naval Research Logistics Quarterly, 2(1-2), 83-97.

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
  for i in 1..<=n {
    p[0] = i
    let mut j0 = 0
    let minv : Array[Double] = Array::make(n + 1, 1.0e18)
    let used : Array[Bool] = Array::make(n + 1, false)
    while true {
      used[j0] = true
      let i0 = p[j0]
      let mut delta = 1.0e18
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
