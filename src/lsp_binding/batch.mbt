// batch.mbt —— JSON-RPC 2.0 批量请求（Batch）解码、逐条分发与编码（任务 2.1，
// 旁路新增）。
//
// paper-to-code 来源（JSON-RPC 2.0 Specification §6「Batch」）：
//   当客户端需要一次性发送多个 Request 对象时，可将其放入一个**顶层 JSON 数组**
//   中发送。服务端应**按出现顺序**处理数组中的每个元素（每个元素是一个 Request
//   或 Notification），并将各 Request 的 Response 对象放入一个**响应数组**返回；
//   Notification 不产生响应，故从响应数组中略去。数组中某一元素非法不应影响其余
//   元素的处理——非法元素就地产生一个对应的错误，其余元素正常处理。
//   参见 JSON-RPC 2.0 §6 与 §4.2「Notification」。
//
// 设计原则（design.md §3.2「批量请求」）：本模块与既有单条 `decode_message` /
// `dispatch` / `encode_message` **正交且复用**——批量只负责「顶层数组 ⇄ 逐元素
// 消息」的拆分与汇集，单条语义一律复用冻结接口，既有单条 `dispatch` 行为不变。
//
// 实现复用 json.mbt 的包内私有 helper（同包不同文件，私有 `fn` 在同包内可见）：
//   * `parse_json` / `print_json` —— 顶层数组的解析与编码；
//   * `bytes_to_text` / `text_to_bytes` —— 逐字节（ASCII）字节↔文本互转；
// 以及 binding.mbt 的私有 `message_to_json`，使批量编码与既有 `encode_message`
// 的字段顺序、序列化策略逐字节一致。
//
// 三后端一致性：输出响应数组的顺序仅由「输入消息的出现顺序」决定（确定性遍历），
// 不依赖任何哈希顺序；全部逐字节（ASCII）处理，无浮点、无平台相关 API。

// ───────────────────────────── 批量解码 ───────────────────────────────

///|
/// 解码顶层为数组的批量请求（Requirement 2.4）。
///
///   * 顶层须为 JSON 数组：按出现顺序对每个元素**重新打印为正文字节**后交既有
///     `decode_message` 解码，得到该元素的 `Result[JsonRpcMessage, RpcError]`；
///   * 某元素非法（不符合 JSON-RPC 2.0 结构）→ 就地标记为该元素的 `Err`，**不**
///     影响其余元素的解码（稳健性，Requirement 2.4）；
///   * 顶层无法解析为合法 JSON → `Err(parse_error_code, ..)`；
///   * 顶层为合法 JSON 但**非数组** → `Err(invalid_request_code, ..)`（顶层错误）。
///
/// 失败均以 `Result::Err` 承载结构化错误，绝不 panic/abort，也不产出半成品消息。
pub fn decode_batch(
  bytes : Bytes,
) -> Result[Array[Result[JsonRpcMessage, RpcError]], RpcError] {
  let text = bytes_to_text(bytes)
  let json = match parse_json(text) {
    Some(j) => j
    None =>
      return Err(RpcError::new(parse_error_code, "Parse error: invalid JSON"))
  }
  match json {
    JArr(items) => {
      let results : Array[Result[JsonRpcMessage, RpcError]] = []
      for it in items {
        // 逐元素重新打印为正文字节再交既有 decode_message 解码，保持与单条
        // 解码语义逐字节一致；元素非法就地标记为该元素 Err。
        let body = text_to_bytes(print_json(it))
        results.push(decode_message(body))
      }
      Ok(results)
    }
    _ =>
      Err(
        RpcError::new(
          invalid_request_code, "Invalid Request: batch top-level value must be a JSON array",
        ),
      )
  }
}

// ───────────────────────────── 逐条分发 ───────────────────────────────

///|
/// 对一批消息按出现顺序逐条复用冻结的单条 `dispatch`，将各请求的响应按对应顺序
/// 汇集为响应数组（Requirement 2.4 / 2.10）。
///
///   * 请求（Request）：`dispatch` 命中处理器返回其结果、未命中合成 `method
///     _not_found_code` 错误响应——产生 `Some(响应)` 则按序收入响应数组；
///   * 通知（Notification）：`dispatch` 返回 `None`，按 JSON-RPC 规范从响应数组
///     中略去；
///   * 响应（Response）：`dispatch` 返回 `None`，同样略去。
///
/// 不改既有单条 `dispatch` 语义；响应顺序仅由输入消息出现顺序决定（确定性）。
pub fn dispatch_batch(
  msgs : Array[JsonRpcMessage],
  router : Router,
) -> Array[JsonRpcMessage] {
  let responses : Array[JsonRpcMessage] = []
  for m in msgs {
    match dispatch(m, router) {
      Some(resp) => responses.push(resp)
      None => () // 通知 / 产生 None 的项略去。
    }
  }
  responses
}

// ───────────────────────────── 批量编码 ───────────────────────────────

///|
/// 将一批响应消息编码为 JSON **顶层数组**字节（与既有 `encode_message` 的字段
/// 顺序与序列化策略逐字节一致：复用私有 `message_to_json` + `print_json`）。
pub fn encode_batch(responses : Array[JsonRpcMessage]) -> Bytes {
  let items : Array[Json] = []
  for r in responses {
    items.push(message_to_json(r))
  }
  text_to_bytes(print_json(JArr(items)))
}
