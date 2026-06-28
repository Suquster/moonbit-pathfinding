# logging · 可执行文档

> **方向七（R7）结构化日志与 tracing 库** — 结构化字段 · 级别过滤 · span 树与时长 · 三后端一致 · 文档即测试。
>
> 本文件既是 `logging` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/logging/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 10.5**。

本文件作为 `logging` 包的黑盒测试运行，因此可直接调用本包公开 API
（`reset_logger` / `set_threshold` / `log` / `enter_span` / `exit_span` /
`span_duration` / `captured_events` / `finished_spans` / `begin_trace` /
`format_json` / `parse_json_log` 等）而无需限定包名。下面 4 段示例覆盖
**结构化字段记录、级别阈值过滤、span 进入/退出与时长、`format_json` →
`parse_json_log` 往返**。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。

> **关于全局运行时与构造手法**：日志运行时是进程级单例，故每段示例均先调用
> `reset_logger()` 隔离全局状态（阈值、逻辑时钟、span/trace 标识源、已发射事件
> 等），保证示例间互不串扰。黑盒文档中级别经 `Level::Info` 等限定形式书写，
> 字段取值经 `Value::VStr` / `VInt` / `VBool` / `VFloat` 限定构造函数装配为
> `Map[String, Value]`。

---

## 数据模型速览

* `log(level : Level, fields : Map[String, Value]) -> Unit` —— 记录一条带键值字段的
  事件；低于阈值的级别被丢弃（**R7.2**），保留事件携带时间戳、级别与全部结构化
  字段（**R7.1**），并自动标注当前 `trace`（及激活 span 的 `span`）上下文（**R7.4**）。
* `set_threshold(level : Level) -> Unit` —— 配置最低级别阈值（**R7.2**）。
* `enter_span(name : String) -> Span` / `exit_span(s : Span) -> Unit` —— 进入/退出 span；
  子 span 关联父 span 形成 span 树（**R7.3**），退出后记录时长（**R7.5**）。
* `span_duration(s : Span) -> Int64?` —— 已结束 span 的时长（`end - start`）。
* `captured_events()` / `finished_spans()` —— 观测已发射事件与已结束 span。
* `format_json(e : Event) -> String` / `parse_json_log(s : String) -> Event?` ——
  结构化输出与其逆解析，二者构成「序列化再解析」往返（**R7.7**）。

---

## 示例 1 · 结构化字段记录 —— log 输出时间戳 + 级别 + 全部字段

`log` 把一条带键值字段的事件写入运行时（**R7.1**）：保留调用方提供的全部结构化
字段，并附带单调递增的逻辑时间戳与级别。下例记录一条带 `service` / `status` /
`ok` 三个不同取值类型字段的 `Info` 事件，随后从 `captured_events()` 取回校验。

```mbt check
///|
test "README · log 记录结构化字段与时间戳" {
  reset_logger()
  log(Level::Info, {
    "service": Value::VStr("api-gateway"),
    "status": Value::VInt(200L),
    "ok": Value::VBool(true),
  })
  let events = captured_events()
  assert_eq(events.length(), 1)
  let e = events[0]
  // 级别与时间戳（R7.1）：默认逻辑时钟自 0 起，首条事件时间戳为 1
  assert_true(e.level == Level::Info)
  assert_eq(e.ts, 1L)
  // 调用方的全部结构化字段被原样保留（R7.1）
  assert_true(e.fields.get("service") == Some(Value::VStr("api-gateway")))
  assert_true(e.fields.get("status") == Some(Value::VInt(200L)))
  assert_true(e.fields.get("ok") == Some(Value::VBool(true)))
}
```

---

## 示例 2 · 级别阈值过滤 —— 低于阈值的事件被丢弃

`set_threshold` 配置最低记录级别（**R7.2**）：严重程度低于阈值的事件被 `log`
直接丢弃，不产生任何记录。下例把阈值设为 `Warn`，则 `Trace` / `Debug` / `Info`
三条被丢弃，仅 `Warn` 与 `Error` 两条被保留。

