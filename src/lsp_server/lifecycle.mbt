// lifecycle.mbt —— 完整 LSP 生命周期纯状态机与会话句柄（旗舰深化，任务 5.1 旁路新增）。
//
// paper-to-code 追溯：Microsoft Language Server Protocol §「Lifecycle Messages」
//   （initialize / initialized / shutdown / exit）与 JSON-RPC 2.0 会话语义。
//
// 设计原则（design.md §3.1）：
//   * 状态机为**纯转移函数** `step`：给定当前状态、是否已收到 shutdown、一个事件与
//     用于合成响应的 reply_id，返回新状态 + 可选响应 + 可选退出码，无 IO、无全局可变状态，
//     确保 wasm-gc / js / native 三后端逐位一致。
//   * `LspSession` 在状态机之上叠加「是否已 shutdown」与协商后能力 `ServerCapabilitiesExt`，
//     提供 `new` / `handle` / `state` 三个会话级接口。
//
// 转移规则（与 Requirement 1.1–1.8 一一对应）：
//   1.1 Uninitialized --EvInitialize--> Initializing（回携带协商能力的 initialize 响应）
//   1.2 Initializing  --EvInitialized--> Initialized
//   1.3 Uninitialized --EvRequest(非 initialize)--> 状态不变，回 invalid_request_code 错误响应
//   1.4 Initialized   --EvShutdown--> ShuttingDown，回 result=null 成功响应
//   1.5 ShuttingDown  --EvRequest(非 exit)--> 状态不变，回 invalid_request_code 错误响应
//   1.6 任意状态      --EvExit--> Exited，exit_code = if shutdown_seen {0} else {1}
//   1.8 未声明转移：保持当前状态，对请求回 invalid_request_code（健全性）
//
// 依赖：capabilities_ext.mbt 的 `ServerCapabilitiesExt` / `InitializeParamsExt`。
// 能力协商 `negotiate` 由任务 5.2 补充，此处 initialize 响应以默认（全量）能力回报。

// ───────────────────────────── 状态与事件 ─────────────────────────────

///|
/// 生命周期状态（LSP Lifecycle Messages）。
pub(all) enum LifecycleState {
  Uninitialized // 未初始化（会话起点）
  Initializing // 已收到 initialize，等待 initialized
  Initialized // 已就绪，可处理常规请求
  ShuttingDown // 已收到 shutdown，等待 exit
  Exited // 已退出
} derive(Eq, Debug)

///|
/// `LifecycleState` 的文本表示用于对外协议 / JSON 输出（领域专用显示文本），
/// 故手工实现 `Show`（变体名），与历史 `derive(Show)` 行为一致；调试输出走 `Debug`。
pub impl Show for LifecycleState with fn output(self, logger) {
  logger.write_string(
    match self {
      Uninitialized => "Uninitialized"
      Initializing => "Initializing"
      Initialized => "Initialized"
      ShuttingDown => "ShuttingDown"
      Exited => "Exited"
    },
  )
}

///|
/// 驱动生命周期状态机的事件。`EvRequest` / `EvNotification` 承载除生命周期消息之外
/// 的任意请求 / 通知（按当前状态裁决）。
pub(all) enum LifecycleEvent {
  EvInitialize(InitializeParamsExt) // initialize 请求
  EvInitialized // initialized 通知
  EvShutdown // shutdown 请求
  EvExit // exit 通知
  EvRequest(method_name~ : String) // 任意其他请求
  EvNotification(method_name~ : String) // 任意其他通知
} derive(Eq, Debug)

///|
/// 一步转移的结果：新状态 `state` + 可选应答 `reply`（请求才有；通知为 None）+
/// 可选退出码 `exit_code`（仅 EvExit 给出）。
pub(all) struct StepResult {
  state : LifecycleState
  reply : @lsp_binding.JsonRpcMessage?
  exit_code : Int?
} derive(Eq, Debug)

// ───────────────────────────── 能力 JSON 合成 ─────────────────────────

