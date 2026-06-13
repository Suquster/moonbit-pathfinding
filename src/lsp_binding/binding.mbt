// binding.mbt —— JSON-RPC 2.0 编解码与分发高层接口（任务 14.1）。
//
// 设计依据（design.md §「方向五：LSP_Server / LSP_Binding」）：
//   pub fn decode_message(bytes : Bytes) -> Result[JsonRpcMessage, RpcError]
//   pub fn encode_message(msg : JsonRpcMessage) -> Bytes        // round-trip 配套
//   pub fn dispatch(msg : JsonRpcMessage, router : Router) -> JsonRpcMessage?
//
// 本文件实现三个高层接口（骨架）：
//   * decode_message —— 字节 → JSON-RPC 消息；非法消息返回**符合规范**的
//     `RpcError`（标准错误码），以 `Result::Err` 承载而不终止进程（R5.3）。
//   * encode_message —— JSON-RPC 消息 → 字节，作为 decode 的 round-trip 配套。
//   * dispatch       —— 按 method 路由到处理器；方法未找到时合成规范错误响应。

// ───────────────────────────── 解码 ─────────────────────────────────

///|
/// 将一段字节解码为 JSON-RPC 2.0 消息（Requirement 5.1 / 5.2）。
///
/// 失败契约（Requirement 5.3）：
///   * 无法解析为合法 JSON → `Err(parse_error_code, ...)`；
///   * JSON 合法但不符合 JSON-RPC 2.0 结构（顶层非对象、缺失或非法 `jsonrpc`、
///     `method` 非字符串、`id` 非法、响应未恰含 result/error 其一等）
///     → `Err(invalid_request_code, ...)`。
/// 任一失败均以 `Result::Err` 返回结构化错误，**不**通过 panic/abort 终止进程。
pub fn decode_message(bytes : Bytes) -> Result[JsonRpcMessage, RpcError] {
  let text = bytes_to_text(bytes)
  let json = match parse_json(text) {
    Some(j) => j
    None =>
      return Err(RpcError::new(parse_error_code, "Parse error: invalid JSON"))
  }
  let obj = match json {
    JObj(fields) => fields
    _ =>
      return Err(
        RpcError::new(
          invalid_request_code, "Invalid Request: top-level value must be a JSON object",
        ),
      )
  }
  // JSON-RPC 2.0 要求 `jsonrpc` 字段恰为 "2.0"。
  match json_obj_get(obj, "jsonrpc") {
    Some(JStr("2.0")) => ()
    _ =>
      return Err(
        RpcError::new(
          invalid_request_code, "Invalid Request: missing or invalid \"jsonrpc\" (must be \"2.0\")",
        ),
      )
  }
  let id_field = json_obj_get(obj, "id")
  match json_obj_get(obj, "method") {
    Some(JStr(method)) => {
      // 请求或通知：params 缺省视为 JNull。
      let params = match json_obj_get(obj, "params") {
        Some(p) => p
        None => JNull
      }
      match id_field {
        None => Ok(Notification(method~, params~)) // 无 id → 通知
        Some(idj) =>
          match parse_id(idj) {
            Some(id) => Ok(Request(id~, method~, params~))
            None =>
              Err(
                RpcError::new(
                  invalid_request_code, "Invalid Request: \"id\" must be a string, integer, or null",
                ),
              )
          }
      }
    }
    Some(_) =>
      Err(
        RpcError::new(
          invalid_request_code, "Invalid Request: \"method\" must be a string",
        ),
      )
    None =>
      // 无 method：按响应处理（须含 id 且 result/error 恰有其一）。
      match id_field {
        None =>
          Err(
            RpcError::new(
              invalid_request_code, "Invalid Request: missing \"method\" or \"id\"",
            ),
          )
        Some(idj) =>
          match parse_id(idj) {
            None =>
              Err(
                RpcError::new(
                  invalid_request_code, "Invalid Request: \"id\" must be a string, integer, or null",
                ),
              )
            Some(id) => {
              let result = json_obj_get(obj, "result")
              let error = match json_obj_get(obj, "error") {
                None => None
                Some(ej) =>
                  match parse_rpc_error(ej) {
                    Some(e) => Some(e)
                    None =>
                      return Err(
                        RpcError::new(
                          invalid_request_code, "Invalid Request: malformed \"error\" object",
                        ),
                      )
                  }
              }
              match (result, error) {
                (Some(_), None) => Ok(Response(id~, result~, error~))
                (None, Some(_)) => Ok(Response(id~, result~, error~))
                _ =>
                  Err(
                    RpcError::new(
                      invalid_request_code, "Invalid Request: response must contain exactly one of \"result\" or \"error\"",
                    ),
                  )
              }
            }
          }
      }
  }
}