```mbt check
///|
test "README · set_threshold 丢弃低于阈值的事件" {
  reset_logger()
  set_threshold(Level::Warn)
  log(Level::Trace, { "m": Value::VStr("trace") }) // 丢弃
  log(Level::Debug, { "m": Value::VStr("debug") }) // 丢弃
  log(Level::Info, { "m": Value::VStr("info") }) // 丢弃
  log(Level::Warn, { "m": Value::VStr("warn") }) // 保留
  log(Level::Error, { "m": Value::VStr("error") }) // 保留
  let events = captured_events()
  assert_eq(events.length(), 2)
  assert_true(events[0].level == Level::Warn)
  assert_true(events[1].level == Level::Error)
}
```

---

## 示例 3 · span 进入/退出与时长 —— 形成 span 树并记录时长

`enter_span` 进入一个 span，其父 span 取自当前激活上下文，从而形成 span 树
（**R7.3**）；`exit_span` 结束 span 并记录时长（**R7.5**）。span 激活期间产生的
事件被自动标注该 span 的 `span` 标识与当前 `trace` 上下文（**R7.4**）。下例先用
`begin_trace` 开启 trace，进入外层 `request` span，再嵌套进入内层 `db-query` span。

```mbt check
///|
test "README · enter_span/exit_span 形成 span 树并记录时长" {
  reset_logger()
  let trace = begin_trace()
  let outer = enter_span("request")
  // 激活 span 内的事件被标注 span 与 trace 上下文（R7.4）
  log(Level::Info, { "msg": Value::VStr("handling") })
  let inner = enter_span("db-query")
  // 内层 span 关联外层 span，形成 span 树（R7.3）
  assert_true(outer.parent is None) // 外层为根 span
  assert_true(inner.parent == Some(outer.id)) // 内层挂接到外层之下
  exit_span(inner)
  exit_span(outer)
  // 事件携带激活 span 与 trace 标识
  let e = captured_events()[0]
  assert_true(e.fields.get("span") == Some(Value::VInt(outer.id.value)))
  assert_true(e.fields.get("trace") == Some(Value::VInt(trace.value)))
  // 退出后两个 span 均记录正向时长（end - start > 0，R7.5）
  let finished = finished_spans()
  assert_eq(finished.length(), 2)
  for i = 0; i < finished.length(); i = i + 1 {
    match span_duration(finished[i]) {
      Some(d) => assert_true(d > 0L)
      None => fail("expected a recorded duration")
    }
  }
}
```

---

## 示例 4 · 结构化输出往返 —— format_json → parse_json_log

`format_json` 把一条事件序列化为 JSON 结构化文本（字段按键名稳定排序，三后端
逐字节一致）；`parse_json_log` 是其逆操作，解析回等价事件。二者构成「序列化再
解析」往返闭环（**R7.7**）。下例对一条含多种取值类型字段的事件做往返，并校验
非法 JSON 返回 `None`、不产生部分构造对象。

```mbt check
///|
test "README · format_json 与 parse_json_log 往返" {
  reset_logger()
  let event = Event::new(7L, Level::Warn, {
    "msg": Value::VStr("disk almost full"),
    "used": Value::VInt(95L),
    "healthy": Value::VBool(false),
    "ratio": Value::VFloat(0.95),
  })
  let json = format_json(event)
  // 结构化文本含级别标签、时间戳与字段
  assert_true(json.contains("\"level\":\"WARN\""))
  assert_true(json.contains("\"ts\":7"))
  // 往返：解析结果与原事件逐字段等价
  match parse_json_log(json) {
    Some(parsed) => {
      assert_eq(parsed.ts, 7L)
      assert_true(parsed.level == Level::Warn)
      assert_true(
        parsed.fields.get("msg") == Some(Value::VStr("disk almost full")),
      )
      assert_true(parsed.fields.get("used") == Some(Value::VInt(95L)))
      assert_true(parsed.fields.get("healthy") == Some(Value::VBool(false)))
      assert_true(parsed.fields.get("ratio") == Some(Value::VFloat(0.95)))
    }
    None => fail("expected round-trip to succeed")
  }
  // 非法 JSON 返回 None，不产生部分构造对象
  assert_true(parse_json_log("{ not json") is None)
}
```

