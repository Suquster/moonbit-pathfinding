// Feature: championship-v1-upgrade, Property 28: 反例收缩的局部最小性
//
// 本文件以属性测试（property-based test）校验 `@infra_fuzz` 反例收缩的核心
// 不变量（design.md §「Property 28」/ Requirement 17.6）：
//
//   **反例收缩的局部最小性**：对任意触发失败谓词的图实例，`shrink_fuzz_graph`
//   配合 `@infra_pbt.check_with_shrink` 驱动的收缩，在不超过
//   `shrink_iters_max`（1000）次迭代内产出满足「局部最小性」的最小失败实例；
//   局部最小性定义为「再移除其中任一节点或任一边后，失败不再复现」。
//
// 语义说明（务必与 @infra_pbt 实际语义对齐）：
//   * `check_with_shrink(gen, prop, shrink, iters?)` 中谓词 `prop` 返回
//     `true` 表示「通过」、`false` 表示「失败（即为反例）」；
//   * 返回的 `CheckResult { passed; counterexample }`：`passed == false` 时
//     `counterexample` 携带收缩后的最小失败反例，且该反例必满足
//     `prop(c) == false`（仍失败）。
//
// 因此「局部最小性」可直接表述为：对最小反例 `c` 的**每个** `shrink_fuzz_graph`
// 候选 `cand`，都有 `prop(cand) == true`（移除任一节点/边后失败不再复现 →
// 候选不再是反例）。这正是 `check_with_shrink` 内部贪心收缩终止时的不变量，
// 本测试对其作端到端的独立验证。
//
// 人为失败谓词设计：`prop_below(k) = fn(g) { g.edges.length() < k }`，即
//   * 边数 < k 的图「通过」；
//   * 边数 ≥ k 的图「失败」（成为反例）。
// 用含较多边的种子图（稠密类别）必然触发失败，收缩会朝「边数恰为 k」逼近：
// 再删任一边 → 边数 k-1 < k（通过）；再删任一节点 → 关联边一并移除使边数
// 跌破 k（通过）。从而最小反例的所有候选都不再是反例 → 局部最小。
//
// 驱动框架：复用本包生产依赖 `@infra_pbt` 的 `Gen` / `holds_for_all` /
// `check_with_shrink`，以及本包 `shrink_fuzz_graph` / `shrink_iters_max`。
// 外层 `holds_for_all` 迭代 128 次（≥100 基线），每次内部再跑一轮
// `check_with_shrink(iters=shrink_iters_max)`。

///|
/// 单次属性迭代的输入：失败阈值 `k` 与种子图规模参数。
///
/// `k ∈ [1, 8]`：阈值取小正整数，既保证「边数 ≥ k」的反例在采样中极易出现，
/// 又使收缩后的最小反例规模微小、候选集校验快速稳定。`max_n` / `max_edges`
/// 取足以稳定产出稠密图（边数远超 k）的规模，确保 `check_with_shrink` 在
/// `shrink_iters_max` 次采样内必能命中反例。
struct P28Params {
  k : Int
  max_n : Int
  max_edges : Int
}

///|
/// 阈值与规模参数的生成器。
///
/// `k ∈ [1, 8]`；`max_n ∈ [8, 50]`（≥2 以便稠密类别生效）；
/// `max_edges ∈ [200, 800]`（远超 k，保证反例充足）。
fn p28_param_gen() -> @infra_pbt.Gen[P28Params] {
  @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_range(1, 8)
    let max_n = rng.next_range(8, 50)
    let max_edges = rng.next_range(200, 800)
    { k, max_n, max_edges }
  })
}

///|
/// 人为失败谓词工厂：`prop_below(k)(g)` 在「边数 < k」时返回 `true`（通过），
/// 否则返回 `false`（失败，即为反例）。
fn p28_prop_below(k : Int) -> (FuzzGraph) -> Bool {
  fn(g) { g.edges.length() < k }
}

///|
/// 局部最小性判定：对最小反例 `c` 的每个 `shrink_fuzz_graph` 候选 `cand`，
/// 校验 `prop(cand) == true`（移除任一节点/边后失败不再复现）。
///
/// 任一候选仍使 `prop` 为假（仍是反例）即说明 `c` 并非局部最小，返回 `false`。
/// 空候选集（`c` 已无更小图）视为平凡局部最小，返回 `true`。
fn p28_locally_minimal(c : FuzzGraph, prop : (FuzzGraph) -> Bool) -> Bool {
  for cand in shrink_fuzz_graph(c) {
    if !prop(cand) {
      // 存在仍触发失败的更小候选 → 非局部最小。
      return false
    }
  }
  true
}

