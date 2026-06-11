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

### 计划中（后续任务）
- 任务 15.2：完整树遍历解释器 `eval` 与含类型错误诊断的 `check`。
- 任务 15.3 ~ 15.5：AST 往返、词法/语法错误条件、求值确定性与作用域不变量属性测试及证明谓词。
- 任务 15.6：`*.mbt.md` 端到端可执行文档（源码 → AST → 求值）。

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/mini_compiler-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/mini_compiler-v0.1.0
