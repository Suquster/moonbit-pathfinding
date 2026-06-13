// benches/logging_bench — Logging_Library 旗舰深化的原生基准与回归 guard。
//
// 对应 design.md §4.11（R9）。四类工作负载：
//   ① 高频 log（大批量事件发射 + 级别过滤）；
//   ② 格式化（JSON 与 logfmt 渲染于不同字段规模）；
//   ③ 采样判定（sample_trace 于大量 trace、sample_stream 于大事件流）；
//   ④ span 进入/退出（深 span 树）。
// 冒烟 / 回归 guard 在大规模负载上对确定性不变量精确比较（R9.1/9.2/9.3）。
//
// _Requirements: 9.1, 9.2, 9.3, 9.4_

// ---------------------------------------------------------------------------
// 工作负载构造
// ---------------------------------------------------------------------------

///|
/// 构造 `n` 条带字段的事件（级别按 i mod 5 轮转，覆盖全部级别）。
fn build_events(n : Int) -> Array[@log.Event] {
  let levels = [
    @log.Level::Trace,
    @log.Level::Debug,
    @log.Level::Info,
    @log.Level::Warn,
    @log.Level::Error,
  ]
  let out : Array[@log.Event] = []
  for i in 0..<n {
    let fields : Map[String, @log.Value] = {
      "i": @log.Value::VInt(i.to_int64()),
      "msg": @log.Value::VStr("event payload"),
      "ok": @log.Value::VBool(i % 2 == 0),
      "ratio": @log.Value::VFloat(0.5),
    }
    out.push(@log.Event::new(i.to_int64(), levels[i % 5], fields))
  }
  out
}

// ---------------------------------------------------------------------------
// 冒烟 guard（correctness）：大规模负载核心不变量
// ---------------------------------------------------------------------------

///|
/// Smoke: 高频 log（2000 条，阈值 Info）保留计数等于 Info+ 级别事件数。
test "smoke: high-frequency log respects threshold at scale" {
  @log.reset_logger()
  @log.set_threshold(@log.Level::Info)
  let n = 2000
  let levels = [
    @log.Level::Trace,
    @log.Level::Debug,
    @log.Level::Info,
    @log.Level::Warn,
    @log.Level::Error,
  ]
  for i in 0..<n {
    @log.log(levels[i % 5], { "i": @log.Value::VInt(i.to_int64()) })
  }
  // i%5 ∈ {2,3,4} 即 Info/Warn/Error 被保留：每 5 个中 3 个 → 1200 条。
  assert_eq(@log.captured_events().length(), 1200)
  @log.reset_logger()
}

///|
/// Smoke: 1000 条事件 JSON / logfmt 渲染非空且 logfmt 往返（标量域）。
test "smoke: format json and logfmt at scale" {
  let events = build_events(1000)
  for e in events {
    let j = @log.format_json(e)
    assert_true(j.length() > 0)
    let l = @log.format_logfmt(e)
    // logfmt 标量域往返还原等价事件。
    assert_true(@log.parse_logfmt(l) == Some(e))
  }
}

// ---------------------------------------------------------------------------
// 回归 guard（R9.3）：确定性输出内联基线
// ---------------------------------------------------------------------------

///|
/// Guard: 系统采样保留条数 == floor(rate*n)（精确基线）。
test "guard: sample_stream retained count matches floor(rate*n)" {
  let events = build_events(1000)
  let kept = @log.sample_stream(0.25, events, @pbt.rng_new(7UL)).length()
  if kept != 250 {
    fail(
      "LOGGING-BENCH GUARD FAIL [sample-count]: 保留条数 " +
      kept.to_string() +
      " 偏离基线 250（rate=0.25, n=1000）。",
    )
  }
  if @log.retained_count(0.25, 1000) != 250 {
    fail(
      "LOGGING-BENCH GUARD FAIL [retained-count]: retained_count 偏离基线 250。",
    )
  }
}

///|
/// Guard: 计数守恒——各级别计数之和 == 事件总数（精确基线 1000）。
test "guard: count_by_level conserves total at scale" {
  let events = build_events(1000)
  let counts = @log.count_by_level(events)
  let mut sum = 0
  for c in counts {
    sum = sum + c
  }
  if sum != 1000 {
    fail(
      "LOGGING-BENCH GUARD FAIL [counter-conservation]: 计数之和 " +
      sum.to_string() +
      " 偏离基线 1000。",
    )
  }
}

///|
/// Guard: 固定事件的 JSON 渲染字节级稳定（防渲染回归）。
test "guard: format_json byte-stable for a fixed event" {
  let e = @log.Event::new(7L, @log.Level::Warn, {
    "msg": @log.Value::VStr("hi"),
    "count": @log.Value::VInt(42L),
  })
  let expected = "{\"ts\":7,\"level\":\"WARN\",\"fields\":{\"msg\":\"hi\",\"count\":42}}"
  let actual = @log.format_json(e)
  if actual != expected {
    fail(
      "LOGGING-BENCH GUARD FAIL [json-bytes]: 渲染 `" +
      actual +
      "` 偏离基线 `" +
      expected +
      "`。",
    )
  }
}

// ---------------------------------------------------------------------------
// 原生基准（@bench.T）：四类工作负载（moon bench 下执行）
// ---------------------------------------------------------------------------

///|
/// ① 高频 log：5000 条事件发射（阈值 Trace，全部保留）。
test "bench: high-frequency log" (b : @bench.T) {
  b.bench(name="log_emit_5000", fn() {
    @log.reset_logger()
    for i in 0..<5000 {
      @log.log(@log.Level::Info, { "i": @log.Value::VInt(i.to_int64()) })
    }
    b.keep(@log.captured_events().length())
  })
  @log.reset_logger()
}

///|
/// ② 格式化：1000 条事件的 JSON 与 logfmt 渲染。
test "bench: format json and logfmt" (b : @bench.T) {
  let events = build_events(1000)
  b.bench(name="format_json_1000", fn() {
    let mut acc = 0
    for e in events {
      acc = acc + @log.format_json(e).length()
    }
    b.keep(acc)
  })
  b.bench(name="format_logfmt_1000", fn() {
    let mut acc = 0
    for e in events {
      acc = acc + @log.format_logfmt(e).length()
    }
    b.keep(acc)
  })
}

///|
/// ③ 采样判定：sample_trace 于 10000 个 trace、sample_stream 于 2000 事件流。
test "bench: sampling decisions" (b : @bench.T) {
  let events = build_events(2000)
  b.bench(name="sample_trace_10000", fn() {
    let mut kept = 0
    for i in 0..<10000 {
      if @log.sample_trace(0.5, { value: i.to_int64() }, 0x9e3779b9UL) {
        kept = kept + 1
      }
    }
    b.keep(kept)
  })
  b.bench(name="sample_stream_2000", fn() {
    b.keep(@log.sample_stream(0.3, events, @pbt.rng_new(11UL)).length())
  })
}

///|
/// ④ span 进入/退出：2000 层深 span 树进入再逆序退出。
test "bench: span enter and exit" (b : @bench.T) {
  b.bench(name="span_enter_exit_2000", fn() {
    @log.reset_logger()
    let _t = @log.begin_trace()
    let spans : Array[@log.Span] = []
    for i in 0..<2000 {
      spans.push(@log.enter_span("s" + i.to_string()))
    }
    for j = spans.length() - 1; j >= 0; j = j - 1 {
      @log.exit_span(spans[j])
    }
    b.keep(@log.finished_spans().length())
  })
  @log.reset_logger()
}
