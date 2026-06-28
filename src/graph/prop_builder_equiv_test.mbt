// Feature: championship-v1-upgrade, Property 19: 构造器图与等价图查询结果相同
//
// 本文件以属性测试（property-based test）校验：经链式 `GraphBuilder` 物化的
// 图，在交给既有算法查询时，与「以既有方式构建的等价图」产出逐项相同的结果
// （design.md §「Property 19」/ Requirement 12.7）。
//
//   * Requirement 12.7：物化由 GraphBuilder 构建的图并交给既有算法查询，应
//     产出与「以既有方式构建的等价图」相同的查询结果；等价图定义为「具有相同
//     节点集合与相同带权边集合」的图，相同定义为「查询结果逐项相等」。
//
// 差分对拍设计（测试期依赖 @directed，仅作用于 `for "test"`，不进入产物）：
//   * 方式 (a)「构造器图」：用 `GraphBuilder::add_node/add_edge` 渐进累积后
//     `build().successors()`，得到供算法消费的 successor 闭包。
//   * 方式 (b)「既有等价图」：从同一条（去重后）带权边集合直接构造 `Map` 邻接
//     表，并以之合成等价的 successor 闭包——代表不借助 GraphBuilder 的传统构图。
//   两条闭包描述同一逻辑图（相同节点集与相同带权边集），故对同一算法、同一
//   (源, 目标) 查询，结果应逐项相等。
//
// 算法选用 `@directed.dijkstra`（非负权单源最短路）：其入参形态为
//   dijkstra(source, (N) -> Array[(N, W)], (N) -> Bool) -> (Array[N], W)?
// 恰与物化图暴露的 successor 闭包契合。比较口径取「可达性 + 路径代价」逐项
// 相等：代价（与可达性）对邻居枚举顺序不敏感，是等价图差分对拍的稳健判据
// （两条闭包的邻居枚举顺序可能因各自 Map 遍历序而不同，但最短路代价不变）。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`，
// 迭代次数取 128（≥100 基线）。

///|
/// 单个随机用例：节点全集为 `0..k-1`（共 `k` 个 Int 节点），外加一段非负权
/// 有向边序列 `edges`（每个三元组为 `(源, 目标, 权重)`，权重 ≥ 0）。
///
/// 源/目标一律取自 `0..k-1`，保证两种构图方式都能成功描述同一逻辑图；
/// 权重非负以满足 Dijkstra 的适用前提。刻意注入重复 `(源, 目标)` 以检验
/// 「末次权重覆盖」在两条构图路径上的一致性（Requirement 12.3 + 12.7）。
struct P19Case {
  /// 节点个数；节点标识为 `0..k-1`。
  k : Int
  /// 非负权有向边序列，含刻意制造的重复 (源, 目标)。
  edges : Array[(Int, Int, Int)]
}

///|
/// 随机用例生成器：先定节点规模 `k ∈ [1, 6]`，再生成 `0..3k` 条非负权边。
///
/// 关键设计：
///   * 源/目标取自 `0..k-1`；权重取自 `0..30`（非负，契合 Dijkstra）。
///   * 每条边以 50% 概率追加一条「同 (源, 目标)、新权重」的重复边，制造
///     末次覆盖场景，检验两条构图路径对重复边处理一致。
///   * 允许空边序列（覆盖「仅孤立节点、无边」边界）。
fn p19_gen() -> @infra_pbt.Gen[P19Case] {
  @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_range(1, 6) // 节点数 1..6（闭区间）
    let edges : Array[(Int, Int, Int)] = []
    let m = rng.next_below(3 * k + 1) // 边条数 0..3k
    let mut i = 0
    while i < m {
      let u = rng.next_below(k) // 源 ∈ 0..k-1
      let v = rng.next_below(k) // 目标 ∈ 0..k-1
      let w = rng.next_below(31) // 权重 0..30（非负）
      edges.push((u, v, w))
      if rng.next_bool() {
        let w2 = rng.next_below(31)
        edges.push((u, v, w2)) // 同 (u, v) 重复，检验末次覆盖一致性
      }
      i = i + 1
    }
    P19Case::{ k, edges }
  })
}

