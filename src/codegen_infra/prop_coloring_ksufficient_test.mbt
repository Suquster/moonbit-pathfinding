// prop_coloring_ksufficient_test.mbt —— Property 2：k 充足无溢出（任务 12.4）。
//
// Feature: codegen-infra, Property 2: k 充足无溢出
// **Validates: Requirements 1.3, 1.6**
//
// 性质：对任意随机干涉图与不小于其最大度加一的 k，`allocate_coloring_briggs`
// 不产生任何 Spill，全部节点分配为 Reg。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 2: k 充足无溢出
/// **Validates: Requirements 1.3, 1.6**
test "Feature: codegen-infra, Property 2: sufficient k yields no spill" {
  let ok = @infra_pbt.holds_for_all(
    gen_interference_graph(),
    fn(g) {
      let k = t_max_degree(g) + 1
      let alloc = allocate_coloring_briggs(g, k)
      t_count_spills(alloc) == 0 && t_alloc_covers(g, alloc)
    },
    iters=100,
  )
  assert_true(ok)
}
