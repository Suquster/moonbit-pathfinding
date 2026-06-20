// prop_opt_semantics_test.mbt —— 优化保持语义属性测试（task 10.3，覆盖 R7.5）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 12「优化保持语义」：
//
//   对任意良类型 `Expr` `e`，`eval_ml(infer(optimize(e))) == eval_ml(infer(e))`。
//
// 形式化说明：
//   * optimize.mbt（task 10.1）的 `optimize = const_fold ∘ dead_let_elim` 是在
//     `Expr` 上定义的**语义保持**变换：常量折叠的折叠规则与 ml_eval.mbt 的
//     `ml_apply_arith` / `ml_apply_cmp` 逐字一致（除零=0、32 位环绕算术），死
//     `let` 消除依赖 MiniML 的纯性与 `eval_ml` 的全函数性。故优化前后语义等价。
//   * 由 task 1.2 的 `ml_well_typed_expr_gen` 产生的 `Expr` 闭合且良类型，顶层
//     结果类型为 TyInt / TyBool，`infer` 必成功并产出 `VInt` / `VBool`，二者
//     借 `Val` 的派生 `Eq` 忠实可比较。
//   * 优化后的语法树仍良类型（Property 11），故 `infer(optimize(e))` 亦成功；
//     任一路推断失败（理论上不应发生）即视为违反属性（predicate 返回 false）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen()`（闭合且可被 infer 成功推断）。
//   * 复用 task 10.1 `optimize.mbt` 的 `optimize`、task 5.1 `infer.mbt` 的
//     `infer`、task 7.1 `ml_eval.mbt` 的 `eval_ml`。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，迭代 100 次
//     （满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   optimize(Expr) -> Expr                            （optimize.mbt，task 10.1）
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]    （infer.mbt，task 5.1）
//   eval_ml(TExpr) -> Val                             （ml_eval.mbt，task 7.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 12：优化保持语义
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 12: 优化保持语义**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`：优化路径
/// `eval_ml(infer(optimize(e)))` 与原始路径 `eval_ml(infer(e))` 所得 `Val`
/// 相等。复用 @infra_pbt 的 `holds_for_all`，迭代 100 次；任一路 `infer` 失败
/// （理论上不应发生，因生成器与优化均保证良类型）即视为属性破坏。
///
/// **Validates: Requirements 7.5**
test "Feature: mini-compiler, Property 12: 优化保持语义" {
  let ok = @infra_pbt.holds_for_all(
    ml_well_typed_expr_gen(),
    fn(e) {
      // 原始路径：infer 后解释求值。
      let original = match infer(e) {
        Ok((te, _)) => eval_ml(te)
        Err(_) => return false
      }
      // 优化路径：optimize 后 infer 再解释求值。
      let optimized = match infer(optimize(e)) {
        Ok((te2, _)) => eval_ml(te2)
        Err(_) => return false
      }
      original == optimized
    },
    iters=100,
  )
  assert_true(ok)
}
