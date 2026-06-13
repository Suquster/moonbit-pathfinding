# Changelog —— LSP（方向五）

本文件记录 **LSP** 方向作为**独立发布单元**的全部值得关注的变更。
方向五由两个子包共同构成、作为单一发布单元（名称 `lsp`）发布：

- `src/lsp_binding` —— JSON-RPC 2.0 协议类型（`JsonRpcMessage`）与 JSON
  编解码 / 分发框架；
- `src/lsp_server` —— 依赖 `lsp_binding` 的能力处理器层（方向对外入口），
  本 changelog 即维护于此入口子包。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`，发布单元名 `lsp`）。

---

## [Unreleased]

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ JSON-RPC 往返与非法消息错误条件属性测试 + 可执行文档」的方向骨架
基线。本版本同时涵盖 `lsp_binding` 与 `lsp_server` 两个子包。

### Added
- lsp_binding：JSON 值模型 `Json` 与 JSON-RPC 2.0 消息类型 `JsonRpcMessage`
  （Request / Response / Notification），并提供 `decode_message` /
  `encode_message` / `dispatch`，复用 `@serialization` 的 JSON 编解码骨架；
  非法消息返回符合规范的错误响应且不终止进程
  （新增 JSON-RPC 协议类型与编解码/分发框架）。
- lsp_server：针对一个通用 DSL（极简 `key=value` 配置 DSL，含定义 `key=...`
  与引用 `${key}` 两类符号关系）实现五项语言能力处理器——
  `on_initialize`（在 `ServerCapabilities` 声明诊断/补全/定义/悬停四项能力）、
  `on_did_change`（重分析文档并产出 `Array[Diagnostic]`，publishDiagnostics）、
  `on_completion`（基于已定义符号返回补全候选）、
  `on_definition`（引用 → 符号定义位置）、
  `on_hover`（符号/引用 → 描述信息）
  （新增 LSP 能力处理器层）。
- 属性测试：JSON-RPC 消息编解码往返（decode∘encode 恒等）与非法消息错误
  条件（始终产出规范错误响应、不 panic）性质，跨三后端一致
  （新增往返与非法消息错误条件属性测试）。
- 可执行文档：展示 JSON-RPC 请求解码、分发与编码响应的 `*.mbt.md` 端到端
  样例（新增 LSP 可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（发布单元名
  `lsp`，版本 `0.1.0`，changelog 路径 `src/lsp_server/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/lsp-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/lsp-v0.1.0
