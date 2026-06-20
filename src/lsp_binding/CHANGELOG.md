# Changelog —— lsp_binding（协议层子包 · 独立 SemVer 线）

本文件记录 **`src/lsp_binding`** 子包（JSON-RPC 2.0 协议类型 + JSON 编解码 /
分发 / 传输框架）作为**协议层独立 SemVer 版本线**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> ⚠️ 版本线说明：本 changelog 维护的是 `lsp_binding` 子包**自身**的协议层
> SemVer 线（版本常量见 `release.mbt` 的 `lsp_binding_version`），用于子包
> 粒度的能力演进追溯。方向五对外仍作为**单一发布单元** `lsp` 统一发布
> （由入口子包 `lsp_server` 通过 `release_info()` 登记 `DirectionRelease`，
> 其版本线维护于 `src/lsp_server/CHANGELOG.md`）。本独立版本线**不改变**
> 该单一发布单元语义，二者互不影响。

---

## [Unreleased]

## [0.2.0] - 2026-06-11

协议层旗舰深化版：在骨架首版的 JSON-RPC 2.0 往返与分发基础上，向后兼容地
新增四类传输 / 协议能力——头部分帧、批量、请求取消、id 关联。本批新增均不
破坏既有公共 API，故按 SemVer 做**次版本号**推进（`0.1.0` → `0.2.0`）。

### Added
- 帧（Content-Length 头部分帧）：按 LSP base protocol 以 `Content-Length`
  头封装 / 拆解单条消息——`encode_framed`（消息 → 带头部字节流）、
  `decode_framed`（带头部字节流 → 消息），以及面向流式输入、可增量喂入并
  逐帧产出的 `FrameReader`（`new` / `push` / `next`）。
- 批量（JSON-RPC batch）：支持数组形态的批量请求 / 响应——`decode_batch`
  （字节流 → 逐条解码结果数组）、`dispatch_batch`（批量消息经 `Router`
  分发为响应数组）、`encode_batch`（消息数组 → 字节流）。
- 取消（请求取消）：新增规范取消错误码 `request_cancelled_code`，以及取消
  登记表 `CancelRegistry`（`new` / `cancel` / `is_cancelled`）、从
  `$/cancelRequest` 通知参数提取目标 id 的 `cancel_id_of`，与据此构造规范
  取消响应的 `cancelled_response`。
- 关联（id 关联）：新增 `id_of`（取消息的 `Id`）与 `correlate`（判定请求与
  响应是否经由同一 `Id` 关联配对），用于请求/响应往返的关联校验。
- release：新增 `lsp_binding_version` 常量，确立本协议层子包的独立 SemVer
  版本线（旁路登记，不影响发布单元 `lsp` 的单一发布单元语义）。

## [0.1.0] - 2026-06-11

协议层骨架首版：随方向五骨架基线一同落地的 `lsp_binding` 初始版本。

### Added
- JSON 值模型 `Json` 与 JSON-RPC 2.0 消息类型 `JsonRpcMessage`
  （Request / Response / Notification），以及 `decode_message` /
  `encode_message` / `dispatch` 与 `Router` 分发框架。
- 规范错误码（`parse_error_code` / `invalid_request_code` /
  `method_not_found_code` / `invalid_params_code` / `internal_error_code`）
  与结构化错误类型 `RpcError`、`error_response`：非法消息以 `Result::Err`
  承载规范错误而不 panic / 终止进程。
- 属性测试：JSON-RPC 消息编解码往返（decode∘encode 恒等）与非法消息错误
  条件性质，跨三后端（wasm-gc / js / native）一致。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/lsp_binding-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/lsp_binding-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/lsp_binding-v0.1.0
