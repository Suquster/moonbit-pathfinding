// release.mbt —— `lsp_binding` 协议层子包的**独立 SemVer 版本线**（旁路登记）。
//
// 对应任务 18.5 / Requirement 11.6。
//
// 背景与边界（design.md §「方向五：LSP_Server / LSP_Binding」与§「发布元数据模型」）：
//   方向五对外作为**单一发布单元**发布，发布名 "lsp"，由入口子包 `lsp_server`
//   通过 `release_info()` 统一登记为一个 `@release_meta.DirectionRelease`
//   （见 `src/lsp_server/release.mbt`）。该「单一发布单元」语义是方向对外的
//   唯一发布契约，**不因本文件而改变**。
//
//   随着协议层旗舰深化（Content-Length 头部分帧、JSON-RPC 批量、请求取消、
//   id 关联）落地，`lsp_binding` 子包自身的公共 API 显著扩张。为了在子包粒度
//   上可追溯地表达「协议层能力演进」，本文件**旁路**维护一条属于 `lsp_binding`
//   的、独立于发布单元 "lsp" 的内部 SemVer 版本线（配套 `CHANGELOG.md`）。
//
//   这是一条**纯文档/可追溯用途**的版本常量：它既不向 `@release_meta` 登记
//   新的 `DirectionRelease`，也不改变 `lsp_server` 中以 "lsp" 名义登记的单一
//   发布单元语义。换言之——
//     * 对外发布：仍是单一发布单元 "lsp"（版本见 `lsp_version`）；
//     * 对内追溯：`lsp_binding` 协议层有自己的 SemVer 线（本常量）。

///|
/// `lsp_binding` 协议层子包的**独立 SemVer 版本号**。
///
/// 自骨架首版 `0.1.0` 起，本次随协议层旗舰深化（帧 / 批量 / 取消 / 关联）
/// 做**次版本号推进**至 `0.2.0`：在不破坏既有公共 API 的前提下新增了
/// 一批向后兼容的能力（`encode_framed` / `decode_framed` / `FrameReader`、
/// `decode_batch` / `dispatch_batch` / `encode_batch`、`request_cancelled_code`
/// / `CancelRegistry` / `cancel_id_of` / `cancelled_response`、`id_of` /
/// `correlate`）。
///
/// 注意：本常量仅表达 `lsp_binding` 子包自身的协议层版本线，用于子包粒度的
/// 变更追溯；方向五对外仍以 `lsp_server` 登记的单一发布单元 "lsp" 发布
/// （见 `lsp_version` / `release_info()`），二者语义互不影响。
pub let lsp_binding_version : String = "0.2.0"
