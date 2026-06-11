# Changelog —— Regex_Engine（方向二）

本文件记录 **Regex_Engine** 方向（子包 `src/regex_engine`）作为
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
native）+ 正则语法树解析/打印 + NFA/DFA 构造 + `find` 匹配 + 往返/差分/错误
属性测试 + 可执行文档」的方向骨架基线。

### Added
- 语法树：`Regex` 正则表达式语法树类型，覆盖字面字符 / 拼接 / 择一 /
  重复（`*` `+` `?`）/ 分组等正则子集结构
  （新增正则语法树类型）。
- 解析与打印：`parse_regex`（解析为语法树，非法输入返回含位置的解析错误
  且不构造自动机）与 `print_regex`（round-trip 配套打印器），二者构成
  解析 ↔ 打印往返闭环（新增正则解析器与打印器）。
- 自动机：基于 Thompson 构造的 `NFA` 与子集构造确定化得到的 `DFA`
  （新增 NFA/DFA 自动机构造）。
- 匹配执行：`find` 在输入串上执行匹配并返回匹配区间
  （新增正则匹配执行与匹配区间返回）。
- 属性测试：解析 ↔ 打印往返性质、NFA 与 DFA 匹配结果差分一致性、
  非法输入错误条件性质，跨三后端一致
  （新增往返 / 差分 / 错误属性测试）。
- 可执行文档：覆盖解析、匹配与匹配区间返回的 `*.mbt.md` 端到端样例
  （新增正则可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/regex_engine/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/regex_engine-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/regex_engine-v0.1.0
