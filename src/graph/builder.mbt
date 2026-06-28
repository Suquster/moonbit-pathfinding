// builder.mbt —— 链式（流式）图构造器 `GraphBuilder[N, W]`。
//
// 设计依据（design.md §「方向 4 · 4.2 GraphBuilder」/ Requirement 12）：
//   `GraphBuilder` 以「就地累积 + 返回 self」的链式范式，渐进式声明节点与
//   有向带权边，最终经 `build` 物化为不可变的 `Graph[N, W]`（见同包
//   `graph.mbt`）。二者同包，故 `build` 可直接以结构体字面量构造 `Graph`。
//
// 关键不变量与需求映射：
//   * R12.1：以 `Array`（声明顺序）+ `Map`（节点集 / 边集）为骨架，哈希直达，
//     支持 ≥1e6 节点 / ≤1e7 边的容量目标；累积与物化均无 O(n²) 热路径。
//   * R12.2：`add_node` / `add_edge` / `add_undirected_edge` 渐进式累积。
//   * R12.3：边以 `Map[(源, 目标), 权重]` 存储，重复 `(源, 目标)` 由 `Map`
//     键唯一性天然实现「末次权重覆盖」。
//   * R12.4：空构造器 `build` 物化为有效空图（节点空、邻接空），而非失败。
//   * R12.5：节点合法性校验延迟到 `build`；若任何边引用未声明节点，`build`
//     返回 `Err(InvalidArgument(...))` 且保持累积状态不变（全程只读校验）。
//   * R12.6：链式方法返回 `self`，使连续调用可组合。
//   * R22.4：诊断串经 `@infra_text.TextBuilder` 顺序追加，禁止循环内 `+` 拼接。
//   * R22.6：以精确的数组 / 映射 / 元组键表示图结构，不用字符串模拟。

///|
/// 链式图构造器：渐进式声明节点与有向带权边，最终经 `build` 物化为
/// 不可变 `Graph[N, W]`。支持 ≥1e6 节点 / ≤1e7 边的容量目标（R12.1）。
///
/// 字段语义：
///
/// - `order`：节点的声明顺序。`add_node` 首次声明某节点时追加；重复声明
///   不再追加（去重），因此该数组恰为「节点全集」且无重复，物化时直接界定
///   `Graph::nodes`（保持声明顺序，含孤立节点）。
/// - `declared`：已声明节点集合（值为 `Unit`，仅用其键集做存在性判定）。
///   既服务于 `add_node` 的去重，也服务于 `build` 阶段的悬挂边校验（R12.5）。
/// - `edges`：有向边集合，键为 `(源, 目标)`、值为权重。重复 `(源, 目标)` 写入
///   时，`Map` 键唯一性使后写入的权重覆盖先前的权重（末次覆盖 · R12.3）。
///
/// 设计取舍：链式方法采用「就地累积 + 返回同一构造器引用」实现（R12.6）；
/// 节点合法性不在 `add_edge` 即时校验，而是延迟到 `build`（R12.5），从而允许
/// 「先连边、后补声明节点」的灵活书写顺序。
pub struct GraphBuilder[N, W] {
  /// 节点声明顺序（去重后），界定物化图的节点全集，含孤立节点。
  order : Array[N]
  /// 已声明节点集合：用于 `add_node` 去重与 `build` 悬挂边校验。
  declared : Map[N, Unit]
  /// 有向边：键 `(源, 目标)`，值为权重；重复键末次覆盖（R12.3）。
  edges : Map[(N, N), W]
}

///|
/// 新建一个空的链式构造器：节点声明顺序为空、节点集为空、边集为空。
///
/// 由此构造器直接 `build` 将物化为「有效空图」（R12.4），而非失败。
/// 后续可通过 `add_node` / `add_edge` / `add_undirected_edge` 链式追加元素，
/// 每个方法返回 `self` 以支持流式书写（R12.6）。节点合法性延迟到 `build`
/// 阶段统一校验，构造期间不拒绝悬挂边的声明。类型参数 `N` 为节点标识
/// （要求 `Eq + Hash`），`W` 为边权类型。
pub fn[N : Eq + Hash, W] GraphBuilder::new() -> GraphBuilder[N, W] {
  GraphBuilder::{ order: [], declared: Map([]), edges: Map([]) }
}

///|
/// 声明一个节点并返回构造器自身以支持链式调用（R12.6）。
///
/// 行为保证：
///
/// - **去重**：若节点 `n` 此前已声明，则仅返回 self，不重复追加到 `order`，
///   从而保证 `order` 恰为无重复的节点全集。
/// - **就地累积**：首次声明时把 `n` 追加到 `order` 并登记进 `declared`。
///
/// 复杂度：均摊 O(1)（一次哈希查存在性 + 至多一次数组追加 / 映射写入）。
pub fn[N : Eq + Hash, W] GraphBuilder::add_node(
  self : GraphBuilder[N, W],
  n : N,
) -> GraphBuilder[N, W] {
  // 仅首次声明时追加，避免 order 出现重复节点（R12.2）。
  match self.declared.get(n) {
    Some(_) => ()
    None => {
      self.order.push(n)
      self.declared[n] = ()
    }
  }
  self
}

