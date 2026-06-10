// Blackbox tests for bidirectional BFS.

///|
test "bidirectional_bfs finds path in chain" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let rev : Array[Array[Int]] = [[], [0], [1], [2]]
  let path = bidirectional_bfs(0, 3, fn(n) { adj[n] }, fn(n) { rev[n] })
  let ok = match path {
    Some(p) => p.length() >= 2 && p[0] == 0 && p[p.length() - 1] == 3
    None => false
  }
  inspect(ok, content="true")
}

///|
test "bidirectional_bfs start equals goal" {
  let adj : Array[Array[Int]] = [[1]]
  let rev : Array[Array[Int]] = [[]]
  let path = bidirectional_bfs(0, 0, fn(n) { adj[n] }, fn(n) { rev[n] })
  match path {
    Some(p) => assert_true(p.length() == 1 && p[0] == 0)
    None => assert_true(false)
  }
}

///|
test "bidirectional_bfs unreachable" {
  let adj : Array[Array[Int]] = [[], [], []]
  let rev : Array[Array[Int]] = [[], [], []]
  let path = bidirectional_bfs(0, 2, fn(n) { adj[n] }, fn(n) { rev[n] })
  assert_true(path is None)
}

///|
/// whitebox: 触发 "forward 前沿大 -> 从 backward 扩展" 的 else 分支。
/// 第 1 轮 forward 从节点 0 扩展出 3 个后继 [1, 3, 4],fwd_queue 增长到 4、fwd_head=1,
/// 剩余 fwd_size=3;而 bwd_queue 仍为 [2]、bwd_size=1。此时 3 > 1,`fwd_size <= bwd_size`
/// 为假,进入 else 分支从 backward 扩展 predecessors(2) = [1]。节点 1 已在 fwd_visited 中,
/// 立刻命中 meeting。覆盖 `bidirectional_bfs.mbt` 中 else 子句整段冷路径(含
/// `if fwd_visited.contains(next) { meeting = Some(next); break }` 方向)。
test "whitebox: bidirectional_bfs expands backward when forward frontier larger" {
  // 0 -> 1, 0 -> 3, 0 -> 4         (forward 出度 = 3,前沿会膨胀)
  // 1 -> 2, 3 -> 2, 4 -> 2        (三条路都汇入 goal=2)
  // predecessors(2) = [1, 3, 4]
  let adj : Array[Array[Int]] = [[1, 3, 4], [2], [], [2], [2]]
  let rev : Array[Array[Int]] = [[], [0], [1, 3, 4], [0], [0]]
  let path = bidirectional_bfs(0, 2, fn(n) { adj[n] }, fn(n) { rev[n] })
  // 无论走哪条 meeting 点,结果都必须是从 0 到 2 且长度为 3 的合法路径。
  match path {
    Some(p) => {
      inspect(p.length(), content="3")
      inspect(p[0], content="0")
      inspect(p[2], content="2")
    }
    None => inspect(false, content="true")
  }
}
