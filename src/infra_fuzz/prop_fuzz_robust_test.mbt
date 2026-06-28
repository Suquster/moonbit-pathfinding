// Feature: championship-v1-upgrade, Property 27: 算法对模糊输入鲁棒
//
// 本文件以属性测试（property-based test）校验 `@infra_fuzz` 模糊测试驱动
// （task 16.1）所裁决的核心鲁棒性不变量（design.md §「Property 27」/
// Requirement 17.1 / 17.3 / 17.5）：
//
//   **算法对模糊输入鲁棒**：对模糊生成器产出的任意图实例，被测电池中的每个
//   寻路算法都必须
//     (a) **正常终止**——不死循环、不崩溃（由「属性测试能在有限迭代内跑完且
//         无 panic」端到端见证 · R17.3）；
//     (b) **返回结构上有效的结果**（合法游走 / 距离映射 / 全对矩阵 / 明确无解）
//         **或返回结构化 `PathError`**（R17.3 / R17.5）。
//   任一算法在任一实例上若结果结构非法（如返回的「路径」并非图中真实游走、
//   代价与路径不符、Floyd-Warshall 对角异常等），即判该算法**不鲁棒**，属性
//   立即被证伪。
//
// 与 task 16.1 的关系：
//   * task 16.1（`fuzz_driver_test.mbt`）提供把 `FuzzGraph` 喂给整套算法电池、
//     逐一作结构化鲁棒裁决的**驱动逻辑**（harness），并以确定性单元测试自验；
//   * 本文件（task 16.2）在该驱动之上，用 `@infra_pbt.holds_for_all` 对**随机
//     生成的 ≥100 个图实例**反复施加鲁棒裁决，把「每算法对模糊输入鲁棒」提升
//     为统计意义上的属性保证（R17.1 结构覆盖 + R17.3 鲁棒 + R17.5 非法参数）。
//
// 覆盖的结构类别（R17.1）：生成器 `fuzz_graph_nonneg_gen` /`fuzz_graph_gen`
//   覆盖空图 / 单节点 / 稠密 / 稀疏 / 自环 / 平行边 / 多连通分量；随机种子在
//   每次迭代驱动出不同类别实例，从而属性跨全部结构类别成立。
//
// 两套电池分流（与驱动一致）：
//   * **非负权电池**（`fuzz_run_from_seed_nonneg`）：BFS / Dijkstra /
//     Bellman-Ford / Floyd-Warshall / typed_shortest_path / typed_bfs /
//     ALT / CH 共 8 个算法（空图为 2 个子集），全部要求鲁棒。
//   * **有符号权电池**（`fuzz_run_from_seed_signed`）：Bellman-Ford /
//     Floyd-Warshall / typed_shortest_path 这 3 个对负权有定义行为的算法，
//     在可含负权（含负权环）图上仍须鲁棒（返回有效结果或以结构化错误处理）。
//
// 可复现（R17.4 / R17.7）：每次迭代的图由 `(seed, max_n, max_edges)` 经
//   `fuzz_run_from_seed_*` 内部的 `@infra_pbt.rng_new(seed)` + 确定性生成器
//   复现；`FuzzRunReport` 携带 `seed`，失败可经 `describe()` 输出种子定位。
//
// 规模选取：`max_n ∈ [0, 24]`、`max_edges ∈ [0, 80]`，兼顾结构多样性与
//   Floyd-Warshall（O(n³)）/ CH·ALT 预处理开销，使 ≥100 迭代快速稳定收敛；
//   生成器的结构类别覆盖与规模无关（小图同样体现自环/平行边/多分量等）。
//
// 驱动框架：复用本包生产依赖 `@infra_pbt` 的 `Gen` / `holds_for_all`，以及
//   task 16.1 同包测试文件提供的 `fuzz_run_from_seed_nonneg` /
//   `fuzz_run_from_seed_signed` / `FuzzRunReport` / `probe_invalid_args`。
//   外层 `holds_for_all` 迭代 128 次（≥100 基线）。

///|
/// 单次属性迭代的输入：64 位种子与图规模参数。
///
/// `seed` 取自 `Rng::next()`（满 64 位），驱动确定性图生成（R17.7 可复现）；
/// `max_n` / `max_edges` 取适中区间——既覆盖退化边界（0 节点 / 0 边的空图），
/// 又覆盖含边的稀疏 / 稠密 / 自环 / 平行边 / 多连通分量等结构类别（R17.1）。
struct P27Params {
  seed : UInt64
  max_n : Int
  max_edges : Int
}

///|
/// 种子与规模参数的生成器。
///
/// `seed` 取 `rng.next()` 的全 64 位；`max_n ∈ [0, 24]`、`max_edges ∈ [0, 80]`，
/// 覆盖空图边界与含边的常规规模，同时控制 Floyd-Warshall / CH·ALT 预处理开销
/// 以保证 ≥100 迭代快速稳定。
fn p27_param_gen() -> @infra_pbt.Gen[P27Params] {
  @infra_pbt.Gen::new(fn(rng) {
    let seed = rng.next()
    let max_n = rng.next_range(0, 24)
    let max_edges = rng.next_range(0, 80)
    { seed, max_n, max_edges }
  })
}

