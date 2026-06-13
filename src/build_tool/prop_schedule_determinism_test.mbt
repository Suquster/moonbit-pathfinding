// prop_schedule_determinism_test.mbt —— Property 10：调度确定性。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag；同图同 jobs 两次调度逐元素一致
// （在多个 jobs 取值上校验）。

///|
/// 两个批次序列逐元素相等。
fn batches_eq(
  a : Array[Array[Target]],
  b : Array[Array[Target]],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if !targets_eq(a[i], b[i]) {
      return false
    }
  }
  true
}

///|
/// Feature: build-tool, Property 10: 调度确定性
///
/// 对任意无环构建图与同一 `jobs`，两次调用 `schedule` 产出逐元素一致的批次
/// 序列（在 jobs ∈ {0,1,2,3} 上校验）。
///
/// **Validates: Requirements 7.7**
test "Feature: build-tool, Property 10: scheduling determinism" {
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    for jobs in [0, 1, 2, 3] {
      if !batches_eq(schedule(g, jobs), schedule(g, jobs)) {
        return false
      }
    }
    true
  })
  assert_true(ok)
}
