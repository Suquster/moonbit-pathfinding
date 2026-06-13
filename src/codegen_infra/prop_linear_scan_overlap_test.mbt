// prop_linear_scan_overlap_test.mbt —— Property 4：线性扫描尊重重叠（任务 14.2）。
//
// Feature: codegen-infra, Property 4: 线性扫描尊重重叠
// **Validates: Requirements 3.4**
//
// 性质：对任意随机活跃区间集合与 k，`allocate_linear_scan` 中任意两个区间重叠
// 的变量若都被分配为 Reg 则编号不同。复用既有 gen_linear_scan_case 生成器与既有
// `allocate_linear_scan`（行为冻结）。复用 holds_for_all（100 迭代）。

///|
/// 两个活跃区间是否重叠。
fn t_iv_overlap(a : LiveInterval, b : LiveInterval) -> Bool {
  a.start <= b.end && b.start <= a.end
}

///|
/// Feature: codegen-infra, Property 4: 线性扫描尊重重叠
/// **Validates: Requirements 3.4**
test "Feature: codegen-infra, Property 4: linear scan respects overlap" {
  let ok = @infra_pbt.holds_for_all(
    gen_linear_scan_case(),
    fn(pair) {
      let (intervals, k) = pair
      let alloc = allocate_linear_scan(intervals, k)
      for i in 0..<intervals.length() {
        for j in (i + 1)..<intervals.length() {
          let a = intervals[i]
          let b = intervals[j]
          if t_iv_overlap(a, b) {
            match (alloc.get(a.variable), alloc.get(b.variable)) {
              (Some(Reg(x)), Some(Reg(y))) => if x == y { return false }
              _ => ()
            }
          }
        }
      }
      true
    },
    iters=100,
  )
  assert_true(ok)
}