///|
/// 非负权电池鲁棒性判定：以 `(seed, max_n, max_edges)` 确定性复现一个非负权
/// 图实例并运行完整算法电池，返回「全部算法均鲁棒」的总判定。
///
/// 作为 `@infra_pbt.holds_for_all` 的谓词：返回 `true` 表示该实例上全部算法
/// 鲁棒（通过）、`false` 表示存在不鲁棒算法（反例）。
fn p27_nonneg_robust(p : P27Params) -> Bool {
  fuzz_run_from_seed_nonneg(p.seed, p.max_n, p.max_edges).robust
}

///|
/// 有符号权电池鲁棒性判定：以 `(seed, max_n, max_edges)` 确定性复现一个可含
/// 负权（含负权环）图实例并运行负权安全子电池，返回「全部算法均鲁棒」的总判定。
fn p27_signed_robust(p : P27Params) -> Bool {
  fuzz_run_from_seed_signed(p.seed, p.max_n, p.max_edges).robust
}

///|
/// Feature: championship-v1-upgrade, Property 27: 算法对模糊输入鲁棒（非负权电池）
///
/// 对任意随机 `(seed, max_n, max_edges)`，由 `fuzz_graph_nonneg_gen` 确定性
/// 生成覆盖全部结构类别的非负权图实例，BFS / Dijkstra / Bellman-Ford /
/// Floyd-Warshall / typed_shortest_path / typed_bfs / ALT / CH 全部算法都
/// 正常终止并返回结构有效结果或结构化 `PathError`（不崩溃 / 不死循环）。
/// 迭代 128 次（≥100 基线）。
///
/// **Validates: Requirements 17.1, 17.3, 17.5**
test "Feature: championship-v1-upgrade, Property 27: algorithms robust on nonneg fuzz inputs" {
  // 锚点 1：固定种子 / 规模下整套非负权电池鲁棒，且报告携带正确种子与算法数。
  let r_anchor = fuzz_run_from_seed_nonneg(0xC0FF_EE00_1234_5678, 24, 80)
  assert_true(r_anchor.robust)
  @test.assert_eq(r_anchor.seed, 0xC0FF_EE00_1234_5678)
  // n>=1 时覆盖 8 个算法；n==0（空图）时为 2 个子集——两种皆为合法电池规模。
  assert_true(
    r_anchor.verdicts.length() == 8 || r_anchor.verdicts.length() == 2,
  )

  // 锚点 2：退化边界——空图（max_n=0）非负权电池仍鲁棒（空矩阵 + 结构化非法参数）。
  let r_empty = fuzz_run_from_seed_nonneg(7, 0, 0)
  assert_true(r_empty.robust)

  // 属性：随机种子与规模下，非负权电池全算法鲁棒。迭代 128 次（≥100）。
  let ok = @infra_pbt.holds_for_all(
    p27_param_gen(),
    p27_nonneg_robust,
    iters=128,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 27: 算法对模糊输入鲁棒（有符号权电池）
///
/// 对任意随机 `(seed, max_n, max_edges)`，由 `fuzz_graph_gen`（权可正可负，
/// 含负权环）确定性生成图实例，负权安全子电池（Bellman-Ford / Floyd-Warshall /
/// typed_shortest_path）全部正常终止并返回结构有效结果或以结构化错误
/// （如 `NegativeCycle`）处理（不崩溃 / 不死循环 · R17.3 / R17.5）。
/// 迭代 128 次（≥100 基线）。
///
/// **Validates: Requirements 17.1, 17.3, 17.5**
test "Feature: championship-v1-upgrade, Property 27: algorithms robust on signed fuzz inputs" {
  // 锚点 1：固定种子 / 规模下有符号权电池鲁棒，且报告携带正确种子。
  let r_anchor = fuzz_run_from_seed_signed(0x1357_9BDF_2468_ACE0, 20, 60)
  assert_true(r_anchor.robust)
  @test.assert_eq(r_anchor.seed, 0x1357_9BDF_2468_ACE0)

  // 锚点 2：退化边界——空图有符号权电池仍鲁棒（仅空矩阵 Floyd-Warshall）。
  let r_empty = fuzz_run_from_seed_signed(11, 0, 0)
  assert_true(r_empty.robust)

  // 属性：随机种子与规模下，有符号权电池全算法鲁棒。迭代 128 次（≥100）。
  let ok = @infra_pbt.holds_for_all(
    p27_param_gen(),
    p27_signed_robust,
    iters=128,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 27: 非法参数结构化处理（R17.5）
///
/// 模糊鲁棒性的一部分是「非法参数被结构化处理而非崩溃」：空节点集 / 越界源 /
/// 越界目标分别映射到 `InvalidArgument` / `SourceNotFound` / `TargetNotFound`。
/// 此判定与图实例无关（对任意输入恒成立），故以驱动提供的 `probe_invalid_args`
/// 直接断言，作为 Property 27 在「结构化错误路径」上的确定性锚点。
///
/// **Validates: Requirements 17.5**
test "Feature: championship-v1-upgrade, Property 27: invalid arguments handled structurally" {
  assert_true(probe_invalid_args())
}