---

## 示例 5 · 嵌套结构化取值与嵌套 JSON 往返（R1）

旗舰深化在标量取值之上新增嵌套对象 `VMap` 与数组 `VList`，可任意层级嵌套；
`format_json` 将其渲染为 JSON 对象（成员稳定排序）/数组，`parse_json_log`
逆还原，二者对任意嵌套深度往返（**R1.2/1.3/1.4/1.6**）。

```mbt check
///|
test "README · 嵌套取值与嵌套 JSON 往返" {
  reset_logger()
  let event = Event::new(1L, Level::Info, {
    "user": Value::VMap({
      "id": Value::VInt(42L),
      "roles": Value::VList([Value::VStr("admin"), Value::VStr("ops")]),
    }),
  })
  let json = format_json(event)
  // VList 保持原序、VMap 成员稳定排序
  assert_true(json.contains("\"roles\":[\"admin\",\"ops\"]"))
  // 嵌套往返：解析回等价事件（Map 相等按内容判定，与字段顺序无关）
  assert_true(parse_json_log(json) == Some(event))
}
```

---

## 示例 6 · 多 formatter 与可插拔 sink（R2）

`Formatter{Json|Logfmt|Pretty}` 提供三种渲染；`Sink`（内存缓冲 + 格式器 +
路由谓词）与 `dispatch` 把同一事件落地到多个 sink 的多种格式（**R2.1/2.4/2.5**）。

```mbt check
///|
test "README · 多 formatter 与可插拔 sink" {
  reset_logger()
  let e = Event::new(3L, Level::Warn, {
    "svc": Value::VStr("api"),
    "code": Value::VInt(503L),
  })
  assert_true(format_event(Formatter::Json, e).contains("\"level\":\"WARN\""))
  assert_true(format_event(Formatter::Logfmt, e).contains("level=WARN"))
  assert_true(format_event(Formatter::Pretty, e).contains("[WARN]"))
  // 可插拔 sink：同一事件落地到 JSON 与 logfmt 两个内存 sink
  let json_sink = Sink::new("json", Formatter::Json)
  let logfmt_sink = Sink::new("logfmt", Formatter::Logfmt)
  dispatch([json_sink, logfmt_sink], e)
  assert_eq(json_sink.buffer.length(), 1)
  assert_eq(logfmt_sink.buffer.length(), 1)
}
```

---

## 示例 7 · logfmt 往返（R2.3/2.6/2.7）

logfmt 以 `key=value` 空格分隔；含空格/特殊字符的取值施加引号与转义，标量域
内 `parse_logfmt(format_logfmt(e)) ≡ e`。

```mbt check
///|
test "README · logfmt 往返" {
  let e = Event::new(5L, Level::Info, {
    "msg": Value::VStr("hello world"),
    "n": Value::VInt(7L),
  })
  let line = format_logfmt(e)
  assert_true(line.contains("msg=\"hello world\"")) // 含空格 → 引号包裹
  assert_true(parse_logfmt(line) == Some(e))
}
```

---

## 示例 8 · 确定性采样与限流（R3）

`sample_trace` 同一 trace 判定恒定（trace 内一致）；`retained_count` 给出系统
采样保留条数上界；`RateLimiter` 在逻辑时间窗内限流（**R3.2/3.3/3.5**）。