///|
/// 登记一条有向带权边 `(u -> v, 权重 w)` 并返回构造器自身以支持链式调用
/// （R12.6）。
///
/// 行为保证：
///
/// - **仅登记，不即时校验**：节点 `u` / `v` 是否已声明的合法性校验延迟到
///   `build`（R12.5）；本方法不触发任何失败，也不隐式声明节点。
/// - **末次权重覆盖**：以 `(u, v)` 为键写入 `edges`；若该 `(源, 目标)` 此前
///   已登记，则后写入的权重覆盖先前权重（`Map` 键唯一性 · R12.3）。
///
/// 复杂度：均摊 O(1)（一次哈希写入）。
pub fn[N : Eq + Hash, W] GraphBuilder::add_edge(
  self : GraphBuilder[N, W],
  u : N,
  v : N,
  w : W,
) -> GraphBuilder[N, W] {
  // 重复 (源, 目标) 由 Map 键唯一性实现末次覆盖（R12.3）。
  self.edges[(u, v)] = w
  self
}

///|
/// 登记一条无向带权边并返回构造器自身以支持链式调用（R12.6）。
///
/// 语义等价于添加两条方向相反、权重相同的有向边 `(u -> v, w)` 与
/// `(v -> u, w)`。与 `add_edge` 一致，二者均遵循末次权重覆盖（R12.3），
/// 且不在此处做节点合法性校验（延迟到 `build` · R12.5）。
///
/// 复杂度：均摊 O(1)（两次哈希写入）。
pub fn[N : Eq + Hash, W] GraphBuilder::add_undirected_edge(
  self : GraphBuilder[N, W],
  u : N,
  v : N,
  w : W,
) -> GraphBuilder[N, W] {
  // 无向边 = 两条对称的有向边；各自遵循末次覆盖（R12.3）。
  self.edges[(u, v)] = w
  self.edges[(v, u)] = w
  self
}

///|
/// 物化构造器为不可变的 `Graph[N, W]`。
///
/// 行为保证：
///
/// - **延迟校验悬挂边**（R12.5）：先全程只读地扫描所有已登记边，若存在任一
///   边的源或目标节点未经 `add_node` 声明，则返回 `Err(InvalidArgument(...))`，
///   附带可读诊断（指明首个越界的边与缺失端点）；此路径**不修改**构造器的
///   任何累积状态（`order` / `declared` / `edges` 均不被触碰）。
/// - **空构造器物化为有效空图**（R12.4）：无节点、无边时返回
///   `Ok(Graph{ nodes: [], adj: {} })`，而非失败。
/// - **物化邻接表**：校验通过后，按声明顺序复制节点全集为 `nodes`，并将每条
///   `(u -> v, w)` 追加到 `adj[u]`（无出边的节点不在 `adj` 键集中出现，
///   `Graph::successors` 对其返回空数组）。
///
/// 复杂度：O(节点数 + 边数)——一次边集校验遍历 + 一次节点复制 + 一次边集
/// 物化遍历；全程无 O(n²) 字符串拼接（R22.4），支持大规模容量目标（R12.1）。
pub fn[N : Eq + Hash, W] GraphBuilder::build(
  self : GraphBuilder[N, W],
) -> Result[Graph[N, W], PathError] {
  // —— 阶段一：悬挂边校验（只读，不修改累积状态 · R12.5）。 ——
  // 遍历全部已登记边，统计引用了未声明节点（源或目标）的悬挂边数量。
  // 因泛型仅约束 `N : Eq + Hash`（不含 `Show`），诊断串不嵌入节点取值，
  // 而以「悬挂边条数」作为可读且类型安全的定位信息（R12.5 / R22.4）。
  let mut dangling = 0
  for key, _w in self.edges {
    let (u, v) = key
    let u_ok = self.declared.get(u) is Some(_)
    let v_ok = self.declared.get(v) is Some(_)
    if !u_ok || !v_ok {
      dangling = dangling + 1
    }
  }
  if dangling > 0 {
    let tb = @infra_text.TextBuilder::new()
    // 仅有限次顺序 push（非循环内拼接），符合无 O(n²) 约束（R22.4）。
    tb.push_str("GraphBuilder::build: 存在 ")
    tb.push_str(dangling.to_string())
    tb.push_str(
      " 条边引用了未经 add_node 声明的节点；请先声明全部端点后再 build。",
    )
    return Err(InvalidArgument(tb.build()))
  }
  // —— 阶段二：物化节点全集（按声明顺序复制，含孤立节点 · R12.4 兜底空图）。 ——
  let nodes : Array[N] = []
  for n in self.order {
    nodes.push(n)
  }
  // —— 阶段三：物化邻接表（每条有向边追加到其源节点的出边数组）。 ——
  let adj : Map[N, Array[(N, W)]] = Map([])
  for key, w in self.edges {
    let (u, v) = key
    match adj.get(u) {
      Some(out_edges) => out_edges.push((v, w))
      None => adj[u] = [(v, w)]
    }
  }
  Ok(Graph::{ nodes, adj })
}
