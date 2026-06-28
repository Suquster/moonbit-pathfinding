// Feature: championship-v1-upgrade, Property 18: 悬挂边物化失败且状态不变
//
// 本文件以属性测试（property-based test）校验链式图构造器 `GraphBuilder` 的
// 「悬挂边延迟校验」语义（design.md §「Property 18」/ Requirement 12.5）：
//
//   * Requirement 12.5：节点合法性校验延迟到 `build`；若任一边引用了未经
//     `add_node` 声明的节点（悬挂边），则 `build` 返回
//     `Err(InvalidArgument(...))`，且该失败路径为「全程只读校验」，绝不修改
//     构造器已累积的节点集（`order` / `declared`）与边集（`edges`）。
//
// 形式化属性：对任意「至少注入一条引用未声明节点的悬挂边」的构造器，
//   1. `build()` 返回 `Err(InvalidArgument(_))`（以 pattern match 断言）；
//   2. 「状态不变」之佐证甲（幂等性）：紧接着再次 `build()` 仍得到相同的
//      `Err(InvalidArgument(_))`——若首次失败破坏了累积状态，二次结果将不同；
//   3. 「状态不变」之佐证乙（可补全）：在同一构造器上补充声明此前缺失的全部
//      节点后再次 `build()`，应成功且物化图包含此前累积的全部边（去重 + 末次
//      权重）与全部节点。这只有在「首次失败未破坏 order/declared/edges」时方
//      可能成立，从而反证此前累积状态完好无损。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 128（≥100 基线）。

///|
/// 单个随机用例：已声明节点全集为 `0..k-1`（共 `k` 个 Int 节点），外加一段
/// 有向带权边添加序列 `edges`（每个三元组为 `(源, 目标, 权重)`），其中**保证
/// 至少有一条边**的源或目标取自 `>= k` 的标识（即未声明的悬挂端点）。
struct P18Case {
  /// 已声明节点个数；节点标识为 `0..k-1`（可为 0，覆盖空声明集边界）。
  k : Int
  /// 有向带权边添加序列，含至少一条引用未声明节点（>= k）的悬挂边。
  edges : Array[(Int, Int, Int)]
}

///|
/// 随机用例生成器：先定已声明节点规模 `k ∈ [0, 6]`，再生成 `0..2k+1` 条
/// 「合法边」（源/目标 ∈ 0..k-1），最后**强制注入 1..3 条悬挂边**（其源或目标
/// 取自未声明区间 `[k, k+3]`），并将注入位置随机打散。
///
/// 关键设计：
///   * 悬挂端点恒取自 `k + r`（`r ∈ 0..3`），必然 `>= k`，故必然未声明。
///   * 每条悬挂边随机选择「仅源悬挂 / 仅目标悬挂 / 源目标皆悬挂」，覆盖三类
///     越界形态。
///   * 允许 `k = 0`（无任何合法节点），此时全部边皆为悬挂边，覆盖极端边界。
fn p18_gen() -> @infra_pbt.Gen[P18Case] {
  @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_below(7) // 已声明节点数 0..6
    let edges : Array[(Int, Int, Int)] = []
    // 合法边：源/目标 ∈ 0..k-1（k=0 时跳过，无合法节点可取）。
    if k > 0 {
      let m = rng.next_below(2 * k + 1) // 合法边条数 0..2k
      let mut i = 0
      while i < m {
        let u = rng.next_below(k)
        let v = rng.next_below(k)
        let w = rng.next_range(-50, 50)
        edges.push((u, v, w))
        i = i + 1
      }
    }
    // 强制注入 1..3 条悬挂边：端点取自未声明区间 [k, k+3]。
    let dangling_cnt = rng.next_range(1, 3) // 1..3（闭区间）
    let mut j = 0
    while j < dangling_cnt {
      let bad1 = k + rng.next_below(4) // 必 >= k，未声明
      let bad2 = k + rng.next_below(4) // 必 >= k，未声明
      let w = rng.next_range(-50, 50)
      // 随机选择悬挂形态：0=仅源悬挂，1=仅目标悬挂，2=源目标皆悬挂。
      let shape = rng.next_below(3)
      // 合法端点候选（k>0 时取 0，否则退化为另一悬挂端点）。
      let good = if k > 0 { 0 } else { bad2 }
      match shape {
        0 => edges.push((bad1, good, w))
        1 => edges.push((good, bad1, w))
        _ => edges.push((bad1, bad2, w))
      }
      j = j + 1
    }
    P18Case::{ k, edges }
  })
}

///|
/// 由边添加序列计算「期望边集」：以 `(源, 目标)` 为键写入权重，后写覆盖先写，
/// 从而天然实现「去重 + 末次权重」（与 Property 17 的物化语义一致）。
fn p18_expected(edges : Array[(Int, Int, Int)]) -> Map[(Int, Int), Int] {
  let expected : Map[(Int, Int), Int] = Map([])
  for e in edges {
    let (u, v, w) = e
    expected[(u, v)] = w // 末次覆盖
  }
  expected
}

