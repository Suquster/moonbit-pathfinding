// prop_ml_roundtrip_test.mbt —— MiniML 解析 / 打印往返属性测试（task 2.4，
// 覆盖 R2.5）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 2「MiniML 解析 / 打印往返」：
//
//   对任意合法 `Expr` e，对 `print_expr(e)` 重新执行 `lex_ml → parse_ml`
//   所得 `Expr` 在去除 span 后，与 `erase_span(e)` 相等。
//
// 这是 ml_printer（task 2.3，完全括号化打印）与 ml_lexer / ml_parser
// （task 2.1 / 2.2）协同正确性的可执行见证：打印器的完全括号化输出可被
// 词法 / 语法分析无歧义地还原回同一树形（与运算符优先级 / 结合性无关）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的 MiniML `Expr` 生成器 `ml_expr_gen`
//     —— 其覆盖全部非元组构造子，可能产出开放（含自由变量）/ 不良类型的
//     表达式。这对纯语法层的「解析 / 打印往返」完全适用：本属性不涉及
//     类型推断或作用域检查，自由变量只作为 `EVar` 节点原样往返即可。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代
//     100 次（满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   print_expr(Expr) -> String           （ml_printer.mbt，task 2.3）
//   erase_span(Expr) -> Expr             （ml_printer.mbt，task 2.3）
//   lex_ml(String) -> Result[Array[MlToken], Diagnostic]   （ml_lexer.mbt）
//   parse_ml(Array[MlToken]) -> Result[Expr, Diagnostic]   （ml_parser.mbt）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 2：MiniML 解析 / 打印往返
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 2: MiniML 解析 / 打印往返**
///
/// 对任意由 `ml_expr_gen` 产生的合法 `Expr` e，令 `s = print_expr(e)`，则
/// `lex_ml(s)` 与 `parse_ml(tokens)` 均应成功，且解析所得 `Expr` 去 span 后
/// 与 `erase_span(e)` 相等。两侧都做 `erase_span` 以仅比较树形（忽略源码
/// 跨度差异），与设计的往返不变式一致。复用 @infra_pbt 的 `holds_for_all`，
/// 迭代 100 次；任一阶段返回 `Err` 即视为往返破坏（谓词返回 false 使属性失败）。
///
/// **Validates: Requirements 2.5**
test "Feature: mini-compiler, Property 2: MiniML 解析 / 打印往返" {
  let ok = @infra_pbt.holds_for_all(
    ml_expr_gen(),
    fn(e) {
      // 打印为 MiniML 源串（完全括号化，消除优先级 / 结合性歧义）。
      let s = print_expr(e)
      // 重新词法分析：失败即往返破坏。
      let tokens = match lex_ml(s) {
        Ok(ts) => ts
        Err(_) => return false
      }
      // 重新语法分析：失败即往返破坏。
      let parsed = match parse_ml(tokens) {
        Ok(a) => a
        Err(_) => return false
      }
      // 去 span 后比较树形：解析所得与原 Expr 应等价。
      erase_span(parsed) == erase_span(e)
    },
    iters=100,
  )
  assert_true(ok)
}
