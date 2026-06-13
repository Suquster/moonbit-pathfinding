// prop_gvn_test.mbt —— Property 14：GVN 保持语义（任务 9.3）。
//
// Feature: codegen-infra, Property 14: GVN 保持语义
// **Validates: Requirements 9.4, 9.5**
//
// 性质：对任意随机 SSA 程序、初始赋值与任一 entry-rooted 路径，`gvn`（含强化
// DCE 与复制传播）变换前后程序在所有输出上的解释执行结果一致（以参考解释器
// `evaluate` 为 oracle）；且变换后保持 SSA 单赋值不变量。复用 holds_for_all。

///|
/// Feature: codegen-infra, Property 14: GVN 保持语义
/// **Validates: Requirements 9.4, 9.5**
test "Feature: codegen-infra, Property 14: GVN preserves semantics" {
  let ok = @infra_pbt.holds_for_all(
    gen_ssa_eval_case(),
    fn(triple) {
      let (p, init, path) = triple
      let before = evaluate(p, init, path)
      let transformed = gvn(p)
      let after = evaluate(transformed, init, path)
      t_outputs_equal(before, after) &&
      t_all_distinct(t_def_version_ids(transformed))
    },
    iters=100,
  )
  assert_true(ok)
}
