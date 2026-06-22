// Feature: championship-v1-upgrade, Property 26: 等价类差分一致
//
// 本文件以属性测试（property-based test）校验 `@infra_fuzz` 跨算法差分验证器
// Differential_Tester 的核心正确性不变量（design.md §「Property 26」/
// Requirement 16.1 / 16.2 / 16.3 / 16.4）：
//
//   **等价类差分一致**：对任意落入某等价类（Equivalence_Class）的随机非负权
//   图实例，类内两算法的最短路结果一致——
//     * 单位权图上 BFS 代价 == Dijkstra 代价（整数精确 · R16.1）；
//     * 非负权图上 Dijkstra 与 Bellman-Ford 单源距离逐点偏差 ≤1e-9（R16.2）；
//     * 整数权图上 Floyd-Warshall 与 Johnson 的全对最短距离矩阵逐元素 ≤1e-9
//       （R16.3）；
//     * 两算法均判不可达时一致给出不可达（R16.4）。
//
// 测试架构（与 task 15.1 支撑逻辑 `differential_test.mbt` 协作）：
//   * 一致性判定复用支撑逻辑 `differential_consistent(cls, g)`：`true` 表示
//     类内两算法在图 `g` 上结果一致（通过）、`false` 表示发现差分反例。
//   * 随机图来自非负权生成器 `fuzz_graph_nonneg_gen`（R16.6：仅非负权，权值
//     0.01–1e6），覆盖空图 / 单节点 / 稠密 / 稀疏 / 自环 / 平行边 / 多连通分量。
//   * 规模约束（R16.5）：节点 1–500、边 0–5000、权 0.01–1e6。本测试在该上限内
//     按等价类的算法复杂度选取适中规模上限（FW/Johnson 为 O(n³)，故取较小
//     节点上限以保持测试快速稳定），逐类各运行 ≥100 次随机实例（R16.5）。
//   * 不一致即报告（R16.7）：主属性以 `holds_for_all`（每类 iters≥100）断言；
//     一旦某类失败，再以**可复现种子**驱动 `p26_seeded_report` 重扫，配合
//     `shrink_fuzz_graph` 贪心收缩出最小反例，输出含「图实例 / 两侧输出 /
//     收缩后最小反例 / 随机种子」的诊断报告（复用 `differential_report`）。
//
// 驱动框架：复用本包生产依赖 `@infra_pbt` 的 `Gen` / `Rng` / `rng_new` /
// `holds_for_all`，以及本包 `fuzz_graph_nonneg_gen` / `shrink_fuzz_graph` /
// `shrink_iters_max` 与 task 15.1 支撑逻辑 `differential_consistent` /
// `differential_report`。每类 `holds_for_all` 迭代 128 次（≥100 基线）。

///|
/// 单源等价类（BFS↔Dijkstra）的节点规模上限。单源算法开销低，可取较大规模
/// 以充分扰动；仍远在 R16.5 的 500 节点上限内。
let p26_cap_n_single : Int = 300

///|
/// 单源等价类（BFS↔Dijkstra）的边规模上限（≤ R16.5 的 5000 边上限）。
let p26_cap_e_single : Int = 3000

///|
/// Dijkstra↔Bellman-Ford 等价类的节点规模上限。Bellman-Ford 为 O(V·E)，故
/// 取适中节点上限以保持测试快速；仍在 R16.5 约束内。
let p26_cap_n_bellman : Int = 120

///|
/// Dijkstra↔Bellman-Ford 等价类的边规模上限（≤ R16.5 的 5000 边上限）。
let p26_cap_e_bellman : Int = 1200

///|
/// Floyd-Warshall↔Johnson 等价类的节点规模上限。全对最短路为 O(n³)，故取较小
/// 节点上限以保证 ≥100 次迭代仍快速终止；权值与边数仍在 R16.5 约束内。
let p26_cap_n_allpairs : Int = 40

///|
/// Floyd-Warshall↔Johnson 等价类的边规模上限（≤ R16.5 的 5000 边上限）。
let p26_cap_e_allpairs : Int = 300

