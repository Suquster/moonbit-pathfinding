// 逐步执行引擎（Stepper）冒烟单元测试（任务 24.1）。
//
// 这里仅做少量「示例 + 边界」单元校验，确认五种算法档在 successor function
// 上正确产出逐步轨迹、终止路径与可达标志。完整的属性测试（Property 1
// 结构不变量、Property 4 终止路径合法/可达一致）由任务 24.2 / 24.3 承载。

///|
/// 构造邻接表 successor function：`adj[n]` 为节点 n 的 `(邻居, 边权)` 列表。
fn make_succ(adj : Array[Array[(Int, Int)]]) -> (Int) -> Array[(Int, Int)] {
  fn(n) { if n >= 0 && n < adj.length() { adj[n] } else { [] } }
}

///|
/// 恒零启发式（BFS/DFS/Dijkstra 用）。
fn zero_h(_n : Int) -> Int {
  0
}

///|
test "trace_search BFS 在链图上找到最短路" {
  // 0 -> 1 -> 2 -> 3
  let adj = [[(1, 1)], [(2, 1)], [(3, 1)], []]
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::BFS,
    0,
    3,
    make_succ(adj),
    zero_h,
  )
  assert_eq(trace.reachable, true)
  assert_eq(trace.final_path, Some([0, 1, 2, 3]))
  assert_eq(trace.algo, @playground.PlaygroundAlgo::BFS)
  // 最后一帧必须终止。
  let last = trace.steps[trace.steps.length() - 1]
  assert_eq(last.done, true)
  assert_eq(last.found, true)
}

///|
test "trace_search Dijkstra 选取更低权重路径" {
  // 0->1 权 10；0->2->1 权 1+1=2。到 1 的最短为经 2。
  let adj = [[(1, 10), (2, 1)], [], [(1, 1)]]
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::Dijkstra,
    0,
    1,
    make_succ(adj),
    zero_h,
  )
  assert_eq(trace.reachable, true)
  assert_eq(trace.final_path, Some([0, 2, 1]))
}

///|
test "trace_search A* 借助启发式仍返回最短路" {
  // 网格直链 0->1->2->3，单位权；启发式给目标距离的粗估。
  let adj = [[(1, 1)], [(2, 1)], [(3, 1)], []]
  let h = fn(n : Int) -> Int { (3 - n).abs() }
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::AStar,
    0,
    3,
    make_succ(adj),
    h,
  )
  assert_eq(trace.reachable, true)
  assert_eq(trace.final_path, Some([0, 1, 2, 3]))
}

///|
test "trace_search DFS 返回一条合法路径" {
  let adj = [[(1, 1), (2, 1)], [(3, 1)], [(3, 1)], []]
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::DFS,
    0,
    3,
    make_succ(adj),
    zero_h,
  )
  assert_eq(trace.reachable, true)
  // DFS 路径不保证最短，但首=起点、末=终点且每相邻对为边。
  let path = trace.final_path.unwrap()
  assert_eq(path[0], 0)
  assert_eq(path[path.length() - 1], 3)
}

///|
test "trace_search JPS（贪心）在带启发式时找到合法路径" {
  let adj = [[(1, 1), (2, 1)], [(3, 1)], [(3, 1)], []]
  let h = fn(n : Int) -> Int { (3 - n).abs() }
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::JPS,
    0,
    3,
    make_succ(adj),
    h,
  )
  assert_eq(trace.reachable, true)
  let path = trace.final_path.unwrap()
  assert_eq(path[0], 0)
  assert_eq(path[path.length() - 1], 3)
}

///|
test "trace_search 目标不可达时 final_path 为 None 且末帧终止" {
  // 节点 3 无任何入边，从 0 不可达。
  let adj = [[(1, 1)], [(2, 1)], [], []]
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::BFS,
    0,
    3,
    make_succ(adj),
    zero_h,
  )
  assert_eq(trace.reachable, false)
  assert_eq(trace.final_path, None)
  let last = trace.steps[trace.steps.length() - 1]
  assert_eq(last.done, true)
  assert_eq(last.found, false)
}

///|
test "trace_search 起点即终点时返回单元素路径" {
  let adj = [[(1, 1)], []]
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::Dijkstra,
    0,
    0,
    make_succ(adj),
    zero_h,
  )
  assert_eq(trace.reachable, true)
  assert_eq(trace.final_path, Some([0]))
  assert_eq(trace.steps.length(), 1)
}

///|
test "trace_search visited 集合沿帧序单调不减" {
  let adj = [[(1, 1), (2, 1)], [(3, 1)], [(3, 1)], [(4, 1)], []]
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::BFS,
    0,
    4,
    make_succ(adj),
    zero_h,
  )
  // 逐帧检查：前一帧 visited 是后一帧 visited 的前缀（追加式、单调不减）。
  let steps = trace.steps
  for i in 1..<steps.length() {
    let prev = steps[i - 1].visited
    let curr = steps[i].visited
    assert_eq(curr.length() >= prev.length(), true)
    for j in 0..<prev.length() {
      assert_eq(curr[j], prev[j])
    }
  }
}