```mbt check
///|
test "README · 确定性采样与限流" {
  // trace 内一致：同一 trace 多次判定恒定；边界 rate=0 全弃、rate=1 全采
  let trace : TraceId = { value: 12345L }
  let decision = sample_trace(0.5, trace, 42UL)
  assert_eq(sample_trace(0.5, trace, 42UL), decision)
  assert_false(sample_trace(0.0, trace, 42UL))
  assert_true(sample_trace(1.0, trace, 42UL))
  // 系统采样保留条数 = floor(rate*n)
  assert_eq(retained_count(0.25, 1000), 250)
  // 限流：window=10 limit=2，同窗放行 2 条后丢弃，窗口到期重置
  let limiter = RateLimiter::new(10L, 2)
  assert_true(limiter.allow("k", 0L))
  assert_true(limiter.allow("k", 1L))
  assert_false(limiter.allow("k", 2L))
  assert_true(limiter.allow("k", 10L)) // 新窗口
}
```

---

## 示例 9 · 过滤与路由（R4）

`EnvFilter` 解析 `target=level,…,level` 指令（对标 `tracing-subscriber`），按
target 阈值过滤；`route` 将事件分发到条件匹配的 sink（**R4.1/4.3/4.5**）。

```mbt check
///|
test "README · 过滤与路由" {
  let f = match parse_env_filter("db=debug,http=warn,info") {
    Ok(filter) => filter
    Err(_) => {
      fail("合法指令应解析成功")
      return
    }
  }
  // db 阈值 debug：Debug 保留；http 阈值 warn：Info 丢弃
  assert_true(
    f.allows(Event::new(0L, Level::Debug, { "target": Value::VStr("db") })),
  )
  assert_false(
    f.allows(Event::new(0L, Level::Info, { "target": Value::VStr("http") })),
  )
  // 未登记 target 走全局兜底 info：Debug 丢弃
  assert_false(
    f.allows(Event::new(0L, Level::Debug, { "target": Value::VStr("x") })),
  )
  // 路由：仅 Error+ 交付给告警 sink
  let errors = Sink::new("errors", Formatter::Json, route=fn(e) {
    e.level.rank() >= Level::Error.rank()
  })
  assert_eq(route([errors], Event::new(0L, Level::Error, {})).length(), 1)
  assert_eq(route([errors], Event::new(0L, Level::Info, {})).length(), 0)
}
```

---

## 示例 10 · OpenTelemetry 风格 span 语义（R5）

`SpanData` 在既有 `Span` 之上旁路叠加属性 / 事件 / 状态 / kind，不改既有 span
树与时长语义（**R5.1–5.5**）。

```mbt check
///|
test "README · OpenTelemetry span 语义" {
  reset_logger()
  let _t = begin_trace()
  let span = enter_span("http.request")
  let sd = SpanData::new(span)
  sd.set_kind(SpanKind::Server)
  sd.set_attribute("http.method", Value::VStr("GET"))
  sd.add_event("cache.miss", span.start, { "key": Value::VStr("u:1") })
  sd.set_status(SpanStatus::Ok)
  exit_span(span)
  assert_true(sd.kind == SpanKind::Server)
  assert_true(sd.status == SpanStatus::Ok)
  assert_true(sd.attributes.get("http.method") == Some(Value::VStr("GET")))
  assert_eq(sd.events.length(), 1)
}
```

---

## 示例 11 · W3C Trace Context 注入与提取（R6）

`inject_traceparent` 产出 `00-<32hex>-<16hex>-<2hex>`；`extract_traceparent`
严格校验后提取三分量，非法返回 `None`；64↔128 位映射详见下文实现边界声明。

```mbt check
///|
test "README · W3C traceparent 注入与提取" {
  let ctx : TraceContext = {
    trace: { value: 0x0123456789abcdefL },
    span: Some({ value: 7L }),
  }
  let tp = inject_traceparent(ctx)
  assert_eq(tp.length(), 55) // 2+1+32+1+16+1+2
  assert_true(tp.contains("0123456789abcdef")) // trace 低 64 位编码
  match extract_traceparent(tp) {
    Some(w) => {
      assert_true(w.is_sampled()) // flags 01 最低位为 1
      assert_eq(w.to_trace_context().trace.value, ctx.trace.value) // 无损往返
    }
    None => fail("合法 traceparent 应提取成功")
  }
  // 非法输入返回 None，不产部分上下文
  assert_true(extract_traceparent("not-a-traceparent") is None)
}
```

