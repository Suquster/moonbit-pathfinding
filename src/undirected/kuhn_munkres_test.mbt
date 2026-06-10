// Blackbox tests for Kuhn-Munkres assignment.

///|
test "kuhn_munkres 3x3 known optimal" {
  // Optimal assignment: 0->2 (5), 1->0 (2), 2->1 (4), total = 11
  // Hungarian minimizes; with this matrix, min is at 2+4+1 = 7 via 1->0,2->1,0->2
  // Let's build a simple known case: identity matrix permutation.
  let cost : Array[Array[Double]] = [
    [4.0, 1.0, 3.0],
    [2.0, 0.0, 5.0],
    [3.0, 2.0, 2.0],
  ]
  let result = kuhn_munkres(cost)
  match result {
    Ok((_assignment, total)) =>
      // Known minimum for this matrix is 5.0 (e.g., 0->1=1, 1->0=2, 2->2=2).
      inspect(total, content="5")
    Err(_) => inspect(false, content="true")
  }
}

///|
test "kuhn_munkres non-square returns error" {
  let cost : Array[Array[Double]] = [[1.0, 2.0], [3.0, 4.0, 5.0]]
  let result = kuhn_munkres(cost)
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="true")
  }
}

///|
/// Brute-force reference solver for the assignment problem.
///
/// Enumerates all `n!` permutations using the iterative variant of Heap's
/// algorithm and returns the minimum total cost. Only suitable as a test
/// oracle for small `n` (used here with `n = 4`, i.e. 24 permutations).
fn brute_force_min_assignment(cost : Array[Array[Double]]) -> Double {
  let n = cost.length()
  if n == 0 {
    return 0.0
  }
  // Current permutation (starts as identity) and Heap's-algorithm counters.
  let perm : Array[Int] = Array::make(n, 0)
  for i in 0..<n {
    perm[i] = i
  }
  let c : Array[Int] = Array::make(n, 0)
  // Evaluate the identity permutation as the initial best.
  let mut best = 0.0
  for k in 0..<n {
    best = best + cost[k][perm[k]]
  }
  // Iterative Heap's algorithm: generates each of the n! permutations exactly
  // once by swapping two elements per step.
  let mut i = 0
  while i < n {
    if c[i] < i {
      let a = if i % 2 == 0 { 0 } else { c[i] }
      let tmp = perm[a]
      perm[a] = perm[i]
      perm[i] = tmp
      let mut s = 0.0
      for k in 0..<n {
        s = s + cost[k][perm[k]]
      }
      if s < best {
        best = s
      }
      c[i] = c[i] + 1
      i = 0
    } else {
      c[i] = 0
      i = i + 1
    }
  }
  best
}

///|
test "kuhn_munkres 4x4 matches brute-force optimum" {
  // 4x4 integer-valued cost matrix. With n = 4 there are 4! = 24 permutations,
  // which `brute_force_min_assignment` enumerates exhaustively to produce the
  // reference minimum. The Hungarian algorithm must return the same total.
  let cost : Array[Array[Double]] = [
    [4.0, 1.0, 3.0, 2.0],
    [0.0, 5.0, 3.0, 1.0],
    [3.0, 2.0, 2.0, 0.0],
    [4.0, 1.0, 2.0, 3.0],
  ]
  let expected = brute_force_min_assignment(cost)
  let result = kuhn_munkres(cost)
  match result {
    Ok((_assignment, total)) => {
      // Compare with a small epsilon to tolerate floating-point drift from
      // the potential-update steps inside the Hungarian algorithm.
      let diff = total - expected
      let abs_diff = if diff < 0.0 { -diff } else { diff }
      inspect(abs_diff < 1.0e-9, content="true")
    }
    Err(_) => inspect(false, content="true")
  }
}

///|
/// whitebox: n = 0 空矩阵 —— 触发 `if n == 0 { return Ok(([], 0.0)) }` 早退分支。
/// 覆盖 `kuhn_munkres.mbt` 开头的空输入短路径,完全跳过 O(n^3) 主循环与
/// 标签初始化。此外 Ok 分支解构后 `assignment.length() == 0 && total == 0.0`
/// 明确该边界契约: 0x0 问题的最优总代价为 0。
test "whitebox: kuhn_munkres empty matrix returns Ok empty assignment" {
  let cost : Array[Array[Double]] = []
  let result = kuhn_munkres(cost)
  match result {
    Ok((assignment, total)) => {
      inspect(assignment.length(), content="0")
      inspect(total, content="0")
    }
    Err(_) => inspect(false, content="true")
  }
}
