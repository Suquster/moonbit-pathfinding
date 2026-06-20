// correlate.mbt —— 请求—响应 id 关联工具（任务 3.2，旁路新增）。
//
// 设计依据（design.md §3.2「取消与 id 关联（cancel.mbt / correlate.mbt）」）：
//   pub fn id_of(msg : JsonRpcMessage) -> Id?                // 请求/响应的 id；通知为 None
//   pub fn correlate(request : JsonRpcMessage, response : JsonRpcMessage) -> Bool  // id 相等校验
//
// paper-to-code 追溯：
//   * JSON-RPC 2.0 §5 Response object —— 响应的 `id` 必须与触发它的请求 `id` 相等，
//     用于在并发/批量场景下把响应匹配回对应请求；通知（Notification）无 `id`，不期待响应。
//
// 实现边界：纯函数、无状态、无 IO，确保三后端（wasm-gc / js / native）逐位一致。
// 与既有 decode/encode/dispatch 正交，不改任何既有行为。

// ───────────────────────────── id 提取 ────────────────────────────────

///|
/// 取出一条消息的标识 `id`：`Request` 与 `Response` 携带 `id` 返回 `Some(id)`；
/// `Notification` 无 id，返回 `None`。
pub fn id_of(msg : JsonRpcMessage) -> Id? {
  match msg {
    Request(id~, ..) => Some(id)
    Response(id~, ..) => Some(id)
    Notification(..) => None
  }
}

// ───────────────────────────── id 关联校验 ────────────────────────────

///|
/// 校验一条响应是否关联到某请求：当二者均携带 `id`（即 `id_of` 皆为 `Some`）
/// 且 `id` 相等时返回 `true`，否则返回 `false`。
///
/// 任一方为通知（无 id）或二者 id 不等，均判定不关联。`Id` derive(Eq)，故
/// 直接以相等比较。
pub fn correlate(request : JsonRpcMessage, response : JsonRpcMessage) -> Bool {
  match (id_of(request), id_of(response)) {
    (Some(req_id), Some(resp_id)) => req_id == resp_id
    _ => false
  }
}