---

## 示例 12 · 脱敏 / PII 过滤（R7）

`redact` 将敏感字段（名命中或谓词为真）取值**整体**替换为掩码（嵌套也整体
替换），字段键集合不变（**R7.1/7.3/7.4**）。

```mbt check
///|
test "README · 脱敏 / PII 过滤" {
  let e = Event::new(1L, Level::Info, {
    "user": Value::VStr("alice"),
    "password": Value::VStr("hunter2"),
    "card": Value::VMap({ "no": Value::VStr("4111111111111111") }),
  })
  let policy = RedactionPolicy::by_names(["password", "card"])
  let red = redact(policy, e)
  // 键集合不变；敏感字段整体掩码；非敏感字段不变
  assert_eq(red.fields.length(), e.fields.length())
  assert_true(red.fields.get("password") == Some(redaction_mask))
  assert_true(red.fields.get("card") == Some(redaction_mask)) // 嵌套整体替换
  assert_true(red.fields.get("user") == Some(Value::VStr("alice")))
  // 输出不残留任何敏感原值片段
  assert_false(format_json(red).contains("4111111111111111"))
}
```

---

## 示例 13 · 指标派生（R8）

`count_by_level` 按级别计数（定长数组，计数守恒）；`histogram` 按升序边界把
数值字段分桶，缺字段 / 非数值事件被跳过（**R8.1/8.2/8.3**）。

```mbt check
///|
test "README · 指标派生" {
  let events = [
    Event::new(0L, Level::Info, { "lat": Value::VInt(5L) }),
    Event::new(1L, Level::Warn, { "lat": Value::VInt(15L) }),
    Event::new(2L, Level::Error, { "lat": Value::VInt(150L) }),
    Event::new(3L, Level::Info, { "msg": Value::VStr("no-lat") }), // 缺 lat → 跳过
  ]
  let counts = count_by_level(events)
  assert_eq(level_count(counts, Level::Info), 2)
  assert_eq(level_count(counts, Level::Error), 1)
  // 边界 [10,100] ⇒ 3 桶；缺字段事件不计入
  let h = histogram(events, "lat", [10.0, 100.0])
  assert_eq(h.buckets.length(), 3)
  assert_eq(h.buckets[0], 1) // 5 < 10
  assert_eq(h.buckets[1], 1) // 15 ∈ [10,100)
  assert_eq(h.buckets[2], 1) // 150 >= 100
}
```

---

## 示例 14 · 端到端 demo 与跨进程传播（R11）

`run_demo` 串联开 trace → 嵌套 span + OTel 属性 → 采样 + 脱敏 → JSON/logfmt
双格式 → traceparent 注入；`run_downstream` 在模拟下游进程提取并续记，与父进程
归属同一 trace-id（**R11.1/11.2/11.3**）。

```mbt check
///|
test "README · 端到端 demo 与跨进程传播" {
  let outcome = run_demo()
  // 嵌套 span（root + db）、3 条事件双格式输出
  assert_eq(outcome.span_count, 2)
  assert_eq(outcome.json_lines.length(), 3)
  assert_eq(outcome.logfmt_lines.length(), 3)
  // 跨进程：下游提取 traceparent 后与父进程同 trace-id
  match run_downstream(outcome.traceparent) {
    Some(tid) => assert_eq(tid.value, outcome.trace.value)
    None => fail("下游应能从 traceparent 提取上下文")
  }
}
```

---

## paper-to-code 可追溯与开源对标（R10）

每个关键追踪 / 日志机制可追溯到规范或论文，并与主流方案对比：

