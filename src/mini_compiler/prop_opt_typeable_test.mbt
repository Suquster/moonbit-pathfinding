// prop_opt_typeable_test.mbt —— 优化保持可推断性属性测试（task 10.2，覆盖 R7.4）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 11「优化保持可推断性」：
//
//   对任意良类型 `Expr` `e`，`optimize(e)` 后仍可被 `infer` 成功推断，
//   且其主类型与优化前**一致**。
//
// 这是 optimize.mbt（task 10.1）「输出仍良类型」承诺的可执行见证：组合管线
// `const_fold ∘ dead_let_elim` 为**语义保持**变换（常量折叠遵循 ml_eval.mbt
// 的逐字语义、死 let 消除依赖 MiniML 纯性与 eval_ml 全函数性），既不会引入
// 类型错误，也不会改变表达式的主类型。
//
// 主类型相等性说明：task 1.2 的良类型生成器以 TyInt / TyBool 为目标自顶向下
// 构造，故所产闭合表达式的顶层主类型恒为**基类型**（TyInt / TyBool，无类型
// 变量）。基类型不含 fresh var 编号，因而优化前后的主类型应**精确相等**
// （`ty1 == ty0`，`Ty` 派生 `Eq`）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen()`（闭合且可被 infer 成功推断）。
//   * 复用 task 10.1 `optimize.mbt` 的 `optimize`，task 5.1 `infer.mbt` 的
//     `infer`。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，迭代 100 次
//     （满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   optimize(Expr) -> Expr                            （optimize.mbt，task 10.1）
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]    （infer.mbt，task 5.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 11：优化保持可推断性
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 11: 优化保持可推断性**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`：`infer(e)`
/// 成功得主类型 `ty0`，且 `infer(optimize(e))` 同样成功并得主类型 `ty1`，满足
/// `ty1 == ty0`。复用 @infra_pbt 的 `holds_for_all`，迭代 100 次；任一推断失败
/// 或主类型不一致即视为属性破坏（谓词返回 false 使属性失败）。
///
/// **Validates: Requirements 7.4**
test "Feature: mini-compiler, Property 11: 优化保持可推断性" {
  let ok = @infra_pbt.holds_for_all(
    ml_well_typed_expr_gen(),
    fn(e) {
      match infer(e) {
        Ok((_, ty0)) =>
          match infer(optimize(e)) {
            Ok((_, ty1)) => ty1 == ty0
            Err(_) => false
          }
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
