// prop_linear_scan_consistency_test.mbt —— Property 5：线性扫描与图着色无溢出
// 一致（任务 14.3）。
//
// Feature: codegen-infra, Property 5: 线性扫描与图着色无溢出一致
// **Validates: Requirements 3.3, 3.5**
//
// 性质：对任意最大重叠度 ≤ k 的随机活跃区间集，由 `interference_from_intervals`
// 导出的干涉图经 `allocate_coloring_briggs` 与对其本身的 `allocate_linear_scan`，
// 二者在「是否需要溢出」结论上一致——均判定为无需溢出。以 `allocation_has_spill`
// 比较。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 5: 线性扫描与图着色无溢出一致
/// **Validates: Requirements 3.3, 3.5**
test "Feature: codegen-infra, Property 5: linear scan and coloring agree on no-spill" {
  let ok = @infra_pbt.holds_for_all(
    gen_bounded_overlap_intervals(),
    fn(pair) {
      let (intervals, k) = pair
      let g = interference_from_intervals(intervals)
      let by_coloring = allocate_coloring_briggs(g, k)
      let by_linear = allocate_linear_scan(intervals, k)
      // 均判无需溢出（结论一致）。
      not(allocation_has_spill(by_coloring)) &&
      not(allocation_has_spill(by_linear))
    },
    iters=100,
  )
  assert_true(ok)
}
