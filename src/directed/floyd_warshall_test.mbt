// Blackbox tests for Floyd-Warshall.

///|
test "floyd_warshall computes all pairs on small chain" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, 2), (2, 3, 3)]
  let dist = floyd_warshall(nodes, edges)
  assert_true(dist.get((0, 3)) == Some(6))
  assert_true(dist.get((1, 3)) == Some(5))
  assert_true(dist.get((2, 2)) == Some(0))
}

///|
test "floyd_warshall returns infinity for unreachable pairs" {
  let nodes = [0, 1]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 5)]
  let dist = floyd_warshall(nodes, edges)
  let inf : Int = 2147483647
  assert_true(dist.get((1, 0)) == Some(2147483647))
  assert_true(dist.get((0, 1)) == Some(5))
  ignore(inf)
}

///|
test "floyd_warshall matches pairwise dijkstra on 5-node graph" {
  // 5-node directed graph with multiple paths and a cycle (4 -> 0).
  //   0 --(2)--> 1 --(1)--> 2 --(3)--> 3 --(1)--> 4 --(6)--> 0
  //   0 --(5)--> 2
  //   1 --(7)--> 3
  //   2 --(10)-> 4
  // Validates Requirements 1.5 (all-pairs) and 7.3 (cross-validation).
  let nodes = [0, 1, 2, 3, 4]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (0, 2, 5),
    (1, 2, 1),
    (1, 3, 7),
    (2, 3, 3),
    (2, 4, 10),
    (3, 4, 1),
    (4, 0, 6),
  ]
  // Build adjacency list from the same edge list so Dijkstra and
  // Floyd-Warshall operate on the exact same graph.
  let adj : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let fw = floyd_warshall(nodes, edges)
  let inf : Int = 2147483647
  // For every ordered pair (u, v) the Floyd-Warshall distance must equal
  // the cost returned by a single-pair Dijkstra call (infinity when
  // unreachable).
  let mismatches : Array[(Int, Int, Int, Int)] = []
  for u in nodes {
    for v in nodes {
      let fw_val = fw.get((u, v)).unwrap()
      let dj_val = match dijkstra(u, fn(n) { adj[n] }, fn(n) { n == v }) {
        Some((_, cost)) => cost
        None => inf
      }
      if fw_val != dj_val {
        mismatches.push((u, v, fw_val, dj_val))
      }
    }
  }
  inspect(mismatches.length(), content="0")
}

///|
/// whitebox: k 作为中继节点实际改善距离。
/// 初始 dist[(0,2)] = inf,只有通过 k=1 中继才能从 inf 被松弛为 (1+2)=3。
/// 覆盖 `floyd_warshall.mbt` 三重循环中 `dik != inf && dkj != inf` 为真且
/// `candidate < dij` 成立的核心松弛分支。
test "whitebox: floyd_warshall relaxes via intermediate k from infinity" {
  // 0 --(1)--> 1 --(2)--> 2, 但没有 (0,2) 直接边。
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, 2)]
  let dist = floyd_warshall(nodes, edges)
  // 通过 k=1 中继后,(0,2) 应从 inf 改善为 3。
  assert_true(dist.get((0, 2)) == Some(3))
  assert_true(dist.get((0, 1)) == Some(1))
  assert_true(dist.get((1, 2)) == Some(2))
  // 反向 (2,0) 没有边,保持 infinity(Int::max_value = 2147483647)。
  assert_true(dist.get((2, 0)) == Some(2147483647))
}
