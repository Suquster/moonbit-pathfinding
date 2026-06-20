// pipeline.mbt —— MiniML 统一流水线入口（design.md §12「统一流水线」，覆盖
// R13.1 / R13.2 / R13.3）。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增（R12.4）。它把已实现的各阶段
// （`lex_ml` / `parse_ml` / `optimize` / `infer` / `eval_ml` / `compile_ml` /
// `VM::run`）串成两条端到端路径：
//
//   * `run_interp`  ：解释路径   —— lex → parse →(可选)optimize→ infer → eval_ml。
//   * `run_compiled`：编译—执行路径 —— lex → parse →(可选)optimize→ infer →
//                                       compile_ml → VM::run。
//
// 两路共享前端 `frontend`（lex → parse →(可选)optimize→ infer），仅在尾部对所得
// 良类型 `TExpr` 分派不同后端，从而「两路接受相同的良类型输入」（R13.3）。
//
// ===========================================================================
// 关于「优化」的施加次序（与 design §12 散文叙述的偏差，已记录）
// ===========================================================================
//   design §12 散文把流水线列为「infer → (可选)optimize → eval_ml」。但
//   `optimize`（optimize.mbt）定义在**未标注类型的** `Expr` 上，而 `infer` 接受
//   `Expr` 产出 `TExpr`、`eval_ml` / `compile_ml` 消费 `TExpr`。若在 `infer` 之
//   后再 `optimize`，类型与数据形态不一致（optimize 无法作用于 TExpr）。
//
//   故采用类型一致且语义等价的清晰次序：**先对解析所得 `Expr` 施加 `optimize`，
//   再 `infer`**，即 lex → parse →(可选)optimize→ infer → eval/compile。这正是
//   设计属性 11 / 12（`infer(optimize(e))` / `eval_ml(infer(optimize(e)))`）所
//   刻画的组合方式——优化保持可推断性与语义，故两种次序对最终结果等价，而本次序
//   在类型上自洽。
//
// ===========================================================================
// 短路传播（R13.1 / R13.2）
// ===========================================================================
//   `frontend` 的任一前置阶段返回 `Err(d)` 即立即以该诊断短路，不进入后续阶段；
//   `run_interp` / `run_compiled` 把该诊断包装为 `Failed(d)` 向上传播。诊断来源：
//     * `lex_ml`  → `LexError`（非法字符，R8.1）；
//     * `parse_ml`→ `SyntaxError`（不符合文法 / 顶层残余 token，R8.2）；
//     * `infer`   → `TypeError`（类型冲突或未绑定变量，R8.3 / R8.4）。
//   注：未绑定变量由 `infer` 即报告为 `TypeError`（见 infer.mbt 的 `EVar` 分支），
//   故前端无需另行调用 `scope_check_ml` 即覆盖作用域错误，保持流水线精简。

///|
/// 流水线结果：成功产出的运行期值，或首个短路诊断（design §12）。
///
/// `Val` 与 `Diagnostic` 均 `derive(Eq)`，故本枚举亦可 `derive(Eq)`，便于
/// 端到端两路一致属性测试（Property 16）与单元测试直接断言。
///
/// 采用 `pub(all)`（与本包 `Val` / `Expr` / `Diagnostic` 等一致），使黑盒测试
/// （`*_test.mbt`，属任务 11.2 / 11.3）可直接构造与匹配 `Produced` / `Failed`。
pub(all) enum PipelineResult {
  /// 流水线成功，产出运行期值。
  Produced(Val)
  /// 某阶段失败，携带首个诊断短路上抛。
  Failed(Diagnostic)
} derive(Eq)

///|
/// 共享前端：lex_ml → parse_ml → (可选)optimize → infer，返回良类型 `TExpr`
/// 或首个短路诊断（R13.1 / R13.2 / R13.3）。
///
/// 两路（解释 / 编译）调用同一前端，确保「接受相同的良类型输入」。`optimize`
/// 施加于解析所得 `Expr`（infer 之前，见文件头次序说明）。
fn frontend(src : String, optimize_ : Bool) -> Result[TExpr, Diagnostic] {
  match lex_ml(src) {
    Err(d) => Err(d)
    Ok(tokens) =>
      match parse_ml(tokens) {
        Err(d) => Err(d)
        Ok(e) => {
          let e1 = if optimize_ { optimize(e) } else { e }
          match infer(e1) {
            Err(d) => Err(d)
            Ok((te, _ty)) => Ok(te)
          }
        }
      }
  }
}

///|
/// 解释路径（R13.1 / R13.2）：lex_ml → parse_ml → (可选)optimize → infer →
/// eval_ml。任一前置阶段返回诊断则以 `Failed(d)` 短路；否则对良类型 `TExpr`
/// 树遍历求值，产出 `Produced(val)`。
pub fn run_interp(src : String, optimize? : Bool = false) -> PipelineResult {
  match frontend(src, optimize) {
    Err(d) => Failed(d)
    Ok(te) => Produced(eval_ml(te))
  }
}

///|
/// 编译—执行路径（R13.2 / R13.3）：lex_ml → parse_ml → (可选)optimize → infer →
/// compile_ml → VM::run。与解释路径接受相同的良类型输入；任一前置阶段返回诊断
/// 则以 `Failed(d)` 短路；否则把良类型 `TExpr` 编译为字节码并以栈式虚拟机执行，
/// 产出 `Produced(val)`。
pub fn run_compiled(src : String, optimize? : Bool = false) -> PipelineResult {
  match frontend(src, optimize) {
    Err(d) => Failed(d)
    Ok(te) => Produced(VM::run(compile_ml(te), ml_env_empty()))
  }
}
