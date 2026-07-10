# Changelog —— Mini_Compiler（方向一）

本文件记录 **Mini_Compiler** 方向（子包 `src/mini_compiler`）作为
**独立发布单元**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`）。

---

## [Unreleased]

### Fixed

- `compile(TypedAst, Backend)` 不再返回恒空字节：`Wasm` 现产出导出
  `main() -> i32` 的合法 WebAssembly 二进制，`Js` 现产出可由 Node.js
  直接执行且与解释器整数语义一致的程序。

## [0.2.0] - 2026-06-12

**旗舰深化版（flagship deepening）**：在 `0.1.0` 骨架基线之上，以
**bypass-additive**（旁路增量、零破坏）方式新增完整的 **MiniML** 语言层——
覆盖词法/语法、Hindley–Milner 类型推断、树遍历解释器、栈式字节码后端与
虚拟机、AST 优化、统一流水线、旗舰演示、基准与可执行文档，并以 16 条
正确性属性（PBT）守护。版本按 **SemVer 次版本号**递进（向后兼容的增量
特性），既有 MiniLet 公开 API（`lex` / `parse` / `check` / `eval` /
`print_ast` / `compile`）**行为冻结**，保持严格向后兼容。

### Added
- 语言层 **MiniML**（bypass-additive）：核心数据模型 `Expr` / `Ty` /
  `TExpr` / `Val`，以及从既有 MiniLet AST 桥接到 MiniML 的 `of_minilet`
  提升入口（不改动 MiniLet 既有产物）。
- 前端：MiniML 词法 `lex_ml`、递归下降语法 `parse_ml`、与解析互逆的
  打印器 `print_expr`（为 AST 往返性质奠基）。
- 类型系统：Hindley–Milner 类型推断——合一 `unify`（含 occurs-check）与
  Algorithm W 风格的 `infer`，给出主类型（principal type）。
- 解释器：树遍历求值 `eval_ml` 与作用域检查 `scope_check_ml`。
- 后端：栈式字节码后端 `compile_ml`（指令集 `Instr` / 程序 `Bytecode`）与
  虚拟机 `VM::run`。
- 优化：AST 级优化遍——常量折叠 `const_fold`、死绑定消除
  `dead_let_elim`、beta 归约 `beta_reduce`，及聚合入口 `optimize`。
- 流水线：统一入口 `run_interp`（解释执行）与 `run_compiled`（编译到
  字节码后经 VM 执行），二者结果一致。
- 演示：旗舰端到端 `run_demo`（源码 → 词法 → 语法 → 推断 → 优化 →
  解释 / 编译执行）。
- 基准：新增 MiniML 基准包，度量推断 / 编译 / 执行路径。
- 文档：扩充 `*.mbt.md` 可执行文档，端到端覆盖 MiniML 全流程。
- 测试：新增 16 条正确性属性（PBT）——AST 往返、合一正确性、occurs-check、
  替换/推断幂等、主类型、类型安全、求值确定性、作用域、优化语义保持/可类型化、
  编译-VM 与解释一致、beta 捕获规避、兼容性金标准等。

### Changed
- release：`mini_compiler_version` 自 `0.1.0` 推进至 `0.2.0`（次版本号）；
  `release_info_with_gates(QualityGates)` 沿用既有签名，门禁聚合语义明确为
  **三后端测试 / 属性测试 / 可执行文档**三要素，经
  `@release_meta.aggregate_release_ready` 聚合 `release_ready`。
- 公开签名不变：`mini_compiler_name`、`release_info()`、
  `release_info_with_gates(QualityGates)` 维持原签名（仅版本常量值变化）。

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版，任务 15.1）：达成「可编译 + 跑通三后端
（wasm-gc / js / native）+ 目标语言文法声明 + 词法/语法/类型/求值/打印
流水线类型与桩」的方向骨架基线。

### Added
- 目标语言：声明极简「整数算术 + let 绑定 + 变量」表达式语言 **MiniLet**
  的词法与上下文无关文法（产生式规则，见 `moon.pkg` 头注释，R1.1）。
- 核心类型：`Token`、`Ast`、`TypedAst`、`Diagnostic`、`Value`，以及辅助的
  `BinOp` / `Type` / `DiagKind` / `Backend`（新增编译器核心数据模型）。
- 词法分析：`lex` 完整实现，构建于 `@parser_combinator` 的不可变游标
  `Input`；非法字符返回含**行号与列号**的词法诊断且不产生后续产物（R1.3）。
- 语法分析：`parse` 构建于 `@parser_combinator`，以递归下降解析 MiniLet
  文法为 `Ast`（R1.2）；语法错误返回含行列位置的语法诊断（R1.3）。
- 打印器：最小可用 `print_ast`，与 `parse` 互逆（完全括号化二元运算），
  为后续「打印再解析」往返性质奠基。
- 流水线桩：`check`（结构性标注为 `TypedAst`）、`eval`（整数字面量求值）、
  `compile`（锁定 `Backend` 目标枚举与签名）——完整实现属任务 15.2 及后续。
- release：通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/mini_compiler/CHANGELOG.md`）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/mini_compiler-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/mini_compiler-v0.1.0...mini_compiler-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/mini_compiler-v0.1.0
