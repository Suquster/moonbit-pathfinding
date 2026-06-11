# Changelog —— Parser_Combinator（方向四）

本文件记录 **Parser_Combinator** 方向（子包 `src/parser_combinator`）作为
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

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ 解析器契约/往返属性测试 + 可执行文档」的方向骨架基线。

### Added
- 核心类型：`Parser[T]`、`ParseResult[T]`（`Ok(T, Input)` /
  `Fail(Pos, expected~)`）、`Input`、`Pos`，并提供
  `Parser::parse` / `parse_string`、`Input::from_string` 等基础 API
  （新增解析器核心类型与输入游标）。
- 基础原语：`pchar`、`satisfy`、`any_char`、`ptoken`
  （新增字符 / 词法单元匹配原语）。
- 组合子：`seq`、`alt`、`many`、`many1`、`optional`
  （新增序列 / 择一 / 重复 / 可选组合子）。
- 回溯控制：择一分支失败时恢复到分支起始位置；失败时不消费输入并返回
  含位置（`Pos`）与期望符号（`expected~`）的错误
  （新增回溯语义与带位置的解析错误）。
- 属性测试：解析器组合子契约不变量与语法结构往返性质，跨三后端一致
  （新增解析器契约与往返属性测试）。
- 可执行文档：覆盖序列 / 择一 / 重复三类组合子的 `*.mbt.md` 端到端样例
  （新增解析器可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/parser_combinator/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/parser_combinator-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/parser_combinator-v0.1.0
