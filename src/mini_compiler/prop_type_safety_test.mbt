// prop_type_safety_test.mbt —— 良类型不卡住（类型可靠性）属性测试（task 7.4,
// 覆盖 R5.8）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 9「良类型不卡住（类型可靠性）」：
//
//   对任意良类型 `Expr`，`eval_ml` 要么产出一个 `Val`、要么按除零等全函数约定
//   终止，而不进入无规则可用的卡住状态。
//
// 关于「不卡住」在 MoonBit 中的可观测形式（与 design.md §「全函数求值」一致）：
//   * ml_eval.mbt（task 6.x）的 `eval_ml` 是**全函数**：环境为不可变 `Env`、
//     变量经 `infer`/作用域检查后必有绑定、除零定义为 `0`、逻辑不短路且无副作用。
//     它**永不抛错、永远终止并返回一个 `Val`**——因此 MoonBit 中不存在「无规则
//     可用的运行期卡住」这一显式的失败状态。
//   * 于是「不卡住」的有意义且可观测的见证是**进展（progress）+ 保持
//     （preservation）的合取**：对每个良类型 `Expr`，`infer` 必成功，且
//     `eval_ml` 产出的 `Val` 的**运行期形状与 `infer` 推断出的主类型一致**：
//       - 主类型 `TyInt`   ⇒ 结果为 `VInt`
//       - 主类型 `TyBool`  ⇒ 结果为 `VBool`
//       - 主类型 `TyFun`   ⇒ 结果为 `VClosure`
//       - 主类型 `TyTuple` ⇒ 结果为 `VTuple`，且分量个数与类型分量个数一致
//     这恰好刻画了类型可靠性（soundness）：不会出现「类型说是整数、求值却得到
//     闭包」之类的卡住 / 形状错配状态。
//   * `TyVar` 不会作为生成器（`ml_well_typed_expr_gen`，仅以 TyInt / TyBool 为
//     目标自顶向下构造）所产闭合表达式的主类型出现；为稳健起见，若主类型为
//     `TyVar` 则接受任意 `Val`（返回 true），以避免误判。
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
// 形状一致性判定：运行期 `Val` 与推断主类型 `Ty` 是否相符（progress + preservation）
// ---------------------------------------------------------------------------

///|
/// 判定求值所得 `Val` 的运行期形状是否与推断主类型 `Ty` 一致——即类型可靠性的
/// 可观测见证（无卡住 / 无形状错配）：
///   * `(VInt, TyInt)`     ⇒ true
///   * `(VBool, TyBool)`   ⇒ true
///   * `(VClosure, TyFun)` ⇒ true
///   * `(VTuple, TyTuple)` ⇒ 分量个数一致即可（长度足以见证形状；类型已由 infer
///     保证逐分量良类型）
///   * 主类型为 `TyVar`（闭合良类型表达式不应出现）⇒ 接受任意 `Val`，避免误判
///   * 其余组合 ⇒ false（形状错配，违反类型可靠性）
fn shape_matches(v : Val, ty : Ty) -> Bool {
  match (v, ty) {
    (VInt(_), TyInt) => true
    (VBool(_), TyBool) => true
    (VClosure(_, _, _), TyFun(_, _)) => true
    (VTuple(vs), TyTuple(ts)) => vs.length() == ts.length()
    // 闭合良类型表达式的主类型不应为裸类型变量；稳健起见接受任意 Val。
    (_, TyVar(_)) => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Property 9：良类型不卡住（类型可靠性）
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 9: 良类型不卡住（类型可靠性）**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`：`infer(e)` 成功
/// 得到带类型标注 `te` 与主类型 `ty`，且 `eval_ml(te)` 产出的 `Val` 的运行期
/// 形状与 `ty` 一致（见 `shape_matches`）——即求值不进入卡住 / 形状错配状态。
/// 复用 @infra_pbt 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 5.8**
test "Feature: mini-compiler, Property 9: 良类型不卡住（类型可靠性）" {
  let ok = @infra_pbt.holds_for_all(
    ml_well_typed_expr_gen(),
    fn(e) {
      match infer(e) {
        // 良类型表达式必可成功推断；求值所得 Val 的形状须与主类型一致。
        Ok((te, ty)) => {
          let v = eval_ml(te)
          shape_matches(v, ty)
        }
        // 良类型表达式不应推断失败；失败即违反属性。
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