///|
/// 将扩展服务端能力编码为 `initialize` 响应的 capabilities JSON 对象。
/// （能力协商在任务 5.2 实现；此处按 capabilities 各 provider 位逐项声明。）
fn caps_ext_to_json(caps : ServerCapabilitiesExt) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("diagnosticProvider", @lsp_binding.JBool(caps.diagnostic_provider)),
    ("completionProvider", @lsp_binding.JBool(caps.completion_provider)),
    ("definitionProvider", @lsp_binding.JBool(caps.definition_provider)),
    ("hoverProvider", @lsp_binding.JBool(caps.hover_provider)),
    (
      "documentSymbolProvider",
      @lsp_binding.JBool(caps.document_symbol_provider),
    ),
    ("referencesProvider", @lsp_binding.JBool(caps.references_provider)),
    ("renameProvider", @lsp_binding.JBool(caps.rename_provider)),
    ("documentFormattingProvider", @lsp_binding.JBool(caps.formatting_provider)),
    ("codeActionProvider", @lsp_binding.JBool(caps.code_action_provider)),
    ("signatureHelpProvider", @lsp_binding.JBool(caps.signature_help_provider)),
    (
      "semanticTokensProvider",
      @lsp_binding.JBool(caps.semantic_tokens_provider),
    ),
    ("foldingRangeProvider", @lsp_binding.JBool(caps.folding_range_provider)),
    (
      "documentHighlightProvider",
      @lsp_binding.JBool(caps.document_highlight_provider),
    ),
  ])
}

///|
/// 合成 `initialize` 成功响应：result 为 `{ "capabilities": { ... } }`。
fn initialize_reply(
  reply_id : @lsp_binding.Id,
  caps : ServerCapabilitiesExt,
) -> @lsp_binding.JsonRpcMessage {
  let result = @lsp_binding.JObj([("capabilities", caps_ext_to_json(caps))])
  @lsp_binding.Response(id=reply_id, result=Some(result), error=None)
}

///|
/// 合成生命周期非法请求的错误响应（携带 `invalid_request_code`）。
fn invalid_request_reply(
  reply_id : @lsp_binding.Id,
) -> @lsp_binding.JsonRpcMessage {
  @lsp_binding.error_response(
    reply_id, @lsp_binding.invalid_request_code, "invalid request for current lifecycle state",
  )
}

// ───────────────────────────── 纯状态转移 ─────────────────────────────

///|
/// 生命周期纯状态转移（Requirement 1.1–1.8）。
///
/// `shutdown_seen` 表示在本步之前是否已成功收到过 shutdown（影响 exit 退出码）；
/// `reply_id` 用于为请求合成带 id 的响应。
pub fn step(
  state : LifecycleState,
  shutdown_seen : Bool,
  event : LifecycleEvent,
  reply_id : @lsp_binding.Id,
) -> StepResult {
  match event {
    // initialize：仅在 Uninitialized 合法（1.1）；其余状态视为非法请求（1.8）。
    EvInitialize(_) =>
      match state {
        Uninitialized =>
          StepResult::{
            state: Initializing,
            reply: Some(
              initialize_reply(reply_id, ServerCapabilitiesExt::default()),
            ),
            exit_code: None,
          }
        _ =>
          StepResult::{
            state,
            reply: Some(invalid_request_reply(reply_id)),
            exit_code: None,
          }
      }
    // initialized：仅在 Initializing 合法（1.2）；通知无应答。
    EvInitialized =>
      match state {
        Initializing =>
          StepResult::{ state: Initialized, reply: None, exit_code: None }
        _ => StepResult::{ state, reply: None, exit_code: None }
      }
    // shutdown：仅在 Initialized 合法，回 result=null（1.4）；其余非法请求（1.5/1.8）。
    EvShutdown =>
      match state {
        Initialized =>
          StepResult::{
            state: ShuttingDown,
            reply: Some(
              @lsp_binding.Response(
                id=reply_id,
                result=Some(@lsp_binding.JNull),
                error=None,
              ),
            ),
            exit_code: None,
          }
        _ =>
          StepResult::{
            state,
            reply: Some(invalid_request_reply(reply_id)),
            exit_code: None,
          }
      }
    // exit：任意状态转入 Exited，退出码取决于是否已 shutdown（1.6）。
    EvExit =>
      StepResult::{
        state: Exited,
        reply: None,
        exit_code: Some(if shutdown_seen { 0 } else { 1 }),
      }
    // 其他请求：未声明转移，保持状态并回 invalid_request_code（1.3/1.5/1.8 健全性）。
    EvRequest(method_name=_) =>
      StepResult::{
        state,
        reply: Some(invalid_request_reply(reply_id)),
        exit_code: None,
      }
    // 其他通知：未声明转移，保持状态且无应答（通知无响应）。
    EvNotification(method_name=_) =>
      StepResult::{ state, reply: None, exit_code: None }
  }
}

