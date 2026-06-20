// prop_eval_determinism_test.mbt —— 求值确定性属性测试（task 7.3，覆盖 R5.7）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 8「求值确定性」：
//
//   对任意良类型 `Expr`，对同一程序重复 `eval_ml` 得到**相等**结果。
//
// 形式化说明：
//   * ml_eval.mbt（task 6.x）的 `eval_ml` 是不依赖任何可变全局状态的纯树遍历
//     解释器：环境为不可变 `Env`，算术为 32 位环绕、除零定义为 `0`，逻辑运算
//     不短路且无副作用——故对同一带类型标注 `TExpr` 求值是**确定的全函数**：
//     重复求值必得逐字相等的 `Val`（R5.7 / R5.8）。
//   * 由 task 1.2 的 `ml_well_typed_expr_gen` 产生的 `Expr` 闭合且良类型，必能
//     被 `infer` 成功推断（`Ok((te, _))`）；随后对同一 `te` 调用两次 `eval_ml`
//     的结果以 `Val` 的派生 `Eq` 比较，二者必然相等。
//   * 若良类型表达式推断失败（不应发生）则视为违反属性（predicate 返回 false）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen()`（闭合且可被 infer 成功推断）。
//   * 复用 task 5.1 `infer.mbt` 的 `infer`，task 6.x `ml_eval.mbt` 的 `eval_ml`。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，迭代 100 次
//     （满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]   （infer.mbt，task 5.1）
//   eval_ml(TExpr) -> Val                             （ml_eval.mbt，task 6.x）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 8：求值确定性
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 8: 求值确定性**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`：`infer(e)` 成功
/// 得到带类型标注 `te`，且对同一 `te` 重复 `eval_ml` 得到相等的 `Val`
/// （`eval_ml(te) == eval_ml(te)`）。复用 @infra_pbt 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 5.7**
test "Feature: mini-compiler, Property 8: 求值确定性" {
  let gen = ml_well_typed_expr_gen()
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(e) {
      match infer(e) {
        // 良类型表达式必可成功推断；对同一 TExpr 两次求值必得相等结果。
        Ok((te, _)) => eval_ml(te) == eval_ml(te)
        // 良类型表达式不应推断失败；失败即违反属性。
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
