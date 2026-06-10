// Blackbox tests for Tarjan SCC.

///|
test "tarjan_scc finds all components" {
  // 0 -> 1 -> 2 -> 0 is one SCC; 3 -> 4 -> 3 is another SCC; 5 alone.
  let nodes = [0, 1, 2, 3, 4, 5]
  let adj : Array[Array[Int]] = [[1], [2], [0], [4], [3], []]
  let sccs = tarjan_scc(nodes, fn(n) { adj[n] })
  inspect(sccs.length(), content="3")
}

///|
test "tarjan_scc empty graph" {
  let nodes : Array[Int] = []
  let adj : Array[Array[Int]] = []
  let sccs = tarjan_scc(nodes, fn(n) { adj[n] })
  inspect(sccs.length(), content="0")
}

///|
test "tarjan_scc DAG gives n singleton components" {
  let nodes = [0, 1, 2]
  let adj : Array[Array[Int]] = [[1], [2], []]
  let sccs = tarjan_scc(nodes, fn(n) { adj[n] })
  inspect(sccs.length(), content="3")
}

///|
/// whitebox: 单节点自环 (0 -> 0) 触发 `on_stack.get(w).or(false)` 为真分支。
/// DFS 访问 0 后,其邻居 w=0 已有 index_map,且 on_stack[0]=true,进入 else-if 分支
/// 读取 `lw = index_map[0]` 并与 `lowlink[0]` 比较 —— 这是纯无自环图里访问不到的冷路径。
/// 最终 pop 出一个包含自身的 component,证明 "自环节点是 SCC 而非 singleton"。
/// 覆盖 `tarjan_scc.mbt` 中 `on_stack.get(w).or(false)` 命中 true 的冷边。
test "whitebox: tarjan_scc single node self-loop forms one SCC" {
  // 单节点 0 + 自环 0 -> 0
  let nodes = [0]
  let adj : Array[Array[Int]] = [[0]]
  let sccs = tarjan_scc(nodes, fn(n) { adj[n] })
  // 刚好 1 个 SCC,且成员就是 [0]。
  inspect(sccs.length(), content="1")
  inspect(sccs[0].length(), content="1")
  inspect(sccs[0][0], content="0")
}
