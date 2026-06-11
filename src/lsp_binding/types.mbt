// types.mbt —— LSP_Binding 的核心数据模型（任务 14.1）。
//
// 设计依据（design.md §「方向五：LSP_Server / LSP_Binding」核心类型与流水线）：
//
//   pub enum JsonRpcMessage {
//     Request(id~ : Id, method~ : String, params~ : Json)
//     Response(id~ : Id, result~ : Json?, error~ : RpcError?)
//     Notification(method~ : String, params~ : Json)
//   }
//   pub fn decode_message(bytes : Bytes) -> Result[JsonRpcMessage, RpcError]
//   pub fn encode_message(msg : JsonRpcMessage) -> Bytes
//   pub fn dispatch(msg : JsonRpcMessage, router : Router) -> JsonRpcMessage?
//
// 本文件锁定协议类型骨架：消息标识 `Id`、错误对象 `RpcError`、JSON-RPC 标准
// 错误码、消息枚举 `JsonRpcMessage` 与方法路由 `Router`。通用 JSON 值模型 `Json`
// 及其编解码见 json.mbt；高层接口 decode/encode/dispatch 见 binding.mbt。

// ───────────────────────────── 标准错误码 ─────────────────────────────

///|
/// JSON-RPC 2.0 标准错误码：解析错误（无法解析为合法 JSON）。
pub let parse_error_code : Int = -32700

///|
/// JSON-RPC 2.0 标准错误码：非法请求（JSON 合法但不符合 JSON-RPC 2.0 结构）。
pub let invalid_request_code : Int = -32600

///|
/// JSON-RPC 2.0 标准错误码：方法未找到（路由无对应处理器）。
pub let method_not_found_code : Int = -32601

///|
/// JSON-RPC 2.0 标准错误码：非法参数。
pub let invalid_params_code : Int = -32602

///|
/// JSON-RPC 2.0 标准错误码：服务器内部错误。
pub let internal_error_code : Int = -32603

// ───────────────────────────── 消息标识 Id ────────────────────────────

///|
/// JSON-RPC 消息标识（id）。规范允许 id 为字符串、数值或 null。
///
/// 骨架以 `Int` 承载数值 id（整数 id 在三后端逐位一致，规避浮点格式化差异）。
pub(all) enum Id {
  IdNum(Int) // 数值 id（整数）
  IdStr(String) // 字符串 id
  IdNull // null id（如解析错误时的错误响应）
} derive(Eq, Show)

// ───────────────────────────── 错误对象 RpcError ──────────────────────

///|
/// JSON-RPC 2.0 错误对象（error）：错误码 `code` + 人类可读 `message` + 可选
/// 附加数据 `data`。满足 Requirement 5.3「返回符合规范的错误响应（含错误码与
/// 消息）」。
pub(all) struct RpcError {
  code : Int
  message : String
  data : Json?
} derive(Eq, Show)

///|
/// 构造一个无附加数据的错误对象。
pub fn RpcError::new(code : Int, message : String) -> RpcError {
  { code, message, data: None }
}

///|
/// 构造一个携带附加数据的错误对象。
pub fn RpcError::with_data(
  code : Int,
  message : String,
  data : Json,
) -> RpcError {
  { code, message, data: Some(data) }
}

// ──────────────────────────── 消息枚举 JsonRpcMessage ─────────────────

///|
/// JSON-RPC 2.0 消息（design.md §「方向五」核心类型）。
///
///   * `Request`      —— 带 id 的请求，期待响应；
///   * `Response`     —— 对某请求的响应，`result` 与 `error` 二者恰有其一；
///   * `Notification` —— 无 id 的通知，不期待响应。
pub(all) enum JsonRpcMessage {
  Request(id~ : Id, method~ : String, params~ : Json)
  Response(id~ : Id, result~ : Json?, error~ : RpcError?)
  Notification(method~ : String, params~ : Json)
} derive(Eq, Show)

///|
/// 构造一个错误响应（result 为空、error 非空），供分发与调用方在非法消息 /
/// 方法未找到等场景下使用（Requirement 5.3）。
pub fn error_response(id : Id, code : Int, message : String) -> JsonRpcMessage {
  Response(id~, result=None, error=Some(RpcError::new(code, message)))
}

// ──────────────────────────── 方法路由 Router ─────────────────────────

///|
/// 方法路由表：按 JSON-RPC `method` 名将消息分发到对应能力处理器。
///
/// 处理器签名为 `(JsonRpcMessage) -> JsonRpcMessage?`：对请求返回 `Some(响应)`
/// 或 `None`（处理器选择不回应）；对通知通常返回 `None`（通知无响应）。骨架的
/// 具体能力处理器（诊断/补全/定义/悬停）由任务 14.2 在 lsp_server 中注册。
pub struct Router {
  handlers : Map[String, (JsonRpcMessage) -> JsonRpcMessage?]
}

///|
/// 构造空路由表。
pub fn Router::new() -> Router {
  { handlers: Map::new() }
}

///|
/// 注册某 `method` 的处理器（已存在则覆盖）。
pub fn Router::register(
  self : Router,
  method : String,
  handler : (JsonRpcMessage) -> JsonRpcMessage?,
) -> Unit {
  self.handlers[method] = handler
}

///|
/// 查询某 `method` 的处理器；无则返回 `None`。
pub fn Router::lookup(
  self : Router,
  method : String,
) -> ((JsonRpcMessage) -> JsonRpcMessage?)? {
  self.handlers.get(method)
}
