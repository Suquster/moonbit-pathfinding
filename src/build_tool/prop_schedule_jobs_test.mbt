// prop_schedule_jobs_test.mbt —— Property 11：并行度约束。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag；对 jobs ∈ {1,2,3} 校验每批长度
// 不超过 jobs。

///|
/// Feature: build-tool, Property 11: 并行度约束
///
/// 对任意无环构建图与 `jobs > 0`，`schedule` 产出的每个并行批次的目标数都
/// 不超过 `jobs`。
///
/// **Validates: Requirements 7.2**
test "Feature: build-tool, Property 11: jobs-bound respected" {
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    for jobs in [1, 2, 3] {
      for batch in schedule(g, jobs) {
        if batch.length() > jobs {
          return false
        }
      }
    }
    true
  })
  assert_true(ok)
}