///|
/// 将 JSON 值还原为消息标识 `Id`：字符串 → `IdStr`、整数 → `IdNum`、null →
/// `IdNull`；其余（含小数 / 指数数值）视为非法返回 `None`。
fn parse_id(j : Json) -> Id? {
  match j {
    JStr(s) => Some(IdStr(s))
    JNull => Some(IdNull)
    JNum(s) =>
      match parse_int_literal(s) {
        Some(n) => Some(IdNum(n))
        None => None
      }
    _ => None
  }
}

///|
/// 将 JSON 值还原为错误对象 `RpcError`：要求是对象，且含整数 `code` 与字符串
/// `message`，可选 `data`；否则返回 `None`。
fn parse_rpc_error(j : Json) -> RpcError? {
  match j {
    JObj(fields) => {
      let code = match json_obj_get(fields, "code") {
        Some(JNum(s)) => parse_int_literal(s)
        _ => None
      }
      let message = match json_obj_get(fields, "message") {
        Some(JStr(m)) => Some(m)
        _ => None
      }
      match (code, message) {
        (Some(c), Some(m)) =>
          Some({ code: c, message: m, data: json_obj_get(fields, "data") })
        _ => None
      }
    }
    _ => None
  }
}

// ───────────────────────────── 编码 ─────────────────────────────────

///|
/// 将 JSON-RPC 2.0 消息编码为字节，作为 `decode_message` 的 round-trip 配套
/// （Property 11，任务 14.3）。始终写出 `jsonrpc: "2.0"`，字段顺序确定。
pub fn encode_message(msg : JsonRpcMessage) -> Bytes {
  text_to_bytes(print_json(message_to_json(msg)))
}

///|
/// 将消息映射为 JSON 值（确定的字段顺序，便于确定性序列化与往返）。
fn message_to_json(msg : JsonRpcMessage) -> Json {
  match msg {
    Request(id~, method~, params~) =>
      JObj([
        ("jsonrpc", JStr("2.0")),
        ("id", id_to_json(id)),
        ("method", JStr(method)),
        ("params", params),
      ])
    Notification(method~, params~) =>
      JObj([
        ("jsonrpc", JStr("2.0")),
        ("method", JStr(method)),
        ("params", params),
      ])
    Response(id~, result~, error~) => {
      let fields : Array[(String, Json)] = [
        ("jsonrpc", JStr("2.0")),
        ("id", id_to_json(id)),
      ]
      match result {
        Some(r) => fields.push(("result", r))
        None => ()
      }
      match error {
        Some(e) => fields.push(("error", rpc_error_to_json(e)))
        None => ()
      }
      JObj(fields)
    }
  }
}

///|
/// 将消息标识 `Id` 编码为 JSON 值。
fn id_to_json(id : Id) -> Json {
  match id {
    IdNum(n) => JNum(n.to_string())
    IdStr(s) => JStr(s)
    IdNull => JNull
  }
}

///|
/// 将错误对象 `RpcError` 编码为 JSON 对象。
fn rpc_error_to_json(e : RpcError) -> Json {
  let fields : Array[(String, Json)] = [
    ("code", JNum(e.code.to_string())),
    ("message", JStr(e.message)),
  ]
  match e.data {
    Some(d) => fields.push(("data", d))
    None => ()
  }
  JObj(fields)
}

// ───────────────────────────── 分发 ─────────────────────────────────

///|
/// 按 `method` 将消息分发到 `router` 中登记的处理器（Requirement 5.2）。
///
///   * 请求（Request）：命中处理器 → 返回其结果（`Some(响应)` 或 `None`）；
///     未命中 → 合成规范的「方法未找到」错误响应（method_not_found_code）。
///   * 通知（Notification）：命中处理器则调用（结果丢弃，通知无响应）；返回 `None`。
///   * 响应（Response）：服务端不分发响应，返回 `None`。
pub fn dispatch(msg : JsonRpcMessage, router : Router) -> JsonRpcMessage? {
  match msg {
    Request(id~, method~, ..) =>
      match router.lookup(method) {
        Some(handler) => handler(msg)
        None =>
          Some(
            error_response(
              id,
              method_not_found_code,
              "Method not found: " + method,
            ),
          )
      }
    Notification(method~, ..) =>
      match router.lookup(method) {
        Some(handler) => {
          let _ = handler(msg)
          None
        }
        None => None
      }
    Response(..) => None
  }
}
