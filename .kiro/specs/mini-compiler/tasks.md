# 实现计划（Implementation Plan）：Mini_Compiler（方向一 · 旗舰深化）

## 概述（Overview）

本计划把 `design.md` 的旁路增量架构落地为一系列可执行、聚焦编码的任务，严格遵循「增量式、向后兼容的旁路扩展」策略：

- **冻结既有资产**：`types.mbt`（`Token`/`BinOp`/`Ast`/`Type`/`TypedAst`/`Value`/`Diagnostic`/`DiagKind`/`Backend` 等 `pub(all)` 枚举与结构）、`lexer.mbt`/`parser.mbt`/`printer.mbt`/`semantics.mbt` 中既有 `lex`/`parse`/`check`/`eval`/`print_ast`/`compile`/`Diagnostic::new` 的签名与逐字行为**一行不改**；既有测试文件（`prop_roundtrip_test.mbt`/`prop_eval_test.mbt`/`prop_error_test.mbt`/`release_test.mbt`/`mini_compiler_test.mbt`）保持不变。
- **旁路新增**：全部新能力以新增 `.mbt` 文件提供；MiniML 编译路径使用**新函数** `compile_ml`，绝不触碰既有 `compile(TypedAst, Backend) -> Bytes` 桩。
- **依赖顺序**：MiniML 类型层 / `of_minilet` → 词法 / 语法 / 打印 → 合一 / 推断 → 解释器 → 字节码 / VM → 优化 / 流水线 → demo / 基准 / 文档 / 发布，阶段之间设检查点。
- **属性测试**：`design.md` 的 16 条正确性属性各自独立成一个 `*` 可选测试子任务，复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`），每条 **≥100 次迭代**，并以注释标注 `**Feature: mini-compiler, Property N: ...**`。为避免与既有 `prop_eval_test.mbt` 等同名冲突，新增属性测试文件均使用不冲突命名（一属性一文件）。
- **三后端一致**：所有测试 / 基准 / 可执行文档需在 `wasm-gc` / `js` / `native` 三后端运行；**运行 native 后端前必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（已在涉及 native 测试 / 基准 / 文档校验的任务中标注）。

> 路径约定：源文件位于 `src/mini_compiler/`（与既有骨架同包），基准位于新增 `benches/mini_compiler_bench/`。

---

## 任务清单（Tasks）

- [x] 1. 旁路类型层、提升桥与测试生成器基础（`ml_types.mbt`）
  - [x] 1.1 实现 MiniML 旁路类型层与 `of_minilet` 提升桥
    - 新增 `src/mini_compiler/ml_types.mbt`，定义 `Span`、`MlToken`、`CmpOp`、`LogicOp`、`Expr`、`Ty`、`Scheme`、`TExpr`、`Val`、`Env`、`Subst`、`TyEnv`；算术运算复用既有冻结 `BinOp`（不重复定义）
    - 实现 `of_minilet(ast : Ast) -> Expr`：整数 / 变量 / 算术 / `let` 一一对应，span 以 `Span{line:0,col:0}` 哨兵填充
    - 不修改 `types.mbt` 等任何既有文件；新增类型不扩容既有 `pub(all)` 枚举的构造子与派生语义
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 12.1, 12.4_
  - [x] 1.2 新增属性测试生成器集 `ml_gen_test.mbt`
    - 基于 `@infra_pbt` 的 `Gen`/`Rng` 实现：MiniLet `Ast`、MiniML `Expr`、良类型 `Expr`（按类型自顶向下构造保证良类型）、`Ty`、可合一类型对、（规范化）`Subst` 六类生成器
    - 生成器命名加 `ml_`/`minilet_` 前缀，避免与既有测试中的生成器符号冲突
    - _Requirements: 12.6_
  - [x] 1.3 向后兼容属性测试 `prop_compat_test.mbt`
    - **Property 15: MiniLet 向后兼容** — 对任意 MiniLet `Ast`，`eval(check(parse(lex(print_ast(ast)))))` 与 `eval(check(ast))` 相等且中途无诊断
    - **Validates: Requirements 12.7**
    - 复用 1.2 的 MiniLet `Ast` 生成器；≥100 迭代；标注 `Feature: mini-compiler, Property 15`（native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 1.4 MiniLet 黄金样例单元测试 `compat_golden_test.mbt`
    - 固定若干 MiniLet 程序，断言 `lex`/`parse`/`check`/`eval`/`print_ast` 产物与 `0.1.0` 骨架逐字一致；确认既有 `compile` 桩签名与 `Diagnostic::new` 行为不变
    - _Requirements: 12.1, 12.2, 12.3_（native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 2. MiniML 词法、语法与打印（`ml_lexer.mbt` / `ml_parser.mbt` / `ml_printer.mbt`）
  - [x] 2.1 实现 MiniML 词法分析 `ml_lexer.mbt`
    - `lex_ml(src : String) -> Result[Array[MlToken], Diagnostic]`，构建于 `@pc.Input` 不可变游标（`peek`/`advance`/`pos`，1 起始行列），复用既有 `scan_int`/`scan_ident`/`is_alpha`/`is_digit`/`is_space`
    - 多字符算符（`<=` `>=` `==` `!=` `&&` `||` `->`）最长匹配；关键字集合 `let/rec/in/if/then/else/fun/lambda/true/false`，`true`/`false` 归一为 `TkBool`
    - 遇非 MiniML 字母表字符返回 `LexError` 诊断（行列指向该字符）且不产出后续
    - _Requirements: 2.1, 8.1, 12.5_
  - [x] 2.2 实现 MiniML 递归下降语法分析 `ml_parser.mbt`
    - `parse_ml(tokens : Array[MlToken]) -> Result[Expr, Diagnostic]`，按优先级自低到高（`let`/`if`/`lambda` → `||` → `&&` → 比较 → 加减 → 乘除 → 应用 → 原子）在 token 游标上递归下降，分支失败回溯
    - 每个节点 span 取起始 token 的 span；顶层解析后仍有未消费的非空白 token 返回 `SyntaxError`（携带出错位置）且不产树
    - _Requirements: 2.2, 2.3, 8.2_
  - [x] 2.3 实现 MiniML 打印器 `ml_printer.mbt`
    - `print_expr(e : Expr) -> String`：对二元 / 比较 / 逻辑 / 应用节点完全括号化以消除优先级歧义
    - `erase_span(e : Expr) -> Expr`：将全部 span 置零，用于往返等价比较
    - _Requirements: 2.4, 2.5_
  - [x] 2.4 解析 / 打印往返属性测试 `prop_ml_roundtrip_test.mbt`
    - **Property 2: MiniML 解析 / 打印往返** — 对任意合法 `Expr` `e`，对 `print_expr(e)` 重新 `lex_ml → parse_ml` 所得 `Expr` 去 span 后与 `erase_span(e)` 相等
    - **Validates: Requirements 2.5**
    - 复用 1.2 的 `Expr` 生成器；≥100 迭代；标注 `Feature: mini-compiler, Property 2`（native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 2.5 词法 / 语法 / 打印单元测试 `ml_frontend_unit_test.mbt`
    - 覆盖典型源串的 token 序列与 span、各优先级 / 结合性样例、`print_expr` 具体输出；断言非法字符 `LexError`、非法文法与顶层残余 token 的 `SyntaxError` 的 `kind`/`line`/`col`
    - _Requirements: 2.1, 2.2, 2.3, 8.1, 8.2_（native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 3. 检查点 A —— 类型层与前端
  - 在 `wasm-gc`/`js`/`native` 三后端运行已实现部分的全部测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保通过，若有疑问询问用户。

- [x] 4. 合一、替换与 occurs-check（`unify.mbt`）
  - [x] 4.1 实现合一与替换核心 `unify.mbt`
    - `apply_subst`、`apply_scheme`、`compose`、`ftv`、`occurs`、`unify(t1, t2) -> Result[Subst, Diagnostic]`
    - 函数类型先合一参数再在所得替换下合一结果并复合；类型变量合一前做 occurs-check；失败返回 `TypeError` 诊断（消息标注冲突两类型）；`Subst` 采用 `@immut/sorted_map`，产出替换规范化至不动点以保证幂等
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 8.3_
  - [x] 4.2 合一正确性属性测试 `prop_unify_correct_test.mbt`
    - **Property 3: 合一正确性** — 对任意可合一类型项对 `(t1,t2)`，`unify` 成功且把所得替换分别施于 `t1`/`t2` 后相等
    - **Validates: Requirements 3.5**
    - 复用 1.2 的可合一类型对生成器；≥100 迭代；标注 `Property 3`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 4.3 occurs-check 属性测试 `prop_occurs_check_test.mbt`
    - **Property 4: occurs-check 正确性** — 对任意类型变量 `v` 与包含 `v` 且不等于 `v` 的类型项 `t`，`unify(TyVar(v), t)` 失败并返回 `TypeError`
    - **Validates: Requirements 3.6**
    - ≥100 迭代；标注 `Property 4`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 4.4 替换幂等属性测试 `prop_subst_idem_test.mbt`
    - **Property 5: 替换幂等** — 对任意规范化替换 `s` 与类型项 `t`，`apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)`
    - **Validates: Requirements 3.7**
    - 复用 1.2 的 `Subst` 生成器；≥100 迭代；标注 `Property 5`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 4.5 合一单元测试 `unify_unit_test.mbt`
    - 覆盖基本类型 / 函数类型 / 变量绑定的具体合一样例与冲突报错样例
    - _Requirements: 3.1, 3.2, 3.3, 3.4_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 5. Hindley-Milner 类型推断 Algorithm W（`infer.mbt`）
  - [x] 5.1 实现 Algorithm W 推断 `infer.mbt`
    - `instantiate`、`generalize`、`infer_w`、`infer(e) -> Result[(TExpr, Ty), Diagnostic]`、`type_of`；`FreshGen` 新鲜类型变量发生器
    - `let` 泛化、`let rec` 先以新鲜变量引入 `f`、`if` 条件合一 `Bool` 且两分支互相合一、应用引入新鲜结果变量；失败返回携带 span 与冲突类型的 `TypeError`；未绑定变量返回携带变量 span 与变量名的诊断
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 8.3, 8.4_
  - [x] 5.2 主类型存在性属性测试 `prop_principal_type_test.mbt`
    - **Property 6: 主类型存在性** — 对任意良类型 `Expr`，`infer` 成功并返回一个类型
    - **Validates: Requirements 4.8**
    - 复用 1.2 的良类型 `Expr` 生成器；≥100 迭代；标注 `Property 6`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 5.3 推断幂等属性测试 `prop_infer_idem_test.mbt`
    - **Property 7: 推断幂等（类型在最终替换下封闭）** — 对任意良类型 `Expr`，对推断所得类型再施加推断结果替换不改变该类型
    - **Validates: Requirements 4.9**
    - ≥100 迭代；标注 `Property 7`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 5.4 推断单元测试 `infer_unit_test.mbt`
    - 覆盖 `let` 多态、`let rec`、`if`、应用、恒等函数等具体主类型样例；断言不可合一程序返回 `TypeError`（含 span 与冲突类型消息）
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 8.3_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 6. 检查点 B —— 合一与推断
  - 三后端运行合一与推断相关全部测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保通过，若有疑问询问用户。

- [x] 7. 树遍历解释器与作用域检查（`ml_eval.mbt`）
  - [x] 7.1 实现解释器与作用域检查 `ml_eval.mbt`
    - `eval_ml(te : TExpr) -> Val`、`eval_env(te, env)`、`scope_check_ml(e : Expr) -> Result[Unit, Diagnostic]`
    - 不可变环境承载绑定；`lambda`/`fun` 求值为捕获当前环境的 `VClosure`（词法作用域）；应用在捕获环境上扩展形参绑定；除法除零返回 `VInt(0)`；同名内层遮蔽；`let rec` 以延迟按名查找实现自指递归（不构造物理回边，保证三后端一致）
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 8.4, 8.6_
  - [x] 7.2 提升保持语义属性测试 `prop_lift_test.mbt`
    - **Property 1: 提升保持语义（of_minilet）** — 对任意 MiniLet `Ast`，`of_minilet` 提升后按 `infer → eval_ml` 求值的整数结果与既有 `eval(check(ast))` 相等
    - **Validates: Requirements 1.6**
    - 复用 1.2 的 MiniLet `Ast` 生成器；≥100 迭代；标注 `Property 1`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 7.3 求值确定性属性测试 `prop_eval_determinism_test.mbt`
    - **Property 8: 求值确定性** — 对任意良类型 `Expr`，对同一程序重复 `eval_ml` 得到相等结果
    - **Validates: Requirements 5.7**
    - ≥100 迭代；标注 `Property 8`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 7.4 良类型不卡住属性测试 `prop_type_safety_test.mbt`
    - **Property 9: 良类型不卡住（类型可靠性）** — 对任意良类型 `Expr`，`eval_ml` 要么产出 `Val`、要么按除零等全函数约定终止，不进入卡住状态
    - **Validates: Requirements 5.8**
    - ≥100 迭代；标注 `Property 9`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 7.5 作用域检查属性测试 `prop_scope_test.mbt`
    - **Property 14: 作用域检查正确** — 对任意 `Expr`，`scope_check_ml` 恰好接受全部变量引用都能解析到绑定的程序、拒绝含自由变量的程序
    - **Validates: Requirements 8.6**
    - 复用 1.2 的 `Expr` 生成器；≥100 迭代；标注 `Property 14`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 7.6 解释器与作用域单元测试 `eval_ml_unit_test.mbt`
    - 覆盖闭包 / 遮蔽 / 递归 / 除零=0 的具体求值样例；断言未绑定变量引用返回携带变量 span 与变量名的诊断
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 8.4_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 8. 字节码编译后端与栈式虚拟机（`bytecode.mbt` / `vm.mbt` / `text_backend.mbt`）
  - [x] 8.1 实现字节码模型与编译器 `bytecode.mbt`
    - 定义 `Instr`（`PushInt`/`PushBool`/`LoadVar`/`Arith`/`Cmp`/`Logic`/`JumpIfFalse`/`Jump`/`MkClosure`/`Call`/`Ret`/`MkTuple`）与 `Bytecode`
    - `compile_ml(te : TExpr) -> Bytecode`：为整棵语法树产出覆盖全部子表达式的线性字节码，不留未编译节点
    - **以新函数 `compile_ml` 提供，绝不修改既有 `compile(TypedAst, Backend) -> Bytes` 桩**
    - _Requirements: 6.1, 6.2, 12.4_
  - [x] 8.2 实现栈式虚拟机 `vm.mbt`
    - `Frame`、`VM`、`VM::run(bc : Bytecode, env : Env) -> Val`：以操作数栈与调用帧解释每条 `Instr`，程序结束产出栈顶 `Val`
    - _Requirements: 6.3_
  - [x] 8.3 实现额外文本后端 `text_backend.mbt`（可选特性 R6.4）
    - `emit_wat(te)`、`emit_js(te)` 渲染为 wasm 文本 / js 源串，仅供展示
    - _Requirements: 6.4_
  - [x] 8.4 编译—执行等价属性测试 `prop_compile_vm_test.mbt`
    - **Property 10: 编译—执行等价（语义保持）** — 对任意良类型 `Expr`，`VM::run(compile_ml(infer(e)))` 与 `eval_ml(infer(e))` 所得 `Val` 相等
    - **Validates: Requirements 6.5**
    - 复用 1.2 的良类型 `Expr` 生成器；≥100 迭代；标注 `Property 10`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 8.5 字节码 / VM 单元测试 `bytecode_vm_unit_test.mbt`
    - 覆盖常量 / 算术 / 比较 / 逻辑 / `if` 跳转 / 闭包构造与调用的具体字节码与执行样例
    - _Requirements: 6.1, 6.2, 6.3_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 9. 检查点 C —— 解释器与字节码 / VM
  - 三后端运行解释器、字节码与 VM 相关全部测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保通过，若有疑问询问用户。

- [x] 10. AST 优化（`optimize.mbt`）
  - [x] 10.1 实现优化管线 `optimize.mbt`
    - `const_fold`（常量子表达式预求值）、`dead_let_elim`（删除从不引用且无副作用的 `let`）、`beta_reduce`（对字面 `lambda` 应用做捕获避免替换）、`optimize`（`const_fold ∘ dead_let_elim`，默认不含 beta）
    - 保证优化后语法树仍良类型且语义等价
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - [x] 10.2 优化保持可推断性属性测试 `prop_opt_typeable_test.mbt`
    - **Property 11: 优化保持可推断性** — 对任意良类型 `Expr`，`optimize(e)` 后仍可被 `infer` 成功推断且主类型与优化前一致
    - **Validates: Requirements 7.4**
    - ≥100 迭代；标注 `Property 11`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 10.3 优化保持语义属性测试 `prop_opt_semantics_test.mbt`
    - **Property 12: 优化保持语义** — 对任意良类型 `Expr`，`eval_ml(infer(optimize(e))) == eval_ml(infer(e))`
    - **Validates: Requirements 7.5**
    - ≥100 迭代；标注 `Property 12`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 10.4 捕获避免替换属性测试 `prop_beta_capture_test.mbt`
    - **Property 13: 捕获避免替换正确** — 对任意含字面 `lambda` 应用的良类型 `Expr`，启用 beta 化简后求值结果与化简前相等
    - **Validates: Requirements 7.6**
    - ≥100 迭代；标注 `Property 13`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 10.5 优化单元测试 `optimize_unit_test.mbt`
    - 覆盖常量折叠 / 死 `let` 消除 / beta 化简的具体前后形态样例
    - _Requirements: 7.1, 7.2, 7.3_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 11. 统一流水线集成（`pipeline.mbt`）
  - [x] 11.1 实现流水线入口 `pipeline.mbt`
    - `PipelineResult`、`run_interp(src, optimize~)`（`lex_ml → parse_ml → infer → (可选)optimize → eval_ml`）、`run_compiled(src, optimize~)`（`… → compile_ml → VM::run`）
    - 任一前置阶段返回诊断即短路并以 `Failed(d)` 向上传播；两路接受相同良类型输入
    - _Requirements: 13.1, 13.2, 13.3_
  - [x] 11.2 端到端两路一致属性测试 `prop_pipeline_test.mbt`
    - **Property 16: 端到端两路一致** — 对任意良类型 MiniML 源串，`run_interp(src)` 与 `run_compiled(src)` 产出相等的 `Val`
    - **Validates: Requirements 13.4**
    - 由良类型 `Expr` 经 `print_expr` 生成源串作输入；≥100 迭代；标注 `Property 16`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
  - [x] 11.3 流水线单元测试 `pipeline_unit_test.mbt`
    - 覆盖正常源串两路一致样例与各阶段错误短路样例（词法 / 语法 / 类型 / 作用域诊断向上传播）
    - _Requirements: 13.1, 13.2, 13.3_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 12. 旗舰端到端示例（`demo.mbt`）
  - [x] 12.1 实现端到端示例 `demo.mbt`
    - `demo_factorial_src`、`demo_fib_src`、`DemoTrace`、`run_demo(src) -> DemoTrace`：跑通 lex → parse → infer → 优化 → eval 与 compile → VM，返回各阶段产物（主类型、优化后形态、解释结果、VM 结果）
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [x] 12.2 端到端示例单元测试 `demo_unit_test.mbt`
    - 断言示例的推断主类型、优化后形态、解释结果与 VM 结果一致且与文档声明相符
    - _Requirements: 9.2, 9.3, 9.4_（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 13. 检查点 D —— 优化、流水线与示例
  - 三后端运行优化、流水线与示例相关全部测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保通过，若有疑问询问用户。

- [x] 14. 性能基准（`benches/mini_compiler_bench/`）
  - [x] 14.1 新增基准包 `benches/mini_compiler_bench/`
    - 新增 `moon.pkg` 与基准源（`bench_lex`/`bench_parse`/`bench_infer`/`bench_eval`/`bench_compile_vm`），在递增规模程序（节点数 / 绑定数 / 应用深度递增）上运行
    - 输出含机器标识、后端目标、规模参数与计时统计的 JSON/Markdown 工件，并与基线中位数比较、超容差给出可审计回归失败报告；文档记录可复现运行命令与规模参数
    - 基准脚本与文档要求 native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 15. 可执行文档扩充（`README.mbt.md`）
  - [x] 15.1 扩充 `src/mini_compiler/README.mbt.md`
    - 新增可执行文档块覆盖 MiniML 词法 / 语法、类型推断、解释器、AST 优化、字节码编译与 VM 执行及旗舰端到端示例，确保 `moon test *.mbt.md` 通过
    - 补充 paper-to-code 追溯（Hindley/Milner/Damas-Milner、Pierce、Nystrom、Appel）、与 OCaml/Haskell/Rust 教学编译器及《Write You a Haskell》对比、显式实现边界与差异声明（除零=0、可选特性取舍）
    - 文档中声明 native 运行 / 文档校验前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 9.5, 11.1, 11.2, 11.3, 11.4, 11.5, 14.3, 10.4_（native 文档校验前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 16. 发布推进（`CHANGELOG.md` / `release.mbt`）
  - [x] 16.1 推进 SemVer 与发布门禁
    - 更新 `src/mini_compiler/CHANGELOG.md` 记录本次旗舰深化；在 `release.mbt` 中将 `mini_compiler_version` 自 `0.1.0` 推进（次版本，如 `0.2.0`），复用既有 `release_info_with_gates(QualityGates)` 签名按三后端测试 / 属性测试 / 可执行文档三要素聚合 `release_ready`
    - 仅推进版本常量与门禁聚合，不改动既有发布元数据的公开签名
    - _Requirements: 14.1, 14.2, 14.5, 14.6_

- [x] 17. 最终检查点 —— 全量门禁
  - 三后端（`wasm-gc`/`js`/`native`，native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）运行全部属性测试（每条 ≥100 迭代）、单元测试与 `moon test *.mbt.md` 可执行文档；确认 `release_info_with_gates` 判定 release-ready；确保全部通过，若有疑问询问用户。

---

## 备注（Notes）

- 标注 `*` 的子任务为可选（属性测试 / 单元测试），可为更快 MVP 跳过；执行代理**不实现** `*` 子任务，**必须实现**未标 `*` 的子任务。
- 顶层任务与检查点不标 `*`；检查点形如「确保所有测试通过，若有疑问询问用户」。
- 16 条正确性属性已一一映射为独立 `*` 测试子任务：P1→7.2、P2→2.4、P3→4.2、P4→4.3、P5→4.4、P6→5.2、P7→5.3、P8→7.3、P9→7.4、P10→8.4、P11→10.2、P12→10.3、P13→10.4、P14→7.5、P15→1.3、P16→11.2。
- 每条属性测试复用 `@infra_pbt`、≥100 迭代，并以 `**Feature: mini-compiler, Property N: ...**` 标注以便追溯设计属性。
- 全程严格向后兼容：既有文件冻结，新能力旁路新增；`compile_ml` 为新函数，不触碰既有 `compile` 桩。

---

## 任务依赖图（Task Dependency Graph）

> 说明：节点为叶子子任务与检查点；`deps` 为直接前置；`waves` 按拓扑分波次，同一波次内任务写入互不相同的文件（无并行写同文件冲突）；每个叶子子任务恰出现一次。

```json
{
  "feature": "mini-compiler",
  "nodes": {
    "1.1": { "file": "src/mini_compiler/ml_types.mbt", "optional": false, "deps": [] },
    "1.4": { "file": "src/mini_compiler/compat_golden_test.mbt", "optional": true, "deps": ["1.1"] },
    "1.2": { "file": "src/mini_compiler/ml_gen_test.mbt", "optional": true, "deps": ["1.1"] },
    "2.1": { "file": "src/mini_compiler/ml_lexer.mbt", "optional": false, "deps": ["1.1"] },
    "1.3": { "file": "src/mini_compiler/prop_compat_test.mbt", "optional": true, "deps": ["1.2"] },
    "2.2": { "file": "src/mini_compiler/ml_parser.mbt", "optional": false, "deps": ["2.1"] },
    "2.3": { "file": "src/mini_compiler/ml_printer.mbt", "optional": false, "deps": ["2.2"] },
    "2.4": { "file": "src/mini_compiler/prop_ml_roundtrip_test.mbt", "optional": true, "deps": ["2.3", "1.2"] },
    "2.5": { "file": "src/mini_compiler/ml_frontend_unit_test.mbt", "optional": true, "deps": ["2.3"] },
    "3":   { "file": null, "checkpoint": true, "deps": ["1.3", "1.4", "2.4", "2.5"] },
    "4.1": { "file": "src/mini_compiler/unify.mbt", "optional": false, "deps": ["3"] },
    "4.2": { "file": "src/mini_compiler/prop_unify_correct_test.mbt", "optional": true, "deps": ["4.1", "1.2"] },
    "4.3": { "file": "src/mini_compiler/prop_occurs_check_test.mbt", "optional": true, "deps": ["4.1", "1.2"] },
    "4.4": { "file": "src/mini_compiler/prop_subst_idem_test.mbt", "optional": true, "deps": ["4.1", "1.2"] },
    "4.5": { "file": "src/mini_compiler/unify_unit_test.mbt", "optional": true, "deps": ["4.1"] },
    "5.1": { "file": "src/mini_compiler/infer.mbt", "optional": false, "deps": ["4.1"] },
    "5.2": { "file": "src/mini_compiler/prop_principal_type_test.mbt", "optional": true, "deps": ["5.1", "1.2"] },
    "5.3": { "file": "src/mini_compiler/prop_infer_idem_test.mbt", "optional": true, "deps": ["5.1", "1.2"] },
    "5.4": { "file": "src/mini_compiler/infer_unit_test.mbt", "optional": true, "deps": ["5.1"] },
    "6":   { "file": null, "checkpoint": true, "deps": ["4.2", "4.3", "4.4", "4.5", "5.2", "5.3", "5.4"] },
    "7.1": { "file": "src/mini_compiler/ml_eval.mbt", "optional": false, "deps": ["6"] },
    "7.2": { "file": "src/mini_compiler/prop_lift_test.mbt", "optional": true, "deps": ["7.1", "5.1", "1.2"] },
    "7.3": { "file": "src/mini_compiler/prop_eval_determinism_test.mbt", "optional": true, "deps": ["7.1", "5.1", "1.2"] },
    "7.4": { "file": "src/mini_compiler/prop_type_safety_test.mbt", "optional": true, "deps": ["7.1", "5.1", "1.2"] },
    "7.5": { "file": "src/mini_compiler/prop_scope_test.mbt", "optional": true, "deps": ["7.1", "1.2"] },
    "7.6": { "file": "src/mini_compiler/eval_ml_unit_test.mbt", "optional": true, "deps": ["7.1", "5.1"] },
    "8.1": { "file": "src/mini_compiler/bytecode.mbt", "optional": false, "deps": ["7.1"] },
    "8.2": { "file": "src/mini_compiler/vm.mbt", "optional": false, "deps": ["8.1"] },
    "8.3": { "file": "src/mini_compiler/text_backend.mbt", "optional": false, "deps": ["8.1"] },
    "8.4": { "file": "src/mini_compiler/prop_compile_vm_test.mbt", "optional": true, "deps": ["8.2", "7.1", "5.1", "1.2"] },
    "8.5": { "file": "src/mini_compiler/bytecode_vm_unit_test.mbt", "optional": true, "deps": ["8.2"] },
    "9":   { "file": null, "checkpoint": true, "deps": ["7.2", "7.3", "7.4", "7.5", "7.6", "8.3", "8.4", "8.5"] },
    "10.1": { "file": "src/mini_compiler/optimize.mbt", "optional": false, "deps": ["9"] },
    "10.2": { "file": "src/mini_compiler/prop_opt_typeable_test.mbt", "optional": true, "deps": ["10.1", "5.1", "1.2"] },
    "10.3": { "file": "src/mini_compiler/prop_opt_semantics_test.mbt", "optional": true, "deps": ["10.1", "7.1", "5.1", "1.2"] },
    "10.4": { "file": "src/mini_compiler/prop_beta_capture_test.mbt", "optional": true, "deps": ["10.1", "7.1", "5.1", "1.2"] },
    "10.5": { "file": "src/mini_compiler/optimize_unit_test.mbt", "optional": true, "deps": ["10.1"] },
    "11.1": { "file": "src/mini_compiler/pipeline.mbt", "optional": false, "deps": ["10.1", "8.2"] },
    "11.2": { "file": "src/mini_compiler/prop_pipeline_test.mbt", "optional": true, "deps": ["11.1", "1.2"] },
    "11.3": { "file": "src/mini_compiler/pipeline_unit_test.mbt", "optional": true, "deps": ["11.1"] },
    "12.1": { "file": "src/mini_compiler/demo.mbt", "optional": false, "deps": ["11.1"] },
    "12.2": { "file": "src/mini_compiler/demo_unit_test.mbt", "optional": true, "deps": ["12.1"] },
    "13":  { "file": null, "checkpoint": true, "deps": ["10.2", "10.3", "10.4", "10.5", "11.2", "11.3", "12.2"] },
    "14.1": { "file": "benches/mini_compiler_bench/*", "optional": false, "deps": ["13"] },
    "15.1": { "file": "src/mini_compiler/README.mbt.md", "optional": false, "deps": ["13"] },
    "16.1": { "file": "src/mini_compiler/{CHANGELOG.md,release.mbt}", "optional": false, "deps": ["14.1", "15.1"] },
    "17":  { "file": null, "checkpoint": true, "deps": ["16.1"] }
  },
  "waves": [
    { "wave": 1,  "tasks": ["1.1"] },
    { "wave": 2,  "tasks": ["1.2", "1.4", "2.1"] },
    { "wave": 3,  "tasks": ["1.3", "2.2"] },
    { "wave": 4,  "tasks": ["2.3"] },
    { "wave": 5,  "tasks": ["2.4", "2.5"] },
    { "wave": 6,  "tasks": ["3"] },
    { "wave": 7,  "tasks": ["4.1"] },
    { "wave": 8,  "tasks": ["4.2", "4.3", "4.4", "4.5", "5.1"] },
    { "wave": 9,  "tasks": ["5.2", "5.3", "5.4"] },
    { "wave": 10, "tasks": ["6"] },
    { "wave": 11, "tasks": ["7.1"] },
    { "wave": 12, "tasks": ["7.2", "7.3", "7.4", "7.5", "7.6", "8.1"] },
    { "wave": 13, "tasks": ["8.2", "8.3"] },
    { "wave": 14, "tasks": ["8.4", "8.5"] },
    { "wave": 15, "tasks": ["9"] },
    { "wave": 16, "tasks": ["10.1"] },
    { "wave": 17, "tasks": ["10.2", "10.3", "10.4", "10.5", "11.1"] },
    { "wave": 18, "tasks": ["11.2", "11.3", "12.1"] },
    { "wave": 19, "tasks": ["12.2"] },
    { "wave": 20, "tasks": ["13"] },
    { "wave": 21, "tasks": ["14.1", "15.1"] },
    { "wave": 22, "tasks": ["16.1"] },
    { "wave": 23, "tasks": ["17"] }
  ]
}
```