// ───────────────────────────── 会话句柄 ───────────────────────────────

///|
/// 会话句柄：封装当前生命周期状态、是否已收到 shutdown 与协商后能力。
pub struct LspSession {
  state : LifecycleState
  shutdown_seen : Bool
  caps : ServerCapabilitiesExt
}

///|
/// 新建会话：初始状态 `Uninitialized`，默认（全量）能力。
pub fn LspSession::new() -> LspSession {
  {
    state: Uninitialized,
    shutdown_seen: false,
    caps: ServerCapabilitiesExt::default(),
  }
}

///|
/// 当前会话状态。
pub fn LspSession::state(self : LspSession) -> LifecycleState {
  self.state
}

///|
/// 将一条 JSON-RPC 消息映射为生命周期事件与应答用的 reply_id。
fn message_to_event(
  msg : @lsp_binding.JsonRpcMessage,
) -> (LifecycleEvent, @lsp_binding.Id) {
  match msg {
    @lsp_binding.Request(id~, method_name~, params~) =>
      if method_name == "initialize" {
        (EvInitialize(parse_init_params(params)), id)
      } else if method_name == "shutdown" {
        (EvShutdown, id)
      } else {
        (EvRequest(method_name~), id)
      }
    @lsp_binding.Notification(method_name~, params=_) =>
      if method_name == "initialized" {
        (EvInitialized, @lsp_binding.IdNull)
      } else if method_name == "exit" {
        (EvExit, @lsp_binding.IdNull)
      } else {
        (EvNotification(method_name~), @lsp_binding.IdNull)
      }
    // 响应消息不驱动生命周期（视为无关通知，无应答、状态不变）。
    @lsp_binding.Response(_) =>
      (EvNotification(method_name="$/response"), @lsp_binding.IdNull)
  }
}

///|
/// 从 `initialize` 请求 params 解析扩展初始化参数：提取 `capabilities` 与
/// `positionEncodings` 两个字符串数组字段（缺失则为空）。完整能力协商见任务 5.2。
fn parse_init_params(params : @lsp_binding.Json) -> InitializeParamsExt {
  let capabilities = json_string_array_field(params, "capabilities")
  let position_encodings = json_string_array_field(params, "positionEncodings")
  { capabilities, position_encodings }
}

///|
/// 从 JSON 对象中按 key 取出字符串数组字段；缺失或类型不符返回空数组。
fn json_string_array_field(
  json : @lsp_binding.Json,
  key : String,
) -> Array[String] {
  let out : Array[String] = []
  match json {
    @lsp_binding.JObj(fields) =>
      for kv in fields {
        let (k, v) = kv
        if k == key {
          match v {
            @lsp_binding.JArr(items) =>
              for it in items {
                match it {
                  @lsp_binding.JStr(s) => out.push(s)
                  _ => ()
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  out
}

///|
/// 驱动一条消息：返回新会话与可选响应（Requirement 1.1–1.8）。
/// 一旦成功转入 `ShuttingDown`，会话即记忆 `shutdown_seen=true`（影响后续 exit 退出码）。
pub fn LspSession::handle(
  self : LspSession,
  msg : @lsp_binding.JsonRpcMessage,
) -> (LspSession, @lsp_binding.JsonRpcMessage?) {
  let (event, reply_id) = message_to_event(msg)
  let result = step(self.state, self.shutdown_seen, event, reply_id)
  let new_shutdown_seen = self.shutdown_seen || result.state == ShuttingDown
  let next = {
    state: result.state,
    shutdown_seen: new_shutdown_seen,
    caps: self.caps,
  }
  (next, result.reply)
}