///|
/// 每个等价类的属性测试迭代次数（≥100 基线 · R16.5「每类不少于 100 次」）。
let p26_iters : Int = 128

///|
/// R16.7 可复现反例重扫的基准种子。一旦主属性失败，自该种子起逐一递增驱动
/// 生成器，定位首个可复现的差分反例并报告其种子。
let p26_base_seed : UInt64 = 0xC0FF_EE00_1357_9BDF

///|
/// R16.7 可复现反例重扫的最大尝试次数：远超 `p26_iters` 以提高命中反例的概率，
/// 仅在主属性已失败时执行，对正常通过路径零开销。
let p26_rescan_iters : Int = 4096

///|
/// 单次重扫的结果：`found` 标记是否捕获到可复现反例，`report` 为对应诊断文本
/// （含图实例 / 两侧输出 / 收缩后最小反例 / 随机种子 · R16.7）。
struct P26Report {
  found : Bool
  report : String
}

///|
/// 按等价类返回 `(节点上限, 边上限)`。各上限均落在 R16.5 约束（节点 ≤500、
/// 边 ≤5000）内，并按算法复杂度分级以保持测试快速稳定。
fn p26_caps(cls : EquivClass) -> (Int, Int) {
  match cls {
    BfsVsDijkstraUnit => (p26_cap_n_single, p26_cap_e_single)
    DijkstraVsBellmanFord => (p26_cap_n_bellman, p26_cap_e_bellman)
    FloydWarshallVsJohnson => (p26_cap_n_allpairs, p26_cap_e_allpairs)
  }
}

///|
/// 等价类专属的非负权图生成器：每次采样先由 `Rng` 在该类规模上限内随机选取
/// `(max_n, max_edges)`（节点 ≥1 · R16.5），再以 `fuzz_graph_nonneg_gen`
/// 产出非负权图（R16.6）。规模随迭代变化以扩大结构覆盖。
fn p26_case_gen(cls : EquivClass) -> @infra_pbt.Gen[FuzzGraph] {
  let (cap_n, cap_e) = p26_caps(cls)
  @infra_pbt.Gen::new(fn(rng) {
    let max_n = rng.next_range(1, cap_n)
    let max_edges = rng.next_range(0, cap_e)
    fuzz_graph_nonneg_gen(max_n, max_edges).generate(rng)
  })
}

///|
/// 贪心收缩（R16.7）：自失败图 `g` 出发，反复取 `shrink_fuzz_graph` 候选集中
/// 首个「仍触发差分不一致」的更小图继续收缩，直至无更小候选仍失败。每个候选
/// 严格更小（节点或边数 -1），故必然终止；并以 `shrink_iters_max`（1000）为
/// 迭代上限作双重保险（R17.6）。返回该收缩策略可达的最小失败反例。
fn p26_greedy_shrink(cls : EquivClass, g : FuzzGraph) -> FuzzGraph {
  let mut current = g
  let mut improved = true
  let mut rounds = 0
  while improved && rounds < shrink_iters_max {
    improved = false
    for cand in shrink_fuzz_graph(current) {
      if !differential_consistent(cls, cand) {
        // 命中仍不一致的更小候选：采纳并从它继续收缩。
        current = cand
        improved = true
        break
      }
    }
    rounds += 1
  }
  current
}

///|
/// 可复现反例重扫（R16.7）：自 `base_seed` 起逐一递增种子，用该种子独立构造
/// `Rng` 驱动等价类生成器产图并判一致性；一旦发现不一致，贪心收缩出最小反例
/// 并以 `differential_report` 构建含「等价类 / 种子 / 图实例 / 两侧输出」的
/// 报告。整个 `(seed → Rng → 图)` 流程确定性可复现，故报告中的种子可逐字节
/// 重放该反例。`iters` 次内未命中则返回 `found=false`。
fn p26_seeded_report(
  cls : EquivClass,
  base_seed : UInt64,
  iters : Int,
) -> P26Report {
  let (cap_n, cap_e) = p26_caps(cls)
  let mut i = 0
  while i < iters {
    let seed = base_seed + i.to_uint64()
    let rng = @infra_pbt.rng_new(seed)
    let max_n = rng.next_range(1, cap_n)
    let max_edges = rng.next_range(0, cap_e)
    let g = fuzz_graph_nonneg_gen(max_n, max_edges).generate(rng)
    if !differential_consistent(cls, g) {
      let minimal = p26_greedy_shrink(cls, g)
      return { found: true, report: differential_report(cls, minimal, seed) }
    }
    i += 1
  }
  { found: false, report: "" }
}

