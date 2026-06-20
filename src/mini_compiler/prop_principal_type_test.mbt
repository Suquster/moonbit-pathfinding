// prop_principal_type_test.mbt —— 主类型存在性属性测试（task 5.2，覆盖 R4.8）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 6「主类型存在性」：
//
//   对任意良类型 `Expr`，`infer` 成功并返回一个类型。
//
// 这是 infer.mbt（task 5.1，Hindley-Milner Algorithm W）正确性的可执行见证：
// 由 task 1.2 的良类型生成器按目标类型自顶向下构造的闭合表达式，必然落在
// MiniML 类型系统的良类型片段内，因而 Algorithm W 必能为其求出主类型（principal
// type），即 `infer` 返回 `Ok((TExpr, Ty))` 而非诊断。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen` —— 其按目标类型（TyInt / TyBool）自顶向下递归，
//     并以带类型环境保证产物闭合且良类型，恰好覆盖本属性的输入空间。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代
//     100 次（满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]   （infer.mbt，task 5.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 6：主类型存在性
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 6: 主类型存在性**
///
/// 对任意由 `ml_well_typed_expr_gen` 产生的良类型闭合 `Expr` `e`，
/// `infer(e)` 应返回 `Ok(_)`（即成功推断出主类型），而非 `Err(_)`（诊断）。
/// 复用 @infra_pbt 的 `holds_for_all`，迭代 100 次；`infer` 返回 `Err` 即视为
/// 属性破坏（谓词返回 false 使属性失败）。
///
/// **Validates: Requirements 4.8**
test "Feature: mini-compiler, Property 6: 主类型存在性" {
  let ok = @infra_pbt.holds_for_all(
    ml_well_typed_expr_gen(),
    fn(e) {
      match infer(e) {
        Ok(_) => true
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
