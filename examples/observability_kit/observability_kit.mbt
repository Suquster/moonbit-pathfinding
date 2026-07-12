// examples/observability_kit — runnable demonstration of the
// `src/infra_metrics` direction as a service-latency dashboard: record
// request latencies into an HDR histogram, read tail percentiles, merge
// per-shard DDSketches with bounded relative error, and profile a request
// with a span tracer (total vs self time).
//
// Run with:
//   moon run examples/observability_kit

///|
fn main {
  println("=== 1. HDR histogram latency percentiles ===")
  let hdr = @metrics.HdrHistogram::new(3)
  // simulate 1000 requests: mostly fast, a slow tail
  for i in 0..<1000 {
    let latency = if i % 100 == 0 {
      (900 + i / 10).to_int64() // 1% slow outliers
    } else {
      (10 + i % 40).to_int64() // 10-49 ms steady state
    }
    hdr.record(latency)
  }
  println("count : \{hdr.count()}, max: \{hdr.max_value()} ms")
  for p in [50.0, 90.0, 99.0, 99.9] {
    match hdr.value_at_percentile(p) {
      Some(v) => println("p\{p} : \{v} ms")
      None => println("p\{p} : n/a")
    }
  }
  println("")
  println("=== 2. mergeable DDSketch across shards ===")
  let shard_a = @metrics.DDSketch::new(0.01)
  let shard_b = @metrics.DDSketch::new(0.01)
  for i in 0..<500 {
    shard_a.add(10.0 + (i % 50).to_double())
    shard_b.add(200.0 + (i % 300).to_double())
  }
  shard_a.merge_with(shard_b)
  println(
    "merged count : \{shard_a.count()} (error bound \{shard_a.error_bound()})",
  )
  match shard_a.quantile(0.5) {
    Some(q) => println("merged p50   : \{q}")
    None => println("merged p50   : n/a")
  }
  match shard_a.quantile(0.99) {
    Some(q) => println("merged p99   : \{q}")
    None => println("merged p99   : n/a")
  }
  println("")
  println("=== 3. span tracer: total vs self time ===")
  let tracer = @metrics.SpanTracer::new()
  let root = tracer.start("handle_request", 0)
  let _db = tracer.start("db_query", 10)
  let _ = tracer.end(60) // db_query: 50ms
  let _render = tracer.start("render", 65)
  let _ = tracer.end(90) // render: 25ms
  let _ = tracer.end(100) // handle_request: 100ms total
  println("finished spans: \{tracer.finished_count()}")
  for name in tracer.stat_names() {
    match tracer.stat(name) {
      Some((calls, total, self_time)) =>
        println(
          "\{name}: calls=\{calls}, total=\{total}ms, self=\{self_time}ms",
        )
      None => ()
    }
  }
  let children = tracer.children_of(root)
  println("root has \{children.length()} child spans")
}