///|
/// 方式 (b)「既有等价图」：从（去重后）带权边集合直接构造 `Map` 邻接表，并以
/// 之合成等价 successor 闭包——代表不借助 GraphBuilder 的传统构图方式。
///
/// 去重口径与 GraphBuilder 一致：以 `(源, 目标)` 为键、末次写入权重覆盖先前
/// 权重（Requirement 12.3），从而两条构图路径描述的是同一逻辑图。
fn p19_legacy_successors(
  k : Int,
  edges : Array[(Int, Int, Int)],
) -> (Int) -> Array[(Int, Int)] {
  // 1) 去重：(源, 目标) -> 末次权重，等价于 GraphBuilder 的边集语义。
  let dedup : Map[(Int, Int), Int] = Map([])
  for e in edges {
    let (u, v, w) = e
    dedup[(u, v)] = w
  }
  // 2) 物化为邻接表（无出边的节点缺省，查询时返回空数组）。
  let adj : Map[Int, Array[(Int, Int)]] = Map([])
  for key, w in dedup {
    let (u, v) = key
    match adj.get(u) {
      Some(out_edges) => out_edges.push((v, w))
      None => adj[u] = [(v, w)]
    }
  }
  // 节点 0..k-1 全集已由调用方界定；闭包对缺省源返回空数组，语义与
  // Graph::successors 对孤立节点的处理一致。
  let _ = k
  fn(node : Int) -> Array[(Int, Int)] {
    match adj.get(node) {
      Some(out_edges) => out_edges
      None => []
    }
  }
}

///|
/// 校验单个用例：分别用两种方式构图，对所有 (源, 目标) 节点对运行同一算法
/// （`@directed.dijkstra`），断言「可达性 + 路径代价」逐项相等。
///
/// 校验链路：
///   1. 方式 (a)：GraphBuilder 累积全部节点与边后 `build().successors()`。
///   2. 方式 (b)：从同一边集直接合成等价 successor 闭包。
///   3. 对每个 (s, t) ∈ {0..k-1}×{0..k-1} 运行 dijkstra，比较结果：
///      - 可达性一致：两者同为 None 或同为 Some；
///      - 路径代价一致：两者 Some 时，最短路代价相等。
fn p19_check(case : P19Case) -> Bool {
  // 1) 方式 (a)：构造器图。
  let builder : GraphBuilder[Int, Int] = GraphBuilder::new()
  for n in 0..<case.k {
    builder.add_node(n) |> ignore
  }
  for e in case.edges {
    let (u, v, w) = e
    builder.add_edge(u, v, w) |> ignore
  }
  let graph = match builder.build() {
    Ok(g) => g
    Err(_) => return false // 边均引用已声明节点，build 不应失败
  }
  let succ_a = graph.successors()
  // 2) 方式 (b)：既有等价图。
  let succ_b = p19_legacy_successors(case.k, case.edges)
  // 3) 对所有 (源, 目标) 节点对差分对拍。
  for s in 0..<case.k {
    for t in 0..<case.k {
      let goal = fn(n : Int) -> Bool { n == t }
      let ra = @directed.dijkstra(s, succ_a, goal)
      let rb = @directed.dijkstra(s, succ_b, goal)
      match (ra, rb) {
        // 可达：比较路径代价逐项相等（代价对邻居枚举顺序不敏感）。
        (Some((_, ca)), Some((_, cb))) => if ca != cb { return false }
        // 不可达：两者必须一致地不可达。
        (None, None) => ()
        // 可达性不一致：等价性被破坏。
        _ => return false
      }
    }
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 19: 构造器图与等价图查询结果相同
///
/// 对任意逻辑图（节点 0..k-1、非负权边集），经 `GraphBuilder` 物化的图与以
/// 既有方式构建的等价图（相同节点集与相同带权边集），在同一算法
/// （`@directed.dijkstra`）查询下，可达性与路径代价逐项相等。
///
/// 另以确定性锚点固定一个示例：三角图 0->1(2)、1->2(3)、0->2(10)，从 0 到 2
/// 两种构图均应得最短代价 5（经 0->1->2），且可达。
///
/// **Validates: Requirements 12.7**
test "Feature: championship-v1-upgrade, Property 19: builder graph equals equivalent graph under same query" {
  // 锚点：构造器图与等价图在确定性示例上的结果一致。
  let anchor : GraphBuilder[Int, Int] = GraphBuilder::new()
  anchor.add_node(0) |> ignore
  anchor.add_node(1) |> ignore
  anchor.add_node(2) |> ignore
  anchor.add_edge(0, 1, 2) |> ignore
  anchor.add_edge(1, 2, 3) |> ignore
  anchor.add_edge(0, 2, 10) |> ignore
  match anchor.build() {
    Ok(g) => {
      let succ_a = g.successors()
      let succ_b = p19_legacy_successors(3, [(0, 1, 2), (1, 2, 3), (0, 2, 10)])
      let goal = fn(n : Int) -> Bool { n == 2 }
      let ra = @directed.dijkstra(0, succ_a, goal)
      let rb = @directed.dijkstra(0, succ_b, goal)
      match (ra, rb) {
        (Some((_, ca)), Some((_, cb))) => {
          assert_eq(ca, 5) // 0->1->2 = 5，优于直达 0->2 = 10
          assert_eq(cb, 5)
        }
        _ => assert_true(false) // 锚点：两者都应可达
      }
    }
    Err(_) => assert_true(false) // 锚点：build 不应失败
  }

  // 属性：随机逻辑图上，两种构图方式的查询结果恒逐项相等。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(p19_gen(), p19_check, iters=128)
  assert_true(ok)
}