///|
/// 收集用例中应当出现的全部节点标识：已声明的 `0..k-1` 与所有边端点之并集。
/// 用于「补全缺失声明后再次 build」的状态完好性佐证。
fn p18_all_nodes(case : P18Case) -> Map[Int, Unit] {
  let all_nodes : Map[Int, Unit] = Map([])
  for n in 0..<case.k {
    all_nodes[n] = ()
  }
  for e in case.edges {
    let (u, v, _) = e
    all_nodes[u] = ()
    all_nodes[v] = ()
  }
  all_nodes
}

///|
/// 校验单个用例：构造含悬挂边的构造器，断言悬挂边物化失败且累积状态不变。
///
/// 校验链路：
///   1. 先 `add_node` 声明 `0..k-1`，再依次 `add_edge` 全部边（含悬挂边）。
///   2. `build()` 必须为 `Err(InvalidArgument(_))`（pattern match）。
///   3. 幂等佐证：再次 `build()` 仍为 `Err(InvalidArgument(_))`（状态未被破坏）。
///   4. 可补全佐证：补声明全部缺失节点后 `build()` 应为 `Ok`，且物化图的
///      `node_count` 等于全部节点数、`edge_count` 等于去重后边数——证明此前
///      累积的 order/declared/edges 完好无损。
fn p18_check(case : P18Case) -> Bool {
  // 1) 构造：声明 0..k-1，再添加全部边（含强制注入的悬挂边）。
  let builder : GraphBuilder[Int, Int] = GraphBuilder::new()
  for n in 0..<case.k {
    builder.add_node(n) |> ignore
  }
  for e in case.edges {
    let (u, v, w) = e
    builder.add_edge(u, v, w) |> ignore
  }
  // 2) 悬挂边 → build 必为 Err(InvalidArgument(_))。
  match builder.build() {
    Err(InvalidArgument(_)) => ()
    _ => return false
  }
  // 3) 幂等佐证：再次 build 仍为相同的 Err(InvalidArgument(_))，
  //    表明首次失败未修改任何累积状态。
  match builder.build() {
    Err(InvalidArgument(_)) => ()
    _ => return false
  }
  // 4) 可补全佐证：补声明缺失节点后 build 应成功并含全部边/节点。
  let all_nodes = p18_all_nodes(case)
  for n, _ in all_nodes {
    builder.add_node(n) |> ignore // 已声明者自动去重
  }
  let graph = match builder.build() {
    Ok(g) => g
    Err(_) => return false // 补全后仍失败 = 此前累积状态被破坏
  }
  let expected = p18_expected(case.edges)
  if graph.node_count() != all_nodes.length() {
    return false
  }
  if graph.edge_count() != expected.length() {
    return false
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 18: 悬挂边物化失败且状态不变
///
/// 对任意含「引用未声明节点」的边的构造器，`build` 返回
/// `Err(InvalidArgument)`，且构造器已累积的节点与边集合不被修改（以幂等的
/// 二次失败、以及补全声明后成功物化全部边/节点来双重佐证）。
///
/// 另以确定性锚点固定一个悬挂边示例：仅声明节点 0，却添加边 (0,1,5)（节点 1
/// 未声明）→ build 失败为 InvalidArgument；随后补声明节点 1 再 build 成功，
/// 且该边以权重 5 物化为唯一一条边——证明首次失败未破坏累积状态。
///
/// **Validates: Requirements 12.5**
test "Feature: championship-v1-upgrade, Property 18: dangling-edge materialization fails and leaves builder state unchanged" {
  // 锚点：仅声明 0，添加悬挂边 (0,1,5)（1 未声明）。
  let anchor : GraphBuilder[Int, Int] = GraphBuilder::new()
  anchor.add_node(0) |> ignore
  anchor.add_edge(0, 1, 5) |> ignore
  // 首次 build 应失败为 InvalidArgument。
  match anchor.build() {
    Err(InvalidArgument(_)) => ()
    _ => assert_true(false)
  }
  // 幂等：再次 build 仍为 InvalidArgument（状态未变）。
  match anchor.build() {
    Err(InvalidArgument(_)) => ()
    _ => assert_true(false)
  }
  // 补声明缺失节点 1 后，build 应成功且含原边（权重 5、唯一一条）。
  anchor.add_node(1) |> ignore
  match anchor.build() {
    Ok(g) => {
      @test.assert_eq(g.node_count(), 2)
      @test.assert_eq(g.edge_count(), 1)
      let asucc = g.successors()
      @test.assert_eq(asucc(0), [(1, 5)])
    }
    Err(_) => assert_true(false) // 补全后不应失败
  }

  // 属性：随机用例上，悬挂边恒致 build 失败为 InvalidArgument，且累积状态
  // 完好（幂等二次失败 + 补全后成功物化全部边/节点）。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(p18_gen(), p18_check, iters=128)
  assert_true(ok)
}