///|
/// 对单个等价类执行一轮 ≥100 次属性测试，返回是否通过；失败时打印 R16.7 的
/// 可复现报告（含图实例 / 两侧输出 / 最小反例 / 种子）。`holds_for_all` 在每类
/// 内随机采样并判 `differential_consistent`，迭代 `p26_iters`（128 ≥100）次。
/// 断言交由调用方（测试块，具 error 签名）执行。
fn p26_run_class(cls : EquivClass) -> Bool {
  let ok = @infra_pbt.holds_for_all(
    p26_case_gen(cls),
    fn(g) { differential_consistent(cls, g) },
    iters=p26_iters,
  )
  if !ok {
    // R16.7：以可复现种子重扫，输出含图实例 / 两侧输出 / 最小反例 / 种子的报告。
    let rep = p26_seeded_report(cls, p26_base_seed, p26_rescan_iters)
    if rep.found {
      println(rep.report)
    } else {
      println(
        "差分不一致已由属性测试发现，但可复现重扫未在上限内命中反例；请提高 p26_rescan_iters 或更换 p26_base_seed 复现。",
      )
    }
  }
  ok
}

///|
/// Feature: championship-v1-upgrade, Property 26: 等价类差分一致
///
/// 对任意非负权随机图实例，三个等价类内两算法结果一致：单位权图上 BFS 代价
/// == Dijkstra 代价（精确 · R16.1）；非负权图上 Dijkstra 与 Bellman-Ford 偏差
/// ≤1e-9（R16.2）；整数权图上 Floyd-Warshall 与 Johnson 全对距离矩阵逐元素
/// ≤1e-9（R16.3）；两算法均判不可达时一致（R16.4）。每个等价类各迭代 128 次
/// （≥100 基线 · R16.5）；不一致即以可复现种子收缩并报告最小反例（R16.7）。
///
/// **Validates: Requirements 16.1, 16.2, 16.3, 16.4**
test "Feature: championship-v1-upgrade, Property 26: equivalence-class differential consistency" {
  // 锚点 1：可复现种子重扫在真实（恒一致）算法上找不到反例（found=false），
  // 印证报告机制不会对一致算法产生伪反例。
  let probe = p26_seeded_report(DijkstraVsBellmanFord, p26_base_seed, 256)
  assert_false(probe.found)
  assert_eq(probe.report, "")
  // 锚点 2：贪心收缩对一致图为不动点（无更小候选仍失败 → 收缩停在原图规模内）。
  let g_anchor : FuzzGraph = {
    n: 4,
    edges: [(0, 1, 1.0), (1, 2, 2.0), (2, 3, 3.0)],
  }
  let shrunk = p26_greedy_shrink(DijkstraVsBellmanFord, g_anchor)
  // 一致图无失败候选，收缩不前进，返回原图（逐元素相等）。
  assert_eq(shrunk, g_anchor)
  // 锚点 3：等价类生成器在给定种子下确定性产出（同种子两次逐元素相等）。
  let gen = p26_case_gen(BfsVsDijkstraUnit)
  let g1 = gen.generate(@infra_pbt.rng_new(0x1234_5678_9ABC_DEF0))
  let g2 = gen.generate(@infra_pbt.rng_new(0x1234_5678_9ABC_DEF0))
  assert_eq(g1, g2)
  // 主属性：三个等价类各 ≥100 次随机实例下差分恒一致（R16.1–16.4 / R16.5）。
  assert_true(p26_run_class(BfsVsDijkstraUnit))
  assert_true(p26_run_class(DijkstraVsBellmanFord))
  assert_true(p26_run_class(FloydWarshallVsJohnson))
}
