// diagnostics.mbt —— 诊断模型 push + pull（任务 13.1）。
//
// 设计依据（design.md §3.6「诊断模型 push + pull」，Requirement 6.1/6.2/6.4）：
// 本文件为**旁路新增**，不改 `analyze` / `dsl.mbt` / `types.mbt` 既有行为，全部
// 能力复用既有 `analyze` 投影：
//
//   * pull 诊断（6.2） —— `textDocument/diagnostic` 请求 → 当前文档分析所得诊断
//     作为响应结果，由 `pull_diagnostics` 提供；
//   * push 诊断（6.1） —— 复用既有 `publish_diagnostics_notification`
//     （server.mbt，构造 `textDocument/publishDiagnostics` 通知），本文件不重复；
//   * 诊断 JSON 编码（6.4） —— 输出范围 + 规范严重级别码
//     （Error=1 / Warning=2 / Information=3 / Hint=4）+ 消息，由 `diagnostic_to_json`
//     提供。该编码自 `0.1.0` 起即以等价行为存在于 server.mbt（彼时私有），任务
//     13.1 将其可见性提升为 `pub`（纯追加、向后兼容），故本文件不重复定义，统一
//     从同包公开 API 复用，避免重名顶层函数冲突。
//
// paper-to-code 追溯：LSP §「Pull Diagnostics」之 `textDocument/diagnostic`，
// 与 §「Diagnostic」之 `DiagnosticSeverity`（Error=1 / Warning=2 /
// Information=3 / Hint=4）。
//
// ── push / pull 等价（Property 18） ─────────────────────────────────────
// push 路径（`on_did_change` → `analyze(doc).diagnostics`）与 pull 路径
// （`pull_diagnostics` → `analyze(doc).diagnostics`）走同一 `analyze` 投影，
// 故对同一文档二者产出的诊断集合逐条相等。
//
// ── 诊断确定性（Property 10） ───────────────────────────────────────────
// `analyze` 为纯函数（无 IO / 无全局可变状态），对同一文档多次调用产出逐条相同
// （顺序与内容一致）的诊断序列，保证 wasm-gc / js / native 三后端逐位一致。

// ───────────────────────────── pull 诊断（6.2） ───────────────────────

///|
/// pull 诊断：处理 `textDocument/diagnostic` 拉取请求，返回对应文档当前分析所得
/// 的诊断集合作为响应结果（Requirement 6.2）。
///
/// 直接复用既有 `analyze`，与 push 路径 `on_did_change` 走同一投影，从而满足
/// push / pull 诊断等价（Property 18）与诊断确定性（Property 10）。
pub fn pull_diagnostics(doc : TextDocument) -> Array[Diagnostic] {
  analyze(doc).diagnostics
}
