// prop_sccp_test.mbt —— Property 13：SCCP 保持语义（任务 8.3）。
//
// Feature: codegen-infra, Property 13: SCCP 保持语义
// **Validates: Requirements 8.4, 8.5**
//
// 性质：对任意随机 SSA 程序、初始赋值与任一 entry-rooted 路径，`sccp` 变换前后
// 程序在所有可达输出上的解释执行结果一致（以参考解释器 `evaluate` 为 oracle）；
// 且变换后保持 SSA 单赋值不变量。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 13: SCCP 保持语义
/// **Validates: Requirements 8.4, 8.5**
test "Feature: codegen-infra, Property 13: SCCP preserves semantics" {
  let ok = @infra_pbt.holds_for_all(
    gen_ssa_eval_case(),
    fn(triple) {
      let (p, init, path) = triple
      let before = evaluate(p, init, path)
      let transformed = sccp(p)
      let after = evaluate(transformed, init, path)
      t_outputs_equal(before, after) &&
      t_all_distinct(t_def_version_ids(transformed))
    },
    iters=100,
  )
  assert_true(ok)
}
