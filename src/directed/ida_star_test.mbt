// Blackbox tests for IDA*.

///|
test "ida_star finds goal with zero heuristic equals dijkstra cost" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 10), (2, 1)],
    [(3, 10)],
    [(3, 1)],
    [],
  ]
  let ia = ida_star(0, fn(n) { adj[n] }, fn(_n) { 0 }, fn(n) { n == 3 })
  let d = dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match (ia, d) {
    (Some((_pa, ca)), Some((_pd, cd))) => inspect(ca == cd, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "ida_star start equals goal" {
  let adj : Array[Array[(Int, Int)]] = [[(1, 5)]]
  let ia = ida_star(0, fn(n) { adj[n] }, fn(_n) { 0 }, fn(n) { n == 0 })
  match ia {
    Some((_p, c)) => inspect(c, content="0")
    None => inspect(false, content="true")
  }
}

///|
test "ida_star returns None when goal unreachable" {
  // Graph:  0 -> 1   (node 2 is isolated, thus unreachable as a goal)
  // IDA* must terminate (not loop forever) and report None when the search
  // space is exhausted without finding any node satisfying the goal predicate.
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [], []]
  let result = ida_star(0, fn(n) { adj[n] }, fn(_n) { 0 }, fn(n) { n == 2 })
  assert_true(result is None)
}

///|
/// whitebox: 强制所有后继被 on_path 跳过 -> `min_exceeded` 保持 inf -> 返回 None。
/// 构造自环 0 <-> 1,目标 2 不存在。第二轮迭代时,bound 被上一轮抬升到 1,
/// inner search(1, 1, 1) 时唯一后继 0 已在 path=[0,1] 中,被 `on_path` 分支 `continue`
/// 跳过,导致 `min_exceeded` 从初始 `inf` 未被更新,返回 `Some(inf)`。
/// 主循环 `match` 到 `Some(t)` 后命中 `if t == inf { return None }` 冷路径。
/// 同时覆盖 `ida_star.mbt` 中 `on_path` 循环提前 break 与 `continue` 两条冷边。
test "whitebox: ida_star exhausts search via on_path skip and returns None" {
  // 0 <-> 1 的两节点自环;goal = 2 不可达。
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(0, 1)], []]
  let result = ida_star(0, fn(n) { adj[n] }, fn(_n) { 0 }, fn(n) { n == 2 })
  assert_true(result is None)
}
