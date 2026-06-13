// demo.mbt —— 端到端实战追踪链路 demo（任务 13.1 / 13.2）。
//
// 设计依据：design.md §4.10「端到端实战 demo」（Requirement 11.*）。串联旗舰
// 深化的全部能力，演示一次请求处理链路从开 trace 到跨进程传播的完整流程：
//
//   begin_trace → 嵌套 enter_span/exit_span + OTel 属性/事件/状态/kind
//     → 采样（sample_stream） + 脱敏（redact）
//     → JSON 与 logfmt 双格式渲染
//     → traceparent 注入（供下游提取续记）
//
//   * `run_demo()` —— 父进程链路，返回 `DemoOutcome`（trace / 双格式行 /
//     traceparent / span 数）；
//   * `run_downstream(traceparent)` —— 模拟下游进程：从 traceparent 提取上下文
//     并在其下续记，返回下游事件的 trace-id（与父进程同 trace-id，Requirement 11.3）。

///|
/// 端到端 demo 产出工件（Requirement 11.1 / 11.2）。
pub(all) struct DemoOutcome {
  trace : TraceId
  json_lines : Array[String]
  logfmt_lines : Array[String]
  traceparent : String
  span_count : Int
} derive(Eq, Show)

///|
/// 运行父进程实战链路（Requirement 11.1 / 11.2）。
pub fn run_demo() -> DemoOutcome {
  reset_logger()
  let trace = begin_trace()
  // 根 span（Server kind）+ OTel 属性。
  let root = enter_span("http.request")
  let root_data = SpanData::new(root)
  root_data.set_kind(SpanKind::Server)
  root_data.set_attribute("http.method", VStr("GET"))
  root_data.set_attribute("http.route", VStr("/api/users/{id}"))
  // 捕获上下文（trace + 根 span）供跨进程传播。
  let propagated = capture_context()
  // 根 span 内记录：含嵌套字段与敏感字段（password）。
  log(Level::Info, {
    "msg": VStr("request received"),
    "password": VStr("hunter2"),
    "headers": VMap({ "accept": VStr("application/json") }),
  })
  // 嵌套子 span（db.query，Client kind）+ span 事件。
  let db = enter_span("db.query")
  let db_data = SpanData::new(db)
  db_data.set_kind(SpanKind::Client)
  db_data.set_attribute("db.system", VStr("postgres"))
  db_data.add_event("query.start", db.start, { "sql": VStr("SELECT 1") })
  log(Level::Debug, {
    "msg": VStr("query executed"),
    "rows": VInt(3L),
    "token": VStr("secret-bearer"),
  })
  db_data.set_status(SpanStatus::Ok)
  exit_span(db)
  log(Level::Warn, { "msg": VStr("slow response"), "latency_ms": VInt(150L) })
  exit_span(root)
  let span_count = finished_spans().length()
  // 采样（rate=1.0 保留全部，保证 demo 输出确定且非空）+ 脱敏 + 双格式渲染。
  let sampled = sample_stream(1.0, captured_events(), @infra_pbt.rng_new(2026UL))
  let policy = RedactionPolicy::by_names(["password", "token"])
  let json_lines : Array[String] = []
  let logfmt_lines : Array[String] = []
  for e in sampled {
    let red = redact(policy, e)
    json_lines.push(format_json(red))
    logfmt_lines.push(format_logfmt(red))
  }
  // 从捕获的（根 span）上下文注入 traceparent，供下游跨进程提取。
  let traceparent = inject_traceparent(propagated)
  { trace, json_lines, logfmt_lines, traceparent, span_count }
}

///|
/// 模拟下游进程：从 traceparent 提取上下文并在其下续记（Requirement 11.3）。
///
/// 返回下游事件的 trace-id；与父进程 `run_demo` 的 trace-id 一致（同一 trace）。
/// traceparent 非法则返回 `None`。
pub fn run_downstream(traceparent : String) -> TraceId? {
  match extract_traceparent(traceparent) {
    Some(w) => {
      let ctx = w.to_trace_context()
      let tid = with_context(ctx, fn() {
        log(Level::Info, { "msg": VStr("downstream handling") })
        current_trace()
      })
      Some(tid)
    }
    None => None
  }
}
