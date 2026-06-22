// Feature: championship-v1-upgrade, Property 7: 生成器同种子确定性
//
// 本文件以属性测试（property-based test）校验 `@infra_fuzz` 图生成器的核心
// 可复现性不变量（design.md §「Property 7」/ Requirement 5.4 / 6.2 / 17.7）：
//
//   **生成器同种子确定性**：对任意 64 位种子 `seed : UInt64` 与图规模参数
//   `(max_n, max_edges)`，用同一 `seed` 构造的两个独立 `@infra_pbt.Rng`
//   分别驱动同一生成器，两次产出的 `FuzzGraph` 逐元素完全相同（节点数、
//   边的源/目标/权重序列完全一致）。
//
// 该性质是差分测试与基准可复现的基石：
//   * R17.7 —— 「同种子 → 逐元素相同的图」，模糊/差分反例可凭种子重放。
//   * R5.4 / R6.2 —— 基准与 Rust 对比需「相同 64 位种子产出逐元素相同图」，
//     从而跨运行、跨工具链交叉校验有意义。
//
// 验证对象覆盖两个公开生成器：`fuzz_graph_gen`（权重可正可负）与
// `fuzz_graph_nonneg_gen`（仅非负权）。`FuzzGraph` 已 `derive(Eq)`，故两次
// 产出可直接以 `==` 断言逐元素相等。
//
// 驱动框架：复用本包生产依赖 `@infra_pbt` 的 `Gen` / `Rng` / `rng_new` /
// `holds_for_all`。迭代次数取 128（≥100 基线）。

///|
/// 单次属性迭代的输入：64 位种子与图规模参数。
///
/// `seed` 直接取自 `Rng::next()`（满 64 位）；`max_n` / `max_edges` 取自
/// 适中区间——既覆盖退化边界（0 节点 / 0 边）又覆盖含边的常规规模，且
/// 不依赖过大图以保持测试快速、稳定。
struct P7Params {
  seed : UInt64
  max_n : Int
  max_edges : Int
}

///|
/// 种子与规模参数的生成器。
///
/// `seed` 取 `rng.next()` 的全 64 位；`max_n ∈ [0, 200]`、`max_edges ∈
/// [0, 2000]`，覆盖空图边界（max_n=0 / max_edges=0）与含边的稀疏/稠密规模。
fn p7_param_gen() -> @infra_pbt.Gen[P7Params] {
  @infra_pbt.Gen::new(fn(rng) {
    let seed = rng.next()
    let max_n = rng.next_range(0, 200)
    let max_edges = rng.next_range(0, 2000)
    { seed, max_n, max_edges }
  })
}

///|
/// 以 `seed` 构造两个独立 `Rng`，分别驱动 `gen` 各生成一次，判断两次产出的
/// `FuzzGraph` 是否逐元素相等（依赖 `FuzzGraph` 的 `derive(Eq)`）。
///
/// 两个 `Rng` 由同一 `seed` 经 `@infra_pbt.rng_new` 独立构造，状态互不共享，
/// 因此若生成器完全由 `Rng` 驱动且无外部不确定性，两次产出必然相同。
fn p7_same_seed_equal(gen : @infra_pbt.Gen[FuzzGraph], seed : UInt64) -> Bool {
  let rng1 = @infra_pbt.rng_new(seed)
  let rng2 = @infra_pbt.rng_new(seed)
  let g1 = gen.generate(rng1)
  let g2 = gen.generate(rng2)
  g1 == g2
}

///|
/// Feature: championship-v1-upgrade, Property 7: 生成器同种子确定性（fuzz_graph_gen）
///
/// 对任意随机的 `(seed, max_n, max_edges)`，以同一 `seed` 两次驱动
/// `fuzz_graph_gen(max_n, max_edges)` 产出逐元素相同的图。
///
/// **Validates: Requirements 5.4, 6.2, 17.7**
test "Feature: championship-v1-upgrade, Property 7: fuzz_graph_gen same-seed determinism" {
  // 锚点：固定种子与规模下两次产出严格相等（直观回归基准）。
  let g_a = fuzz_graph_gen(50, 500)
  assert_true(p7_same_seed_equal(g_a, 0x1234_5678_9ABC_DEF0))
  assert_true(p7_same_seed_equal(g_a, 0))
  assert_true(p7_same_seed_equal(g_a, 0xFFFF_FFFF_FFFF_FFFF))
  // 属性：随机种子与规模下，同种子两次产出逐元素相等。迭代 128 次（≥100）。
  let ok = @infra_pbt.holds_for_all(
    p7_param_gen(),
    fn(p) {
      let gen = fuzz_graph_gen(p.max_n, p.max_edges)
      p7_same_seed_equal(gen, p.seed)
    },
    iters=128,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 7: 生成器同种子确定性（fuzz_graph_nonneg_gen）
///
/// 对任意随机的 `(seed, max_n, max_edges)`，以同一 `seed` 两次驱动
/// `fuzz_graph_nonneg_gen(max_n, max_edges)` 产出逐元素相同的图。
///
/// **Validates: Requirements 5.4, 6.2, 17.7**
test "Feature: championship-v1-upgrade, Property 7: fuzz_graph_nonneg_gen same-seed determinism" {
  // 锚点：固定种子与规模下两次产出严格相等。
  let g_a = fuzz_graph_nonneg_gen(50, 500)
  assert_true(p7_same_seed_equal(g_a, 0x0FED_CBA9_8765_4321))
  assert_true(p7_same_seed_equal(g_a, 0))
  assert_true(p7_same_seed_equal(g_a, 0xFFFF_FFFF_FFFF_FFFF))
  // 属性：随机种子与规模下，同种子两次产出逐元素相等。迭代 128 次（≥100）。
  let ok = @infra_pbt.holds_for_all(
    p7_param_gen(),
    fn(p) {
      let gen = fuzz_graph_nonneg_gen(p.max_n, p.max_edges)
      p7_same_seed_equal(gen, p.seed)
    },
    iters=128,
  )
  assert_true(ok)
}
