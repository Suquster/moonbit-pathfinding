// cancel.mbt —— 请求取消登记表与取消响应（任务 3.1，旁路新增）。
//
// 设计依据（design.md §3.2「取消与 id 关联（cancel.mbt / correlate.mbt）」）：
//   pub let request_cancelled_code : Int = -32800
//   pub struct CancelRegistry { cancelled : Map[String, Bool] }
//   pub fn CancelRegistry::new() -> Self
//   pub fn CancelRegistry::cancel(Self, Id) -> Self
//   pub fn CancelRegistry::is_cancelled(Self, Id) -> Bool
//   pub fn cancel_id_of(params : Json) -> Id?
//   pub fn cancelled_response(id : Id) -> JsonRpcMessage
//
// paper-to-code 追溯：
//   * LSP 规范「$/cancelRequest」通知 —— 客户端发送携带待取消请求 `id` 的通知，
//     服务端「应当」令该进行中请求以「请求已取消」错误响应收场。
//   * LSP 规范错误码 `RequestCancelled = -32800`（在 JSON-RPC 2.0 五个标准错误码
//     之外新增；本文件以**新增公开常量**承载，不改既有五个错误码的值与语义）。
//
// 实现边界（design.md §「取消为协作式语义模型」）：本文件以「取消登记表 + id 标记」
// 的**纯数据模型**表达取消「应当」发生的结果（返回取消错误响应），不涉及抢占式
// 中断真实线程或异步运行时。`CancelRegistry` 为不可变值：`cancel` 返回携带新标记
// 的新实例，原实例不变，确保三后端（wasm-gc / js / native）逐位一致。

// ───────────────────────────── 取消错误码 ─────────────────────────────

///|
/// LSP 规范定义的「请求已取消」错误码（RequestCancelled）。
///
/// 这是**新增**公开常量，独立于 JSON-RPC 2.0 五个标准错误码
/// （parse_error_code / invalid_request_code / method_not_found_code /
/// invalid_params_code / internal_error_code），后者的值与语义保持冻结。
pub let request_cancelled_code : Int = -32800

// ───────────────────────────── id 规范字符串键 ────────────────────────

///|
/// 将消息标识 `Id` 映射为规范字符串键，用于在登记表中无歧义地标记取消。
///
/// 不同变体使用不同前缀以保证互不碰撞：`IdNum(n)` → `"n:<n>"`、
/// `IdStr(s)` → `"s:<s>"`、`IdNull` → `"null"`。例如数值 id `1`（键 `"n:1"`）
/// 与字符串 id `"1"`（键 `"s:1"`）不会相互混淆。
fn id_key(id : Id) -> String {
  match id {
    IdNum(n) => "n:" + n.to_string()
    IdStr(s) => "s:" + s
    IdNull => "null"
  }
}

// ───────────────────────────── 取消登记表 ─────────────────────────────

///|
/// 取消登记表：以 `Id` 的规范字符串键标记哪些进行中请求「应当」被取消。
///
/// 纯函数式不可变值——`cancel` 返回携带新标记的新实例，原实例不被修改。
pub struct CancelRegistry {
  cancelled : Map[String, Bool]
}

///|
/// 构造一个空的取消登记表（无任何 id 被标记取消）。
pub fn CancelRegistry::new() -> CancelRegistry {
  { cancelled: Map::new() }
}

///|
/// 将某 `id` 标记为已取消，返回携带该新标记的**新**登记表（原实例不变）。
pub fn CancelRegistry::cancel(self : CancelRegistry, id : Id) -> CancelRegistry {
  let next : Map[String, Bool] = Map::new()
  for k, v in self.cancelled {
    next[k] = v
  }
  next[id_key(id)] = true
  { cancelled: next }
}

///|
/// 查询某 `id` 是否已被标记取消；未标记返回 `false`。
pub fn CancelRegistry::is_cancelled(self : CancelRegistry, id : Id) -> Bool {
  match self.cancelled.get(id_key(id)) {
    Some(b) => b
    None => false
  }
}

// ───────────────────────────── $/cancelRequest ────────────────────────

///|
/// 从 `$/cancelRequest` 通知的 `params` 中取出待取消的请求 `id`。
///
/// LSP 约定 params 形如 `{"id": <id>}`，其中 `<id>` 为数值、字符串或 null。
/// 复用 `parse_id` 将其还原为 `IdNum` / `IdStr` / `IdNull`；params 非对象、
/// 缺 `id` 字段或 `id` 非法（如小数 / 指数数值）时返回 `None`。
pub fn cancel_id_of(params : Json) -> Id? {
  match params {
    JObj(fields) =>
      match json_obj_get(fields, "id") {
        Some(j) => parse_id(j)
        None => None
      }
    _ => None
  }
}

///|
/// 为一个被取消的进行中请求合成取消错误响应：携带 `request_cancelled_code`
/// 且其 `id` 与原请求 `id` 相等（满足 id 关联）。
pub fn cancelled_response(id : Id) -> JsonRpcMessage {
  error_response(id, request_cancelled_code, "Request cancelled")
}
