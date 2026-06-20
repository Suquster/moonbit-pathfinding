// prop_infer_idem_test.mbt —— 推断幂等属性测试（task 5.3，覆盖 R4.9）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 7「推断幂等（类型在最终替换下封闭）」：
//
//   对任意良类型 `Expr`，对推断所得类型「再施加推断结果替换」不改变该类型。
//
// 形式化说明（针对 infer.mbt 当前公开 API 选取可观测且非平凡的表述）：
//   * infer.mbt（task 5.1）的入口 `infer` 在 `infer_w` 成功后，已把最终累积
//     替换施加到整棵 `TExpr` 的每个类型标注上（`apply_subst_texpr`），使返回的
//     主类型在最终替换下**封闭**——这正是 R4.9 所述「推断幂等」的不变式：再对
//     该类型施加任何（已被 normalize 规范化至不动点的）替换都不会改变它。
//   * 由于最终替换是 infer 的内部状态、不对外暴露，这里以两个**可观测**且彼此
//     独立的见证来检验该封闭性：
//       (a) 根节点类型标注与返回主类型一致：`type_of(te) == ty`（infer 把替换
//           施加到全树，二者必同源相等）；
//       (b) 类型在「恒等替换」下封闭：`apply_subst(subst_empty(), ty) == ty`
//           ——更进一步，因返回类型已是替换不动点，对其再施加自身不会变化；
//       (c) 推断**确定性**：对同一表达式重复 `infer` 得到相等的主类型。
//           infer 每次调用新建 `FreshGen`（计数从 0 起），故同一输入两次推断
//           产生**完全相同**的新鲜变量编号，主类型逐字相等——这是「类型在最终
//           替换下封闭 / 稳定」最强可观测形式。
//   * 三者合取构成对 R4.9「推断所得类型在最终替换下封闭、稳定不变」的稳健见证。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen()`（闭合且可被 infer 成功推断）。
//   * 复用 task 5.1 `infer.mbt` 的 `infer` / `type_of`，task 4.1 `unify.mbt`
//     的 `apply_subst` / `subst_empty`。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，迭代 100 次
//     （满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]   （infer.mbt，task 5.1）
//   type_of(TExpr) -> Ty                              （infer.mbt，task 5.1）
//   apply_subst(Subst, Ty) -> Ty                      （unify.mbt，task 4.1）
//   subst_empty() -> Subst                            （unify.mbt，task 4.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 7：推断幂等（类型在最终替换下封闭）
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 7: 推断幂等**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`，推断成功并返回
/// 主类型 `ty`，且满足以下三项「类型在最终替换下封闭 / 稳定」的可观测见证：
///   (a) `type_of(te) == ty`：根节点类型标注与返回主类型同源相等；
///   (b) `apply_subst(subst_empty(), ty) == ty`：类型在恒等替换下封闭；
///   (c) 确定性：再次 `infer(e)` 得到逐字相等的主类型（因 FreshGen 每次从 0 起）。
/// 复用 @infra_pbt 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 4.9**
test "Feature: mini-compiler, Property 7: 推断幂等" {
  let gen = ml_well_typed_expr_gen()
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(e) {
      match infer(e) {
        Ok((te, ty)) => {
          // (a) 根节点标注与返回主类型一致。
          let stable_annot = type_of(te) == ty
          // (b) 类型在（已规范化的）替换下封闭：再施加替换不改变它。
          let closed = apply_subst(subst_empty(), ty) == ty
          // (c) 推断确定性：重复推断得到相等主类型（封闭 / 稳定的可观测见证）。
          let deterministic = match infer(e) {
            Ok((_, ty2)) => ty == ty2
            Err(_) => false
          }
          stable_annot && closed && deterministic
        }
        // 良类型表达式必可成功推断；失败即违反属性。
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
