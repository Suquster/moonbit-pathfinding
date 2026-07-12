// examples/log_pipeline — runnable demonstration of the `src/logging`
// direction as a realistic request-handling pipeline: distributed tracing
// spans with W3C traceparent propagation, structured events rendered as
// JSON and logfmt, PII redaction before shipping, and level accounting.
//
// Run with:
//   moon run examples/log_pipeline

///|
fn simulate_request(user : String, ok : Bool) -> Unit {
  let span = @log.enter_span("handle_request")
  @log.log(Info, {
    "msg": VStr("request received"),
    "user": VStr(user),
    "password": VStr("hunter2"),
  })
  let inner = @log.enter_span("route_lookup")
  @log.log(Debug, {
    "msg": VStr("routing"),
    "algo": VStr("bidirectional_dijkstra"),
  })
  @log.exit_span(inner)
  if ok {
    @log.log(Info, { "msg": VStr("request ok"), "status": VInt(200) })
  } else {
    @log.log(Error, { "msg": VStr("upstream failed"), "status": VInt(502) })
  }
  @log.exit_span(span)
}

///|
fn main {
  @log.reset_logger()
  let trace = @log.begin_trace()
  println("=== distributed tracing ===")
  println("trace id     : \{trace.value}")
  simulate_request("alice", true)
  simulate_request("mallory", false)
  let ctx = @log.capture_context()
  println("traceparent  : \{@log.inject_traceparent(ctx)}")
  println("finished spans: \{@log.finished_spans().length()}")
  println("")
  let events = @log.captured_events()
  println("=== formatting: same event, three renderers ===")
  let first = events[0]
  println("json  : \{@log.format_json(first)}")
  println("logfmt: \{@log.format_logfmt(first)}")
  println("pretty: \{@log.format_pretty(first)}")
  println("")
  println("=== redaction before shipping ===")
  let policy = @log.RedactionPolicy::by_names(["password", "token"])
  let scrubbed = @log.redact(policy, first)
  println("scrubbed: \{@log.format_logfmt(scrubbed)}")
  println("")
  println("=== env filter: module thresholds like RUST_LOG ===")
  match @log.parse_env_filter("warn,router=debug") {
    Ok(filter) => {
      println("directive 'warn,router=debug':")
      let fallback = filter.fallback.label()
      let router = filter.threshold_for("router").label()
      println("  fallback threshold: \{fallback}, router threshold: \{router}")
    }
    Err(e) => println("filter error at \{e.pos}: \{e.message}")
  }
  println("")
  println("=== level accounting ===")
  let counts = @log.count_by_level(events)
  for level in ([Trace, Debug, Info, Warn, Error] : Array[@log.Level]) {
    println("  \{level.label()}: \{@log.level_count(counts, level)}")
  }
}
