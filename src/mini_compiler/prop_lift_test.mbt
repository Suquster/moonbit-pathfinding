// prop_lift_test.mbt —— 提升保持语义属性测试（task 7.2，覆盖 R1.6）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 1「提升保持语义（of_minilet）」：
//
//   对任意由生成器产生的 MiniLet `Ast`，经 `of_minilet` 提升为 MiniML `Expr`
//   后按 MiniML 语义（`infer` → `eval_ml`）求值所得整数结果，与既有冻结
//   MiniLet 流水线 `eval(check(ast))` 求值所得 `Value` 相等。
//
// 这是「既有 MiniLet 资产一行不改、新增 MiniML 能力旁路扩展」语义一致承诺的
// 可执行见证：`of_minilet` 桥把整数 / 变量 / 算术 / `let` 一一对应地提升到
// MiniML 子集，新路径（HM 推断 + 树遍历解释器）的求值结果应与既有路径逐字
// 一致（R1.6）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的 MiniLet `Ast` 生成器 `minilet_ast_gen`
//     —— 其产物**闭合**（所有变量都被外层 `let` 绑定），故参考路径 `check(ast)`
//     必成功、提升后 `infer` 必成功。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代 100
//     次（满足「每条属性测试 ≥100 迭代」基线）。
//
// 既有冻结 API：check(Ast) -> Result[TypedAst, Diagnostic]、eval(TypedAst) ->
//   Value（Value = IntV(Int)）。新增 API：of_minilet(Ast) -> Expr、
//   infer(Expr) -> Result[(TExpr, Ty), Diagnostic]、eval_ml(TExpr) -> Val
//   （Val = VInt(Int) | VBool(Bool) | VClosure(...) | VTuple(...)）。
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 1：提升保持语义（of_minilet）
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 1: 提升保持语义（of_minilet）**
///
/// 对任意 MiniLet `Ast`，`of_minilet` 提升后按 `infer → eval_ml` 求值的整数
/// 结果，与既有 `eval(check(ast))` 求值的 `Value` 相等。生成器 `minilet_ast_gen`
/// 保证产物闭合，故参考路径 `check(ast)` 与 MiniML 路径 `infer(of_minilet(ast))`
/// 均必成功；任一路径出现意外分支（参考 `check` 报错、`infer` 报错、求值结果
/// 非整数值）即视为真实违例（谓词返回 false 使属性失败）。复用 @infra_pbt 的
/// `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 1.6**
test "Feature: mini-compiler, Property 1: 提升保持语义（of_minilet）" {
  let ok = @infra_pbt.holds_for_all(
    minilet_ast_gen(),
    fn(ast) {
      // 参考结果：既有冻结路径——直接对原始 AST 类型检查并求值。
      // 生成器保证 ast 闭合，故 check 必成功；Value 仅有整数构造子 IntV。
      let reference = match check(ast) {
        Ok(t) =>
          match eval(t) {
            IntV(n) => n
          }
        Err(_) => return false
      }
      // MiniML 路径：提升桥 of_minilet → HM 推断 infer → 树遍历解释器 eval_ml。
      let lifted = of_minilet(ast)
      let ml_result = match infer(lifted) {
        Ok((te, _)) =>
          match eval_ml(te) {
            VInt(m) => m
            // 提升自 MiniLet 的程序求值必为整数；非整数结果视为违例。
            _ => return false
          }
        Err(_) => return false
      }
      // 两条路径所得整数结果须相等（提升保持语义）。
      reference == ml_result
    },
    iters=100,
  )
  assert_true(ok)
}
