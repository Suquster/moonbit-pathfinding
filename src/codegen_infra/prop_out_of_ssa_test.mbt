// prop_out_of_ssa_test.mbt —— Property 12：out-of-SSA 与 SSA 语义等价（任务 6.3）。
//
// Feature: codegen-infra, Property 12: out-of-SSA 与 SSA 语义等价
// **Validates: Requirements 7.1, 7.2, 7.4, 7.5**
//
// 性质：对任意随机 SSA 程序、初始赋值与任一 entry-rooted 路径，沿该路径解释执行
// `destruct_ssa` 后的程序所得可达输出与按 SSA 语义沿同一路径求值 φ 一致（以参考
// 解释器 `evaluate` 为 oracle）；且析构后程序不含任何 φ。复用 holds_for_all。

///|
/// Feature: codegen-infra, Property 12: out-of-SSA 与 SSA 语义等价
/// **Validates: Requirements 7.1, 7.2, 7.4, 7.5**
test "Feature: codegen-infra, Property 12: out-of-SSA is semantically equivalent" {
  let ok = @infra_pbt.holds_for_all(
    gen_ssa_eval_case(),
    fn(triple) {
      let (p, init, path) = triple
      let before = evaluate(p, init, path)
      let d = destruct_ssa(p)
      let after = evaluate(d, init, path)
      t_outputs_equal(before, after) && d.phis.length() == 0
    },
    iters=100,
  )
  assert_true(ok)
}
