// prop_pipeline_test.mbt —— 端到端两路一致属性测试（task 11.2，覆盖 R13.4）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 16「端到端两路一致」：
//
//   对任意良类型 MiniML 源串 `src`，解释路径 `run_interp(src)` 与编译—执行
//   路径 `run_compiled(src)` 产出**相等**的结果（`PipelineResult` 派生 `Eq`）。
//
// 这是 pipeline.mbt（task 11.1）两路共享前端、仅尾部分派后端这一设计的可执行
// 见证：两路接受相同的良类型输入（lex → parse → infer 得同一 `TExpr`），随后
// 分别经 `eval_ml`（树遍历解释）与 `compile_ml` + `VM::run`（字节码执行）求值。
// 由于 VM 与解释器在基值 / 元组结果上完全忠实（vm.mbt 的 reify 说明），二者
// 必产出逐位相等的 `Val`，故 `Produced(v)` 两侧相等。
//
// 输入空间构造：由 task 1.2 的良类型 `Expr` 生成器 `ml_well_typed_expr_gen()`
// 产生闭合、可被 `infer` 成功推断的 `Expr`，再经 `print_expr`（ml_printer.mbt）
// 打印为源串。该源串完全括号化、往返安全，重新 `lex → parse → infer` 后仍是
// 同一良类型程序，故两路前端均成功、尾部后端均产出可比较的 `Val`。生成器目标
// 类型恒为 TyInt / TyBool（顶层基类型），保证 VM 与解释器结果忠实可比较。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的良类型 `Expr` 生成器
//     `ml_well_typed_expr_gen()`，并以 `print_expr` 映射为 `Gen[String]`。
//   * 复用 task 11.1 `pipeline.mbt` 的 `run_interp` / `run_compiled` 与
//     `PipelineResult`（派生 `Eq`）。
//   * 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Gen::new` / `Gen::generate` /
//     `holds_for_all` 不变量模板，迭代 100 次（满足「每条属性测试 ≥100 迭代」
//     基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   run_interp(String, optimize~ : Bool = false) -> PipelineResult   （pipeline.mbt）
//   run_compiled(String, optimize~ : Bool = false) -> PipelineResult （pipeline.mbt）
//   print_expr(Expr) -> String                                        （ml_printer.mbt）
//   ml_well_typed_expr_gen() -> @infra_pbt.Gen[Expr]                  （ml_gen_test.mbt）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 16：端到端两路一致
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 16: 端到端两路一致**
///
/// 对任意由 `ml_well_typed_expr_gen` 经 `print_expr` 生成的良类型 MiniML 源串
/// `src`：解释路径 `run_interp(src)` 与编译—执行路径 `run_compiled(src)` 产出
/// 相等的 `PipelineResult`（二者均为 `Produced(v)` 且 `v` 逐位相等）。复用
/// @infra_pbt 的 `holds_for_all`，迭代 100 次；任一源串使两路结果不等即视为
/// 属性破坏（谓词返回 false 使属性失败）。
///
/// **Validates: Requirements 13.4**
test "Feature: mini-compiler, Property 16: 端到端两路一致" {
  // 由良类型 Expr 经 print_expr 派生 Gen[String]：单次采样生成一个良类型
  // 表达式并打印为往返安全的源串。
  let src_gen = @infra_pbt.Gen::new(fn(rng) {
    print_expr(ml_well_typed_expr_gen().generate(rng))
  })
  let ok = @infra_pbt.holds_for_all(
    src_gen,
    fn(src) { run_interp(src) == run_compiled(src) },
    iters=100,
  )
  assert_true(ok)
}
