// 黑盒测试：覆盖率审计收口（INFRA 第七十八批）——
// 代价搜索的惰性删除：同一节点多次入堆，陈旧条目弹出即跳过。

///|
test "trace_search：Dijkstra 陈旧堆条目惰性跳过" {
  // s(0)→a(1) 代价 1；s→b(2) 代价 5；a→b 代价 1：b 两次入堆。
  // 目标设为不可达节点，迫使搜索耗尽堆并弹出 b 的陈旧条目。
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    match n {
      0 => [(1, 1), (2, 5)]
      1 => [(2, 1)]
      _ => []
    }
  }
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::Dijkstra,
    0,
    99,
    succ,
    fn(_n) { 0 },
  )
  assert_false(trace.reachable)
  assert_eq(trace.steps[trace.steps.length() - 1].visited.length(), 3)
}

///|
test "trace_search：AStar 陈旧堆条目惰性跳过" {
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    match n {
      0 => [(1, 1), (2, 5)]
      1 => [(2, 1)]
      _ => []
    }
  }
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::AStar,
    0,
    99,
    succ,
    fn(_n) { 0 },
  )
  assert_false(trace.reachable)
}
