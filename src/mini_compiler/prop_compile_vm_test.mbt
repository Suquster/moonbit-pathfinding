// prop_compile_vm_test.mbt —— 编译—执行等价（语义保持）属性测试（task 8.4，
// 覆盖 R6.5）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 10「编译—执行等价（语义保持）」：
//
//   对任意良类型 `Expr` `e`，`VM::run(compile_ml(infer(e)))` 与
//   `eval_ml(infer(e))` 所得 `Val` 相等。
//
// 这是字节码编译器（bytecode.mbt，task 8.1 的 `compile_ml`）与栈式虚拟机
// （vm.mbt，task 8.2 的 `VM::run`）相对树遍历解释器（ml_eval.mbt，task 7.1 的
// `eval_ml`）语义保持的可执行见证：编译路径与解释路径对同一良类型程序必产出
// 相等的运行期值。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen` —— 其按目标类型（TyInt / TyBool）自顶向下递归，
//     保证产物闭合、良类型且顶层结果类型为 TyInt / TyBool。
//   * 顶层结果为 TyInt / TyBool（基值）意味着两路结果均为 `VInt` / `VBool`
//     （或由其构成的元组），`VM::run` 对基值/元组的投影**完全忠实**（见
//     vm.mbt 文件头「阻抗匹配」说明，并呼应 task 8.2 备注），故 `==` 比较有意义。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代 100 次
//     （满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]   （infer.mbt，task 5.1）
//   eval_ml(TExpr) -> Val                              （ml_eval.mbt，task 7.1）
//   compile_ml(TExpr) -> Bytecode                      （bytecode.mbt，task 8.1）
//   VM::run(Bytecode, Env) -> Val                      （vm.mbt，task 8.2）
//   ml_env_empty() -> Env                              （ml_eval.mbt，task 7.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 10：编译—执行等价（语义保持）
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 10: 编译—执行等价（语义保持）**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`，先 `infer`
/// 得带类型语法树 `te`，再分别走解释路径 `eval_ml(te)` 与编译路径
/// `VM::run(compile_ml(te), ml_env_empty())`，两者所得 `Val` 应相等。
/// 复用 @infra_pbt 的 `holds_for_all`，迭代 100 次；`infer` 失败（理论上不应
/// 发生，因生成器保证良类型）即视为属性破坏。
///
/// **Validates: Requirements 6.5**
test "Feature: mini-compiler, Property 10: 编译—执行等价（语义保持）" {
  let ok = @infra_pbt.holds_for_all(
    ml_well_typed_expr_gen(),
    fn(e) {
      match infer(e) {
        Ok((te, _)) => {
          let interp = eval_ml(te)
          let compiled = VM::run(compile_ml(te), ml_env_empty())
          interp == compiled
        }
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
