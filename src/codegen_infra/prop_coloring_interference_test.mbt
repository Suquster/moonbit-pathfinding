// prop_coloring_interference_test.mbt —— Property 1：着色尊重干涉且分配良构
// （任务 12.3）。
//
// Feature: codegen-infra, Property 1: 着色尊重干涉且分配良构
// **Validates: Requirements 1.4, 1.5**
//
// 性质：对任意随机干涉图与寄存器数 k，`allocate_coloring_briggs` 结果以 Var 为键
// 恰覆盖全部节点、每变量恰一个 Location，且任意干涉边两端若都为 Reg 则编号不同。
// 复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 1: 着色尊重干涉且分配良构
/// **Validates: Requirements 1.4, 1.5**
test "Feature: codegen-infra, Property 1: coloring respects interference and is well-formed" {
  let ok = @infra_pbt.holds_for_all(
    gen_interference_case(),
    fn(pair) {
      let (g, k) = pair
      let alloc = allocate_coloring_briggs(g, k)
      t_alloc_covers(g, alloc) && t_coloring_respects(g, alloc)
    },
    iters=100,
  )
  assert_true(ok)
}
