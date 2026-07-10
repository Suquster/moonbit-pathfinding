// lsp_proof.mbt —— LSP_Binding / LSP_Server（R5）方向的契约谓词。
//
// 复用约定：JSON-RPC 消息往返复用 `round_trip_eq`；本文件补充方向特有的
// 「非法消息不终止进程」错误条件谓词。真实 JSON-RPC 分发测试投影消息合法性、
// 错误响应与进程存活状态；谓词保持纯、全（total）。

///|
/// 非法消息不终止进程。
///
/// 当且仅当：进程保持存活（`process_alive`），且消息合法或已返回符合规范的
/// 错误响应（`is_valid || error_responded`）时成立。这刻画了 JSON-RPC 服务
/// 「畸形输入也绝不崩溃、而是返回结构化错误」的鲁棒性契约（R2.3 / R11.3）。
/// 纯、全函数，对任意三布尔组合恒返回 `Bool`。
pub fn illegal_message_keeps_alive(
  is_valid : Bool,
  error_responded : Bool,
  process_alive : Bool,
) -> Bool {
  process_alive && (is_valid || error_responded)
}
