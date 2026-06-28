// prop_coalescing_test.mbt —— Property 3：保守合并安全性（任务 13.3）。
//
// Feature: codegen-infra, Property 3: 保守合并安全性
// **Validates: Requirements 2.2, 2.4, 2.5**
//
// 性质：对任意随机干涉图、传送候选集与 k，在 Briggs 保守判据下执行 coalesce 后
// 再分配，仍满足干涉不变量，且溢出数量不大于合并前（合并不引入新溢出）；互相
// 干涉的变量对不被合并（由 coalesce 仅合并非干涉对保证）。合并前后均以
// `allocate_coloring_briggs` 分配比较。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 3: 保守合并安全性
/// **Validates: Requirements 2.2, 2.4, 2.5**
test "Feature: codegen-infra, Property 3: conservative coalescing is safe" {
  let ok = @infra_pbt.holds_for_all(
    gen_coalesce_case(),
    fn(triple) {
      let (g, moves, k) = triple
      let merged = coalesce(g, moves, k, strategy=Briggs)
      let alloc_after = allocate_coloring_briggs(merged, k)
      // (1) 合并后再分配满足干涉不变量。
      if !t_coloring_respects(merged, alloc_after) {
        return false
      }
      // (2) 溢出数量不大于合并前。
      let alloc_before = allocate_coloring_briggs(g, k)
      if t_count_spills(alloc_after) > t_count_spills(alloc_before) {
        return false
      }
      true
    },
    iters=100,
  )
  assert_true(ok)
}
