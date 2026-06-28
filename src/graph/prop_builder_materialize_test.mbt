// Feature: championship-v1-upgrade, Property 17: 构造器物化完整性与末次覆盖
//
// 本文件以属性测试（property-based test）校验链式图构造器 `GraphBuilder` 的
// 物化完整性与末次权重覆盖语义（design.md §「Property 17」/ Requirement
// 12.2、12.3）：
//
//   * Requirement 12.2：依次添加 N 条边后物化，产出的图包含全部已添加边且
//     **无遗漏、无重复引入**。
//   * Requirement 12.3：对同一 `(源, 目标)` 重复添加边，仅保留一条实例并采用
//     **末次添加的权重**。
//
// 形式化属性：对任意「边均引用已声明节点」的边添加序列，`build` 产出图的边集
// 恰等于「按 (源, 目标) 去重、取末次权重」后的边集——逐源节点比对邻居映射
// （目标 -> 权重）应与期望完全一致，且全图 `edge_count()` 等于去重后边数。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 128（≥100 基线）。

///|
/// 单个随机用例：节点全集为 `0..k-1`（共 `k` 个 Int 节点），外加一段有向带权
/// 边添加序列 `edges`（每个三元组为 `(源, 目标, 权重)`）。
///
/// 生成时刻意令边的源/目标均取自已声明节点 `0..k-1`，从而保证 `build` 必然
/// 成功（无悬挂边）；同时刻意注入重复 `(源, 目标)` 的不同权重，以检验末次覆盖。
struct P17Case {
  /// 节点个数；节点标识为 `0..k-1`。
  k : Int
  /// 有向带权边添加序列，含刻意制造的重复 (源, 目标)。
  edges : Array[(Int, Int, Int)]
}

///|
/// 随机用例生成器：先定节点规模 `k ∈ [1, 6]`，再生成 `0..3k` 条边。
///
/// 关键设计：
///   * 源/目标一律取自 `0..k-1`（合法节点），保证 `build` 为 `Ok`；节点池较小
///     使重复 `(源, 目标)` 自然高频出现。
///   * 每条边以 50% 概率紧随追加一条「同 (源, 目标)、新权重」的重复边，显式
///     制造末次覆盖场景（Requirement 12.3）。
///   * 允许空边序列（覆盖「无边」边界）。
fn p17_gen() -> @infra_pbt.Gen[P17Case] {
  @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_range(1, 6) // 节点数 1..6（闭区间）
    let edges : Array[(Int, Int, Int)] = []
    let m = rng.next_below(3 * k + 1) // 边条数 0..3k
    let mut i = 0
    while i < m {
      let u = rng.next_below(k) // 源 ∈ 0..k-1（已声明）
      let v = rng.next_below(k) // 目标 ∈ 0..k-1（已声明）
      let w = rng.next_range(-50, 50) // 权重 -50..50
      edges.push((u, v, w))
      // 以 50% 概率追加同 (u, v) 的不同权重，刻意制造末次覆盖场景。
      if rng.next_bool() {
        let w2 = rng.next_range(-50, 50)
        edges.push((u, v, w2))
      }
      i = i + 1
    }
    P17Case::{ k, edges }
  })
}

///|
/// 由边添加序列计算「期望边集」：以 `(源, 目标)` 为键写入权重，后写覆盖先写，
/// 从而天然实现「去重 + 末次权重」（Requirement 12.3）。
///
/// 返回的 `Map` 大小即去重后边数，逐项即每条边的末次权重。
fn p17_expected(edges : Array[(Int, Int, Int)]) -> Map[(Int, Int), Int] {
  let expected : Map[(Int, Int), Int] = Map([])
  for e in edges {
    let (u, v, w) = e
    expected[(u, v)] = w // 末次覆盖
  }
  expected
}

