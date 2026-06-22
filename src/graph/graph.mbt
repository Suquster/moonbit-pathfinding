// graph.mbt —— 物化图 `Graph[N, W]` 与 successor 物化。
//
// 设计依据（design.md §「方向 4 · 4.2 GraphBuilder」/ Requirement 12）：
//   `Graph[N, W]` 是 `GraphBuilder` 物化（`build`）后的不可变产物，以邻接表
//   存储有向带权边，并向既有算法暴露统一的 successor function 范式
//   （`fn(N) -> Array[(N, W)]`，承袭 design.md「设计哲学」）。本文件只提供
//   图的容器与查询能力（successor 物化 / 规模查询）；链式构造逻辑由同包的
//   `builder.mbt`（任务 2.2）填充——二者同包，故可直接以结构体字面量构造。
//
// 关键不变量：
//   * Requirement 12.1：以邻接表（`Map[N, Array[(N, W)]]`）存储，支持大规模
//     节点 / 边的容量目标；查询为哈希直达，successor 物化为 O(1) 闭包构造。
//   * Requirement 12.7：物化图交给既有算法的查询结果，与「以既有方式构建的
//     等价图」逐项相等——其根基即 `successors` 返回的邻居集合忠实反映 `adj`。
//   * Requirement 22.6：以精确的结构体 / 数组 / 映射表示图，不用字符串模拟。

///|
/// 物化后的不可变图：以邻接表存储有向带权边，并向既有算法暴露 successor。
///
/// 字段语义：
///
/// - `nodes`：图中全部节点，按声明顺序排列（`GraphBuilder` 物化时填充）。
///   `node_count()` 即返回其长度；它界定了图的节点全集（含孤立节点）。
/// - `adj`：邻接表，键为源节点，值为该源节点的出边数组 `(目标, 权重)`。
///   无出边的节点可以不在键集合中出现——`successors` 对此返回空数组，从而
///   与「该节点存在但无出边」语义一致。
///
/// 设计取舍：`Graph` 一经物化即视为只读视图，所有查询方法均不修改自身状态；
/// 这使其可被多个算法安全共享，亦便于属性测试中对「构造器图 ≡ 等价图」做
/// 交叉对拍（Requirement 12.7）。
pub struct Graph[N, W] {
  /// 图中全部节点（按声明顺序），界定节点全集，含孤立节点。
  nodes : Array[N]
  /// 邻接表：源节点 -> 其出边 `(目标, 权重)` 数组；无出边的源可缺省。
  adj : Map[N, Array[(N, W)]]
}

///|
/// 物化为 successor function：返回一个闭包，给定节点即返回其出边邻居数组
/// `Array[(N, W)]`。
///
/// 行为保证：
///
/// - 节点存在出边时，返回 `adj` 中登记的出边数组（顺序与登记顺序一致）。
/// - 节点无出边（或不在 `adj` 键集合中，例如孤立节点）时，返回 **空数组**
///   而非报错，契合 successor function 范式「无邻居即空序列」的约定。
/// - 闭包仅捕获 `adj` 的引用、按需哈希查表，构造本身为 O(1)；单次查询为
///   均摊 O(1) 哈希定位（Requirement 12.1）。
///
/// 该闭包形态与既有算法（如 `@directed.dijkstra` 等）所需的 `(N) -> Array[(N, W)]`
/// 入参完全契合，从而让物化图无缝接入既有算法（Requirement 12.7）。
pub fn[N : Eq + Hash, W] Graph::successors(
  self : Graph[N, W],
) -> (N) -> Array[(N, W)] {
  let adj = self.adj
  fn(node : N) -> Array[(N, W)] {
    match adj.get(node) {
      Some(edges) => edges
      None => []
    }
  }
}

///|
/// 返回图中节点总数（含孤立节点），即 `nodes` 的长度。
///
/// 该计数以节点全集为准，不依赖 `adj` 是否为某节点登记了出边；因此孤立节点
/// （无任何出边）同样计入。复杂度 O(1)。
pub fn[N : Eq + Hash, W] Graph::node_count(self : Graph[N, W]) -> Int {
  self.nodes.length()
}

///|
/// 返回图中有向边总数，即邻接表中所有出边数组长度之和。
///
/// 实现按邻接表逐源累加出边条数（一次线性遍历，O(节点数 + 边数)）；不在循环
/// 内做任何字符串拼接，符合横切红线（Requirement 22.4）。每条 `(源, 目标)`
/// 边计为一条；由于 `GraphBuilder` 对重复 `(源, 目标)` 取末次权重覆盖
/// （Requirement 12.3），此处的计数与去重后的边集大小一致。
pub fn[N : Eq + Hash, W] Graph::edge_count(self : Graph[N, W]) -> Int {
  let mut total = 0
  for _node, edges in self.adj {
    total = total + edges.length()
  }
  total
}
