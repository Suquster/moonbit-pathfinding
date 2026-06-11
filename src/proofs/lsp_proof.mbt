// lsp_proof.mbt —— LSP_Binding / LSP_Server（R5）方向的证明谓词占位。
//
// 复用约定：JSON-RPC 消息往返复用 `round_trip_eq`；本文件补充方向特有的
// 「非法消息不终止进程」错误条件最小占位谓词。谓词均为纯、全（total）。
// 升级路径：任务 14.x 引入真实 `JsonRpcMessage` 后替换占位。

///|
/// 非法消息不终止进程（占位）。
///
/// 当且仅当：进程保持存活（`process_alive`），且消息合法或已返回符合规范的
/// 错误响应（`is_valid || error_responded`）时成立。
pub fn illegal_message_keeps_alive(
  is_valid : Bool,
  error_responded : Bool,
  process_alive : Bool,
) -> Bool {
  process_alive && (is_valid || error_responded)
}