///|
/// 对单组参数执行一轮「收缩 + 局部最小性」端到端校验，返回是否满足性质。
///
/// 流程：
///   1. 以 `fuzz_graph_gen(max_n, max_edges)` 为种子生成器、`prop_below(k)`
///      为失败谓词、`shrink_fuzz_graph` 为收缩策略，限定收缩迭代上限为
///      `shrink_iters_max`（R17.6 的 ≤1000 次约束）；
///   2. 取收缩所得最小反例 `c`：
///      - `c` 自身必仍失败：`prop(c) == false`；
///      - 局部最小性：`c` 的每个收缩候选都不再是反例（`prop(cand) == true`）；
///   3. 若本轮未命中反例（`counterexample == None`），返回 `true`（该轮对
///      性质无证伪意义，交由其他轮次与锚点断言保证反例确被覆盖）。
fn p28_shrink_locally_minimal(p : P28Params) -> Bool {
  let gen = fuzz_graph_gen(p.max_n, p.max_edges)
  let prop = p28_prop_below(p.k)
  let result = @infra_pbt.check_with_shrink(
    gen,
    prop,
    shrink_fuzz_graph,
    iters=shrink_iters_max,
  )
  match result.counterexample {
    Some(c) =>
      // 最小反例自身仍失败，且其所有收缩候选都不再是反例 → 局部最小。
      !prop(c) && p28_locally_minimal(c, prop)
    None =>
      // 本轮未命中反例，对性质无证伪意义。
      true
  }
}

///|
/// Feature: championship-v1-upgrade, Property 28: 反例收缩的局部最小性
///
/// 对随机阈值 `k` 与种子图规模，`check_with_shrink` 配合 `shrink_fuzz_graph`
/// 收缩所得最小反例满足局部最小性：移除其中任一节点或任一边后失败不再复现
/// （即所有收缩候选都不再是反例）。迭代 128 次（≥100 基线）。
///
/// **Validates: Requirements 17.6**
test "Feature: championship-v1-upgrade, Property 28: counterexample shrink local minimality" {
  // 锚点 1：固定参数下确凿命中反例，且最小反例边数恰为阈值 k。
  // 理由：最小反例边数 m 必满足 m >= k（仍失败）且删任一边后 m-1 < k（通过）
  //       → m <= k，故 m == k；且其所有候选都不再是反例（局部最小）。
  let k_anchor = 3
  let gen_anchor = fuzz_graph_gen(40, 600)
  let prop_anchor = p28_prop_below(k_anchor)
  let result_anchor = @infra_pbt.check_with_shrink(
    gen_anchor,
    prop_anchor,
    shrink_fuzz_graph,
    iters=shrink_iters_max,
  )
  // 确凿命中反例（稠密种子图边数远超阈值）。
  assert_false(result_anchor.passed)
  match result_anchor.counterexample {
    Some(c) => {
      // 最小反例自身仍失败。
      assert_false(prop_anchor(c))
      // 最小反例边数恰为阈值 k_anchor。
      assert_eq(c.edges.length(), k_anchor)
      // 局部最小性：所有收缩候选都不再是反例。
      assert_true(p28_locally_minimal(c, prop_anchor))
    }
    None => assert_true(false) // 不应发生：锚点参数必命中反例。
  }
  // 锚点 2：阈值 k=1 时最小反例应恰好仅 1 条边（再删该边即空边集 → 通过）。
  let prop_one = p28_prop_below(1)
  let result_one = @infra_pbt.check_with_shrink(
    fuzz_graph_gen(30, 400),
    prop_one,
    shrink_fuzz_graph,
    iters=shrink_iters_max,
  )
  match result_one.counterexample {
    Some(c) => {
      assert_eq(c.edges.length(), 1)
      assert_true(p28_locally_minimal(c, prop_one))
    }
    None => assert_true(false)
  }
  // 属性：随机阈值与规模下，收缩所得最小反例恒满足局部最小性。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(
    p28_param_gen(),
    p28_shrink_locally_minimal,
    iters=128,
  )
  assert_true(ok)
}
