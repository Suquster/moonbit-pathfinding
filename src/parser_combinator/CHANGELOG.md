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

## [0.2.0] - 2026-06-12

旗舰深化（🟣 档位 3「业界顶尖」）：在 `0.1.0` 骨架之上以**新增文件旁路扩展**为
一套对标 Haskell `parsec` / `megaparsec` 与 Rust `nom` 的旗舰级解析器组合子库，
既有 `0.1.0` 公开契约全部冻结。

### Added
- L0 核心代数（`algebra.mbt`）：`pure` / `map` / `bind` / `ap` / `pfail`
  （functor / monad / applicative 地基，Hutton & Meijer 1998）。
- L0 衍生组合子（`derived.mbt`）：`sep_by` / `sep_by1` / `between` /
  `chainl1` / `chainr1` / `chainl` / `chainr` / `lazy_parser`（递归文法）。
- L0 前瞻（`lookahead.mbt`）：`lookahead` / `not_followed_by`（零消费不变量）。
- L0 错误模型（`error_model.mbt`）：`label`（`<?>`）位置敏感改写、最远失败
  合并器与确定性期望归一。
- L1 运行期引擎（`engine.mbt`）：不透明 `Grammar[T]`、`lift`、`run_naive` /
  `run_packrat` 双入口。
- L1 提交语义与恢复（`commit.mbt`）：`commit` / `cut` / `choice`（提交感知
  择一）/ `recover`（同步恢复）。
- L1 packrat 记忆化（`packrat.mbt`）：`memoize`，按运行隔离缓存、线性时间
  （Ford 2002）。
- L1 直接左递归（`left_recursion.mbt`）：`left_recursive` 以 seed-growing 支持
  `A := A op b | b`（Warth et al. 2008）。
- L1 流式 / 增量输入（`streaming.mbt`）：`Step[T]` / `run_incremental` / `drive`
  （分段无关性、needs-more-input 语义）。
- L2 旗舰示例：JSON 解析器 / 打印器 / 转义解码 / 错误恢复（`json.mbt`）与
  算术表达式求值器（优先级、左/右结合，`arith.mbt`）。
- 基准：`benches/parser_json_bench` 与 `benches/parser_arith_bench`，对比
  packrat 与朴素实现在递增规模下的计时，结果工件落地 `benches/results/`。
- 属性测试：Property 1~31 以 `@infra_pbt`（≥100 迭代）实现，覆盖
  functor / monad / alternative 定律、衍生组合子、前瞻、错误模型与最远失败、
  提交语义、packrat 差分一致性与缓存隔离、左递归与 chainl1 差分、流式分段
  无关性、JSON 往返 / 转义 / 错误诊断、算术求值一致性。
- 可执行文档：`README.mbt.md` 扩充至 9 段端到端示例，并补充 paper-to-code
  可追溯与 `parsec` / `megaparsec` / `nom` 对标。

### Changed
- `alt` 失败诊断**精化**为最远失败（farthest-failure）：全分支失败时报告
  `offset` 最大的失败位置，仅合并落在该最远位置的分支期望（去重并保留首次
  出现顺序），舍弃较早位置分支的期望。签名与成功路径行为不变；这是唯一可
  观察的行为变化，属严格信息增益（失败位置不早于原值、期望更聚焦），据此将
  版本推进为次版本 `0.2.0`。

### Compatibility
- 既有公开类型 `Parser[T]` / `ParseResult[T]` / `Input` / `Pos` 与原语
  `pchar` / `satisfy` / `any_char` / `ptoken`、组合子 `seq` / `alt` / `many` /
  `many1` / `optional` 的签名与（除上述 `alt` 失败诊断精化外的）行为保持不变；
  `to_path_error` 桥接语义不变。

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/parser_combinator-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/parser_combinator-v0.1.0...parser_combinator-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/parser_combinator-v0.1.0
