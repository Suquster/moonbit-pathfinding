// Blackbox tests for connected_components.

///|
test "single connected component" {
  let nodes = [0, 1, 2]
  let adj : Array[Array[Int]] = [[1], [0, 2], [1]]
  let comps = connected_components(nodes, fn(n) { adj[n] })
  inspect(comps.length(), content="1")
}

///|
test "two connected components" {
  let nodes = [0, 1, 2, 3]
  let adj : Array[Array[Int]] = [[1], [0], [3], [2]]
  let comps = connected_components(nodes, fn(n) { adj[n] })
  inspect(comps.length(), content="2")
}

///|
test "all isolated nodes form n components" {
  let nodes = [0, 1, 2]
  let adj : Array[Array[Int]] = [[], [], []]
  let comps = connected_components(nodes, fn(n) { adj[n] })
  inspect(comps.length(), content="3")
}

///|
/// whitebox: 单节点图 —— BFS 主 while 只执行 1 轮,pop start=0 后 successors(0) 为空,
/// 内层 for 不进入循环体,component 收敛为 [0]。验证 connected_components 对最小非空图
/// 的边界契约: 返回恰好 1 个分量、分量内含唯一节点。
/// 覆盖 `connected_components.mbt` 中 successors 返回空 Array 时 for-in 零次迭代的冷路径。
test "whitebox: connected_components single node graph returns one component" {
  let nodes = [0]
  let adj : Array[Array[Int]] = [[]]
  let comps = connected_components(nodes, fn(n) { adj[n] })
  inspect(comps.length(), content="1")
  inspect(comps[0].length(), content="1")
  inspect(comps[0][0], content="0")
}
