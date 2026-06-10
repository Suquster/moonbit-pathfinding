// Blackbox tests for Bellman-Ford.

///|
test "bellman_ford computes shortest distances with negative edges" {
  // 0 --(4)--> 1 --(-2)--> 2  (net cost 2)
  // 0 --(5)----------->   2  (cost 5)
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 4), (1, 2, -2), (0, 2, 5)]
  let result = bellman_ford(nodes, edges, 0)
  match result {
    Ok(dist) => assert_true(dist.get(2) == Some(2))
    Err(_) => inspect(false, content="true")
  }
}

///|
test "bellman_ford detects negative cycle" {
  // 0 -> 1 -> 2 -> 0 with total cycle weight -1
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, 1), (2, 0, -3)]
  let result = bellman_ford(nodes, edges, 0)
  match result {
    Err(NegativeCycle) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "bellman_ford source distance is zero" {
  let nodes = [0, 1]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 7)]
  let result = bellman_ford(nodes, edges, 0)
  match result {
    Ok(dist) => assert_true(dist.get(0) == Some(0))
    Err(_) => inspect(false, content="true")
  }
}

///|
/// whitebox: 不可达节点在结果 Map 中应为 None(不在字典中)。
/// 覆盖 `bellman_ford.mbt` 内 `match dist.get(u) { ... None => () }` 冷分支 ——
/// 当某条边的 u 从未被放松到时,整条边会被跳过,目标节点保持不在 dist 中。
test "whitebox: bellman_ford returns None for unreachable nodes" {
  // 图中 2 是孤岛 —— 从 0 出发没有任何路径能到达 2。
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (2, 3, 1)]
  let result = bellman_ford(nodes, edges, 0)
  match result {
    Ok(dist) => {
      // 源点距离为 0,1 可达,2 / 3 不可达(None)。
      assert_true(dist.get(0) == Some(0))
      assert_true(dist.get(1) == Some(1))
      assert_true(dist.get(2) is None)
      assert_true(dist.get(3) is None)
    }
    Err(_) => inspect(false, content="true")
  }
}
