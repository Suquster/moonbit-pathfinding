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

## [0.2.0] - 2026-06-12

旗舰深化版（flagship deepening）：在骨架首版基础上，将方向五推进到贴近真实
LSP 服务端的能力广度——补齐生命周期状态机、能力协商、增量文档同步、位置编码
转换、扩展语言特性、推送 + 拉取诊断，以及端到端会话演示。本版本为**向后兼容**
的能力新增（不破坏既有 `release_info` / `lsp_binding` 公共 API），故按 SemVer
做**次版本**推进（`0.1.0` → `0.2.0`）。本版本仍以单一发布单元（名称 `lsp`，
由 `lsp_binding` + `lsp_server` 两子包构成）统一登记。

### Added
- 生命周期状态机：`LifecycleState` / `LifecycleEvent` 与 `step` 状态转移函数，
  以及会话封装 `LspSession`，建模 initialize → initialized → shutdown → exit
  的合法流转与非法事件拒绝（新增 LSP 生命周期状态机）。
- 能力协商：`ServerCapabilitiesExt` / `InitializeParamsExt` 与 `negotiate`，
  依据客户端声明与服务端支持求交集，产出最终生效的服务端能力集合
  （新增能力协商）。
- 增量文档同步：`TextDocumentSyncKind`（None / Full / Incremental）、
  `ContentChange`、`VersionedDocument` 与 `apply_changes`，支持范围增量变更
  与版本号推进（新增增量文档同步）。
- 位置编码：`PositionEncoding`（UTF-8 / UTF-16 / UTF-32）与
  `code_units` / `position_to_offset` / `offset_to_position` / `convert_position`
  / `negotiate_encoding`，处理多编码下 LSP Position 与字节/码元偏移的互转与协商
  （新增位置编码转换）。
- 扩展语言特性：`documentSymbol`、`workspace_symbols`、`references`、
  `document_highlights`、`rename`（产出 `WorkspaceEdit`）、`formatting`、
  `code_actions`、`signature_help`、`semantic_tokens`、`folding_ranges`，
  显著拓宽编辑器侧可用能力（新增扩展语言特性）。
- 推送 + 拉取诊断：在既有 publishDiagnostics 推送模型外，新增
  `pull_diagnostics` 拉取式诊断与 `diagnostic_to_json` 序列化，覆盖 LSP 3.17
  的双向诊断模型（新增推送 + 拉取诊断）。
- 端到端演示：`run_session_demo` 串联生命周期、同步、能力协商与诊断的完整
  会话演示（新增端到端会话演示）。
- release：`release_info()` 登记版本推进至 `0.2.0`，仍以单一发布单元名
  `lsp` 登记，changelog 路径与语义保持不变（新增版本推进登记）。

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/lsp-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/lsp-v0.1.0...lsp-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/lsp-v0.1.0