| 算法 / 规范 | 来源 | 本库落点 |
|---|---|---|
| span 树 + 上下文传播 | Google Dapper（Sigelman 等, 2010） | `enter_span`/`exit_span`/`with_context` + `otel_span.mbt` 叠加（**R10.1**） |
| span 属性 / 事件 / 状态 / kind | OpenTelemetry 规范（Tracing / SpanKind / Status） | `otel_span.mbt`：`SpanData`/`SpanEvent`/`SpanStatus`/`SpanKind`（**R10.2**） |
| traceparent 格式与字段语义 | W3C Trace Context 规范 | `trace_context.mbt`：`inject_traceparent`/`extract_traceparent`（**R10.3**） |
| logfmt 文本表示 | 结构化日志 / logfmt 约定（Heroku / go-kit） | `logfmt.mbt`：`format_logfmt`/`parse_logfmt`（**R10.4**） |
| EnvFilter 分 target 级别控制 | Rust `tracing-subscriber` EnvFilter | `filter.mbt`：`parse_env_filter`/`threshold_for` |
| 系统采样 + trace 内一致采样 | systematic sampling + Dapper 一致采样 | `sampling.mbt`：`sample_stream`/`sample_trace` |

**与主流方案的模型与权衡对比（R10.5）：**

| 维度 | 本库 | Rust `tracing` | `slog` | Uber `zap` | OpenTelemetry SDK |
|---|---|---|---|---|---|
| 结构化字段 | `Value`（标量 + 嵌套 VMap/VList） | typed fields | KV serializer | 强类型 `Field` | Attributes |
| span / scope | 既有 span 树 + OTel 语义叠加 | `Span`/`Subscriber` | 无原生 span | 无原生 span | `Span`/`Tracer`/`Context` |
| 采样 | 确定性系统采样 + trace 内一致 | subscriber 自定义 | Drain 自定义 | sampler core | `Sampler`（TraceIdRatioBased 等） |
| 上下文传播 | 显式捕获 + `with_context`；W3C traceparent | task-local + `Span` | logger 传递 | logger 传递 | `Context` + W3C Propagator |
| 导出 | 内存 sink（模型层） | 多 layer | 多 Drain | 多 Core | 多 Exporter（OTLP 等） |
| 格式 | JSON / logfmt / pretty + 解析往返 | fmt / json layer | json / logfmt | json / console | OTLP / 自定义 |

**核心取舍**：与 OpenTelemetry SDK 同侧——以**可形式化验证的纯模型层**（确定性
采样 / 往返编解码 / 不变量可证）换取三后端一致性与可审计性，而非 `tracing`/`zap`
面向真实 IO 的高性能导出管线；同时吸收 `tracing` 的 EnvFilter 分模块控制与
`slog`/`zap` 的多格式器表达力。

## 实现边界声明（R10.6，显式而非隐式留白）

- **不接真实网络 / 文件导出**：sink 以内存缓冲（`Sink.buffer`）建模，不做真实 IO；
  多 sink / 路由 / 多格式在内存模型内完整可测。
- **不耦合 `moonbitlang/async`**：跨任务 trace 传播以「显式上下文捕获 +
  `with_context`」模型替代异步任务局部存储，行为不变量（子任务保留父 trace 标识）
  与真实异步运行时一致。
- **不接真实墙钟**：时间戳以单调逻辑时钟建模，保证三后端对同一调用序列产逐位
  一致的时间戳。
- **traceparent 128↔64 映射**：内部 64 位标识编码进 traceparent 的 128 位 trace-id
  低位（高位补 0），inject/extract 对内部标识无损往返，但不承载完整 128 位外部
  trace-id 语义。

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/logging/README.mbt.md

# 三后端一致性（R11.1）：同一文档套件在三后端均须通过
moon test src/logging/README.mbt.md --target wasm-gc
moon test src/logging/README.mbt.md --target js
moon test src/logging/README.mbt.md --target native
```

预期看到：

```
Total tests: 14, passed: 14, failed: 0.
```

（示例 1~14 的 14 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`assert_*` 断言不符，`moon test` 会立即报错——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
