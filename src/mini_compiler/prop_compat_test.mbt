// prop_compat_test.mbt —— MiniLet 向后兼容属性测试（task 1.3，覆盖 R12.7）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 15「MiniLet 向后兼容」：
//
//   对任意 MiniLet `Ast`，经既有冻结流水线「打印 → 重新词法 → 重新语法 →
//   类型检查 → 求值」所得 `Value`，应与「直接类型检查 → 求值」所得 `Value`
//   逐字相等，且整条往返路径上各阶段均不产生诊断（无 Err）。
//
// 这正是「既有 MiniLet 资产一行不改、新增能力旁路扩展」向后兼容承诺的可执行
// 见证：`print_ast` 的完全括号化输出可被无歧义地 `lex → parse` 还原回同一
// 结构，且 `check`/`eval` 行为不变（R12.7）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的 MiniLet `Ast` 生成器 `minilet_ast_gen`
//     —— 其产物**闭合**（所有变量都被外层 `let` 绑定）且「打印再解析」往返
//     安全，故 `check` 必成功、往返各阶段均应为 `Ok`。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代 100
//     次（满足「每条属性测试 ≥100 迭代」基线）。
//
// 既有冻结 API（签名与逐字行为均不改动）：
//   lex(String) -> Result[Array[Token], Diagnostic]
//   parse(Array[Token]) -> Result[Ast, Diagnostic]
//   check(Ast) -> Result[TypedAst, Diagnostic]
//   eval(TypedAst) -> Value
//   print_ast(Ast) -> String
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 15：MiniLet 向后兼容
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 15: MiniLet 向后兼容**
///
/// 对任意 MiniLet `Ast`，`eval(check(parse(lex(print_ast(ast)))))` 与
/// `eval(check(ast))` 相等，且中途无诊断（每个 `lex` / `parse` / `check`
/// 阶段均返回 `Ok`）。生成器 `minilet_ast_gen` 保证产物闭合且往返安全，故参考
/// 路径 `check(ast)` 必成功；往返路径任一阶段返回 `Err` 即视为真实回归（谓词
/// 返回 false 使属性失败）。复用 @infra_pbt 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 12.7**
test "Feature: mini-compiler, Property 15: MiniLet 向后兼容" {
  let ok = @infra_pbt.holds_for_all(
    minilet_ast_gen(),
    fn(ast) {
      // 参考结果：直接对原始 AST 类型检查并求值。
      // 生成器保证 ast 闭合，故 check 必成功。
      let reference = match check(ast) {
        Ok(t) => eval(t)
        Err(_) => return false
      }
      // 往返路径：打印 → 重新词法 → 重新语法 → 类型检查 → 求值。
      // 任一阶段返回 Err（产生诊断）即破坏向后兼容承诺。
      let tokens = match lex(print_ast(ast)) {
        Ok(ts) => ts
        Err(_) => return false
      }
      let parsed = match parse(tokens) {
        Ok(a) => a
        Err(_) => return false
      }
      let roundtrip = match check(parsed) {
        Ok(t) => eval(t)
        Err(_) => return false
      }
      // 两条路径所得 Value 须逐字相等。
      reference == roundtrip
    },
    iters=100,
  )
  assert_true(ok)
}