///|
/// 校验单个用例：构造、物化，并逐源节点比对物化图与期望边集是否完全一致。
///
/// 校验链路：
///   1. 先 `add_node` 全部节点，再依次 `add_edge`，`build` 必须为 `Ok`。
///   2. `node_count()` 等于 `k`；`edge_count()` 等于期望（去重后）边数。
///   3. 对每个源节点 `u`：其 `successors()` 邻居数组的目标互不重复（无重复
///      引入），且其「目标 -> 权重」映射与期望中以 `u` 为源的子集逐项相等
///      （无遗漏、末次权重）。
///   4. 全图邻居总数等于期望边数（与 `edge_count()` 双重确认）。
fn p17_check(case : P17Case) -> Bool {
  // 1) 构造：先声明全部节点，再依次添加全部边。
  let builder : GraphBuilder[Int, Int] = GraphBuilder::new()
  for n in 0..<case.k {
    builder.add_node(n) |> ignore
  }
  for e in case.edges {
    let (u, v, w) = e
    builder.add_edge(u, v, w) |> ignore
  }
  // build 应 Ok（边均引用已声明节点）。
  let graph = match builder.build() {
    Ok(g) => g
    Err(_) => return false
  }
  // 2) 期望边集（去重 + 末次权重）与规模一致性。
  let expected = p17_expected(case.edges)
  if graph.node_count() != case.k {
    return false
  }
  if graph.edge_count() != expected.length() {
    return false
  }
  // 3) 逐源节点比对邻居映射。
  let succ = graph.successors()
  let mut total = 0
  for u in 0..<case.k {
    let actual = succ(u)
    // 实际邻居：目标 -> 权重；同时检测重复目标（无重复引入）。
    let actual_map : Map[Int, Int] = Map([])
    for pair in actual {
      let (v, w) = pair
      if actual_map.get(v) is Some(_) {
        return false // 同一源下重复目标 = 重复引入，违反 R12.2
      }
      actual_map[v] = w
    }
    // 期望中以 u 为源的子集。
    let exp_map : Map[Int, Int] = Map([])
    for key, w in expected {
      let (eu, ev) = key
      if eu == u {
        exp_map[ev] = w
      }
    }
    // 大小一致 + 逐项一致（无遗漏、末次权重）。
    if actual_map.length() != exp_map.length() {
      return false
    }
    for v, w in exp_map {
      match actual_map.get(v) {
        Some(aw) => if aw != w { return false }
        None => return false // 期望边缺失 = 遗漏
      }
    }
    total = total + actual.length()
  }
  // 4) 全图邻居总数 == 期望边数（双重确认无遗漏、无重复引入）。
  total == expected.length()
}

///|
/// Feature: championship-v1-upgrade, Property 17: 构造器物化完整性与末次覆盖
///
/// 对任意边添加序列（边均引用已声明节点），`build` 产出图的边集等于「按
/// (源, 目标) 去重、取末次权重」后的边集——无遗漏、无重复引入，且重复
/// `(源, 目标)` 取末次权重。
///
/// 另以确定性锚点固定一个末次覆盖示例：对 (0,1) 先后写入权重 5、9，物化后
/// 该边权重应为 9 且仅此一条。
///
/// **Validates: Requirements 12.2, 12.3**
test "Feature: championship-v1-upgrade, Property 17: builder materialization integrity and last-write coverage" {
  // 锚点：末次覆盖——(0,1) 权重 5 → 9，最终应为 9 且去重为一条边。
  let anchor : GraphBuilder[Int, Int] = GraphBuilder::new()
  anchor.add_node(0) |> ignore
  anchor.add_node(1) |> ignore
  anchor.add_edge(0, 1, 5) |> ignore
  anchor.add_edge(0, 1, 9) |> ignore
  match anchor.build() {
    Ok(g) => {
      @test.assert_eq(g.edge_count(), 1)
      let asucc = g.successors()
      @test.assert_eq(asucc(0), [(1, 9)])
    }
    Err(_) => assert_true(false) // 锚点：build 不应失败
  }

  // 属性：随机用例上，物化边集恒等于「去重 + 末次权重」期望集。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(p17_gen(), p17_check, iters=128)
  assert_true(ok)
}
