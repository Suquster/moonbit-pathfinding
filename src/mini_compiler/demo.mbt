// demo.mbt —— 旗舰端到端示例（design.md §13「旗舰端到端示例」，覆盖 R9.1 /
// R9.2 / R9.3 / R9.4）。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增（R12.4）。它提供两段贯穿文档
// 与基准的 MiniML 示例程序（阶乘、斐波那契，均含 `let rec` 递归、一等函数、`if`
// 与比较运算，R9.1），并以 `run_demo` 跑通完整链路：
//
//   lex_ml → parse_ml → infer → 优化 → eval_ml      （解释路径）
//   lex_ml → parse_ml → infer → 优化 → compile_ml → VM::run （编译—执行路径）
//
// 各阶段产物收敛进 `DemoTrace`：推断主类型（R9.4）、优化后形态（R9.2）、解释
// 结果（R9.2）与 VM 结果（R9.3）。两示例均为合法良类型输入，故 `run_demo` 假定
// 各阶段成功，遇意外失败以 `abort` 携带明确消息中止（便于定位回归）。
//
// ===========================================================================
// 关于「优化」的施加次序（与 pipeline.mbt 一致）
// ===========================================================================
//   `optimize` 定义在未标注类型的 `Expr` 上，而 `infer` 接受 `Expr` 产出 `TExpr`，
//   `eval_ml` / `compile_ml` 消费 `TExpr`。故采用类型自洽且语义等价的次序：先对
//   解析所得 `Expr` 施加 `optimize`，再 `infer` 出 `TExpr`，最后分派解释 / 编译两
//   路。`principal_type` 取**原始程序**的推断主类型（R9.4 所声明的主类型），
//   `optimized_form` 为 `print_expr(optimize(e))`（R9.2 的「优化后形态」）。
//   解释与 VM 两路均消费优化后的良类型 `TExpr`，由设计属性 12（优化保持语义）与
//   属性 10（编译—执行等价）保证 `interp_result == vm_result`。

///|
/// 阶乘示例（`let rec` + `if` + 比较 + 一等函数 + 应用）。`fact 5 = 120`。
pub let demo_factorial_src : String = "let rec fact = fun n -> if n <= 1 then 1 else n * fact (n - 1) in fact 5"

///|
/// 斐波那契示例（`let rec` + `if` + 比较 + 应用）。`fib 10 = 55`。
pub let demo_fib_src : String = "let rec fib = fun n -> if n <= 1 then n else fib (n - 1) + fib (n - 2) in fib 10"

///|
/// 端到端各阶段产物（R9.2 / R9.3 / R9.4）。
///
/// - `principal_type`：原始程序经 `infer` 推断的主类型（R9.4）。
/// - `optimized_form`：`print_expr(optimize(parsed))`，即优化后语法树的源串形态
///   （R9.2 的「优化后形态」）。
/// - `interp_result`：解释路径 `eval_ml(infer(optimize(e)))` 的运行期值（R9.2）。
/// - `vm_result`：编译—执行路径 `VM::run(compile_ml(infer(optimize(e))))` 的运行
///   期值（R9.3）。
///
/// `derive(Eq)` 便于单元测试（任务 12.2）直接断言两路结果一致且与文档声明相符。
pub(all) struct DemoTrace {
  principal_type : Ty
  optimized_form : String
  interp_result : Val
  vm_result : Val
} derive(Eq)

///|
/// 跑通示例源串并返回各阶段产物（R9.2 / R9.3 / R9.4）。
///
/// 链路：`lex_ml → parse_ml → infer`（取主类型）→ `optimize` →
/// `infer`（对优化后程序重新标注类型）→ `eval_ml`（解释）与
/// `compile_ml → VM::run`（编译执行）。
///
/// 两示例均为合法良类型程序，故各阶段假定成功；遇意外失败以 `abort` 携带阶段信
/// 息中止（防止静默吞错，便于回归定位）。
pub fn run_demo(src : String) -> DemoTrace {
  // 阶段 1：词法分析。
  let tokens = match lex_ml(src) {
    Ok(ts) => ts
    Err(d) => abort("run_demo: lex_ml failed: " + d.msg)
  }
  // 阶段 2：语法分析。
  let e = match parse_ml(tokens) {
    Ok(expr) => expr
    Err(d) => abort("run_demo: parse_ml failed: " + d.msg)
  }
  // 阶段 3：对原始程序推断主类型（R9.4）。
  let principal_type = match infer(e) {
    Ok((_te, ty)) => ty
    Err(d) => abort("run_demo: infer failed: " + d.msg)
  }
  // 阶段 4：优化，并记录优化后形态（R9.2）。
  let optimized = optimize(e)
  let optimized_form = print_expr(optimized)
  // 阶段 5：对优化后程序重新推断以获得良类型 `TExpr`（供两路消费）。
  let te_opt = match infer(optimized) {
    Ok((te, _ty)) => te
    Err(d) => abort("run_demo: infer(optimize) failed: " + d.msg)
  }
  // 阶段 6：解释路径求值（R9.2）。
  let interp_result = eval_ml(te_opt)
  // 阶段 7：编译—执行路径（R9.3）。
  let vm_result = VM::run(compile_ml(te_opt), ml_env_empty())
  DemoTrace::{ principal_type, optimized_form, interp_result, vm_result }
}
