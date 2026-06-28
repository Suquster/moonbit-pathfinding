// Blackbox tests for Edmonds-Karp maximum flow.

///|
test "edmonds_karp textbook 4-node example" {
  // s=0, t=3
  // 0->1 cap 3, 0->2 cap 2, 1->2 cap 1, 1->3 cap 2, 2->3 cap 3
  //
  // Augmenting paths found by BFS:
  //   0->1->3  bottleneck = 2
  //   0->2->3  bottleneck = 2
  //   0->1->2->3  bottleneck = 1  (uses remaining 0->1, 1->2, 2->3)
  // Max flow = 2 + 2 + 1 = 5.
  // Verified by min-cut: S={0} -> cut = cap(0,1) + cap(0,2) = 3 + 2 = 5.
  let nodes = [0, 1, 2, 3]
  let cap : Map[(Int, Int), Int] = Map([])
  cap[(0, 1)] = 3
  cap[(0, 2)] = 2
  cap[(1, 2)] = 1
  cap[(1, 3)] = 2
  cap[(2, 3)] = 3
  let flow = edmonds_karp(nodes, cap, 0, 3)
  inspect(flow, content="5")
}

///|
test "edmonds_karp disconnected graph" {
  let nodes = [0, 1]
  let cap : Map[(Int, Int), Int] = Map([])
  let flow = edmonds_karp(nodes, cap, 0, 1)
  inspect(flow, content="0")
}

///|
test "edmonds_karp CLRS 6-node multi-path network" {
  // Classic CLRS Figure 26.1(b) maximum-flow network with multiple
  // augmenting paths.  Nodes: s=0, v1=1, v2=2, v3=3, v4=4, t=5.
  //
  //   Edges (capacity):
  //     0->1 : 16   0->2 : 13
  //     1->2 : 10   2->1 :  4
  //     1->3 : 12   3->2 :  9
  //     2->4 : 14   4->3 :  7
  //     3->5 : 20   4->5 :  4
  //
  // Min-cut S = {0, 1, 2, 4}, T = {3, 5}:
  //   cut edges = {1->3 (12), 4->3 (7), 4->5 (4)}
  //   capacity  = 12 + 7 + 4 = 23.
  // Therefore max flow = 23.
  let nodes = [0, 1, 2, 3, 4, 5]
  let cap : Map[(Int, Int), Int] = Map([])
  cap[(0, 1)] = 16
  cap[(0, 2)] = 13
  cap[(1, 2)] = 10
  cap[(2, 1)] = 4
  cap[(1, 3)] = 12
  cap[(3, 2)] = 9
  cap[(2, 4)] = 14
  cap[(4, 3)] = 7
  cap[(3, 5)] = 20
  cap[(4, 5)] = 4
  let flow = edmonds_karp(nodes, cap, 0, 5)
  inspect(flow, content="23")
}

///|
/// whitebox: source == sink —— BFS 从 source 出发,visited[source]=true 已被置位;
/// 遍历 v in nodes 时 sink(== source) 立刻命中 `if visited.contains(v) { continue }` 冷分支,
/// 不会有任何 parent 指针被写入,found 保持 false,外层 while 通过 `!(found) { break }` 退出,
/// 最终返回 `total_flow = 0`。覆盖 `edmonds_karp.mbt` 中 "源汇同点" 的边界路径。
test "whitebox: edmonds_karp source equals sink returns zero flow" {
  // 3 个节点带容量;source 和 sink 都是 0。
  let nodes = [0, 1, 2]
  let cap : Map[(Int, Int), Int] = Map([])
  cap[(0, 1)] = 10
  cap[(1, 2)] = 10
  cap[(2, 0)] = 10
  let flow = edmonds_karp(nodes, cap, 0, 0)
  inspect(flow, content="0")
}
