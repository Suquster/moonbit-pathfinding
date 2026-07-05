// otlp_export.mbt —— T7.1 真·OTLP 导出器（纲领方向七，突破「不做真实导出」非目标）。
//
// 按 OTLP（OpenTelemetry Protocol）线缆格式把本包的 `SpanData` 序列化为
// `opentelemetry.proto.trace.v1.TracesData` 的 **protobuf 字节**与 **OTLP/JSON**，
// 复用方向九 @serialization 的模式驱动编码（parse_proto_full + encode_typed /
// encode_json），产出可被真实 OTel collector 接收的载荷。
//
// 语义追溯（opentelemetry-proto v1 trace.proto，逐字段对齐）：
//   * `Span`：trace_id(1, 16B) / span_id(2, 8B) / parent_span_id(4, 8B) /
//     name(5) / kind(6) / start·end_time_unix_nano(7/8, fixed64) /
//     attributes(9) / events(11) / status(15)；
//   * `SpanKind`：UNSPECIFIED=0, INTERNAL=1, SERVER=2, CLIENT=3,
//     PRODUCER=4, CONSUMER=5（本包 `SpanKind` 依序 +1 映射）；
//   * `Status.code`：UNSET=0, OK=1, ERROR=2；
//   * `AnyValue` oneof：string(1) / bool(2) / int(3) / double(4) /
//     array(5) / kvlist(6)——与本包 `Value` 六构造一一对应；
//   * trace_id / span_id 字节序：与 trace_context.mbt 的 W3C traceparent
//     十六进制表示一致（高位补零的大端 `Int64`），保证同一 span 在
//     traceparent 头与 OTLP 载荷中的标识可互相印证。
//
// 时间语义：本包 span 时间戳为**逻辑时钟**（spec 不接墙钟），导出时按
// 纳秒直写 fixed64；接入真实时钟后无需改动线缆层。

///|
/// OTLP trace v1 线缆模式（opentelemetry-proto 子集，字段号与官方 .proto 一致）。
/// 单例惰性解析后缓存，编码路径零重复解析。
pub fn otlp_trace_proto() -> String {
  (
    #|syntax = "proto3";
    #|
    #|message TracesData {
    #|  repeated ResourceSpans resource_spans = 1;
    #|}
    #|
    #|message ResourceSpans {
    #|  Resource resource = 1;
    #|  repeated ScopeSpans scope_spans = 2;
    #|}
    #|
    #|message Resource {
    #|  repeated KeyValue attributes = 1;
    #|}
    #|
    #|message ScopeSpans {
    #|  InstrumentationScope scope = 1;
    #|  repeated Span spans = 2;
    #|}
    #|
    #|message InstrumentationScope {
    #|  string name = 1;
    #|  string version = 2;
    #|}
    #|
    #|message KeyValue {
    #|  string key = 1;
    #|  AnyValue value = 2;
    #|}
    #|
    #|message AnyValue {
    #|  oneof value {
    #|    string string_value = 1;
    #|    bool bool_value = 2;
    #|    int64 int_value = 3;
    #|    double double_value = 4;
    #|    ArrayValue array_value = 5;
    #|    KeyValueList kvlist_value = 6;
    #|  }
    #|}
    #|
    #|message ArrayValue {
    #|  repeated AnyValue values = 1;
    #|}
    #|
    #|message KeyValueList {
    #|  repeated KeyValue values = 1;
    #|}
    #|
    #|message Span {
    #|  bytes trace_id = 1;
    #|  bytes span_id = 2;
    #|  bytes parent_span_id = 4;
    #|  string name = 5;
    #|  int32 kind = 6;
    #|  fixed64 start_time_unix_nano = 7;
    #|  fixed64 end_time_unix_nano = 8;
    #|  repeated KeyValue attributes = 9;
    #|  repeated SpanEvent events = 11;
    #|  SpanStatus status = 15;
    #|}
    #|
    #|message SpanEvent {
    #|  fixed64 time_unix_nano = 1;
    #|  string name = 2;
    #|  repeated KeyValue attributes = 3;
    #|}
    #|
    #|message SpanStatus {
    #|  string message = 2;
    #|  int32 code = 3;
    #|}
  )
}

///|
/// 解析并缓存 OTLP trace 模式（进程内单例）。
let otlp_schema_cache : Ref[@serialization.ProtoSchema?] = Ref(None)

///|
/// 取（或首次解析）OTLP trace 模式。模式文本为编译期常量，解析必成功；
/// 万一失败（不可能路径）则 abort 暴露而非静默降级。
pub fn otlp_schema() -> @serialization.ProtoSchema {
  match otlp_schema_cache.val {
    Some(s) => s
    None =>
      match @serialization.parse_proto_full(otlp_trace_proto()) {
        Ok(s) => {
          otlp_schema_cache.val = Some(s)
          s
        }
        Err(_) =>
          abort(
            "otlp_trace_proto 模式解析失败（编译期常量，不可能路径）",
          )
      }
  }
}

///|
/// `Int64` → 大端 8 字节（与 traceparent 的 16 位 hex 同一编码位序）。
fn otlp_id8(v : Int64) -> Bytes {
  let b = Array::make(8, b'\x00')
  for i in 0..<8 {
    b[7 - i] = ((v >> (i * 8)) & 0xFFL).to_int().to_byte()
  }
  Bytes::from_array(b)
}

///|
/// `TraceId` → 16 字节 trace_id（高 8 字节补零，低 8 字节大端——与
/// trace_context.mbt 的 `0000000000000000` + hex(低 64 位) 逐字节一致）。
fn otlp_id16(v : Int64) -> Bytes {
  let b = Array::make(16, b'\x00')
  for i in 0..<8 {
    b[15 - i] = ((v >> (i * 8)) & 0xFFL).to_int().to_byte()
  }
  Bytes::from_array(b)
}

///|
/// 本包 `Value` → OTLP `AnyValue`（oneof 六构造一一映射，含递归嵌套）。
fn otlp_any_value(v : Value) -> @serialization.TypedMessage {
  let m = @serialization.TypedMessage::new()
  match v {
    VStr(s) => m.set(1, TStringV(s))
    VBool(b) => m.set(2, TBoolV(b))
    VInt(n) => m.set(3, TInt(n))
    VFloat(d) => m.set(4, TDoubleV(d))
    VList(items) => {
      let arr = @serialization.TypedMessage::new().set(
        1,
        TList(items.map(fn(x) { @serialization.TMsg(otlp_any_value(x)) })),
      )
      m.set(5, TMsg(arr))
    }
    VMap(fields) => {
      let kvl = @serialization.TypedMessage::new().set(
        1,
        otlp_key_values(fields),
      )
      m.set(6, TMsg(kvl))
    }
  }
}

///|
/// 结构化字段表 → `repeated KeyValue`（保持插入序，确定性输出）。
fn otlp_key_values(fields : Map[String, Value]) -> @serialization.TypedValue {
  let out : Array[@serialization.TypedValue] = []
  for k, v in fields {
    out.push(
      TMsg(
        @serialization.TypedMessage::new()
        .set(1, TStringV(k))
        .set(2, TMsg(otlp_any_value(v))),
      ),
    )
  }
  TList(out)
}

///|
/// 本包 `SpanKind` → OTLP kind 编号（INTERNAL=1 … CONSUMER=5）。
fn otlp_kind_code(kind : SpanKind) -> Int {
  match kind {
    Internal => 1
    Server => 2
    Client => 3
    Producer => 4
    Consumer => 5
  }
}

///|
/// 本包 `SpanStatus` → OTLP status code（UNSET=0 / OK=1 / ERROR=2）。
fn otlp_status_code(status : SpanStatus) -> Int {
  match status {
    SpanStatus::Unset => 0
    SpanStatus::Ok => 1
    SpanStatus::Error => 2
  }
}

///|
/// 单个 `SpanData` → OTLP `Span` 消息（逐字段对齐官方 trace.proto）。
pub fn otlp_span_message(
  trace : TraceId,
  name : String,
  sd : SpanData,
) -> @serialization.TypedMessage {
  let mut m = @serialization.TypedMessage::new()
    .set(1, TBytesV(otlp_id16(trace.value)))
    .set(2, TBytesV(otlp_id8(sd.span.id.value)))
  match sd.span.parent {
    Some(p) => m = m.set(4, TBytesV(otlp_id8(p.value)))
    None => ()
  }
  m = m
    .set(5, TStringV(name))
    .set(6, TInt(otlp_kind_code(sd.kind).to_int64()))
    .set(7, TUInt(sd.span.start.reinterpret_as_uint64()))
  match sd.span.end {
    Some(e) => m = m.set(8, TUInt(e.reinterpret_as_uint64()))
    None => ()
  }
  if sd.attributes.length() > 0 {
    m = m.set(9, otlp_key_values(sd.attributes))
  }
  if sd.events.length() > 0 {
    let evs : Array[@serialization.TypedValue] = []
    for ev in sd.events {
      let mut em = @serialization.TypedMessage::new()
        .set(1, TUInt(ev.ts.reinterpret_as_uint64()))
        .set(2, TStringV(ev.name))
      if ev.fields.length() > 0 {
        em = em.set(3, otlp_key_values(ev.fields))
      }
      evs.push(TMsg(em))
    }
    m = m.set(11, TList(evs))
  }
  m.set(
    15,
    TMsg(
      @serialization.TypedMessage::new().set(
        3,
        TInt(otlp_status_code(sd.status).to_int64()),
      ),
    ),
  )
}

///|
/// 组装一批命名 span 为 `TracesData`（单 Resource + 单 Scope）。
/// `service_name` 写入 Resource 的 `service.name` 属性（OTel 语义约定）。
pub fn otlp_traces_data(
  service_name : String,
  trace : TraceId,
  spans : Array[(String, SpanData)],
) -> @serialization.TypedMessage {
  let resource = @serialization.TypedMessage::new().set(
    1,
    TList([
      TMsg(
        @serialization.TypedMessage::new()
        .set(1, TStringV("service.name"))
        .set(
          2,
          TMsg(
            @serialization.TypedMessage::new().set(1, TStringV(service_name)),
          ),
        ),
      ),
    ]),
  )
  let scope = @serialization.TypedMessage::new()
    .set(1, TStringV(logging_name))
    .set(2, TStringV(logging_version))
  let span_msgs : Array[@serialization.TypedValue] = []
  for pair in spans {
    let (name, sd) = pair
    span_msgs.push(TMsg(otlp_span_message(trace, name, sd)))
  }
  let scope_spans = @serialization.TypedMessage::new()
    .set(1, TMsg(scope))
    .set(2, TList(span_msgs))
  let resource_spans = @serialization.TypedMessage::new()
    .set(1, TMsg(resource))
    .set(2, TList([TMsg(scope_spans)]))
  @serialization.TypedMessage::new().set(1, TList([TMsg(resource_spans)]))
}

///|
/// T7.1 主入口：批量 span → OTLP **protobuf 字节**
/// （`opentelemetry.proto.trace.v1.TracesData`，可直接 POST 到真实 collector
/// 的 `/v1/traces`，Content-Type: application/x-protobuf）。
pub fn otlp_export_traces(
  service_name : String,
  trace : TraceId,
  spans : Array[(String, SpanData)],
) -> Bytes {
  let msg = otlp_traces_data(service_name, trace, spans)
  match @serialization.encode_typed(otlp_schema(), "TracesData", msg) {
    Ok(b) => b
    Err(_) =>
      abort("OTLP 编码失败（模式与构造同源，不可能路径）")
  }
}

///|
/// T7.1 补充入口：批量 span → **OTLP/JSON** 文本（collector 的
/// application/json 变体；字段名与 proto 定义一致的 JSON 映射）。
pub fn otlp_export_traces_json(
  service_name : String,
  trace : TraceId,
  spans : Array[(String, SpanData)],
) -> String {
  let msg = otlp_traces_data(service_name, trace, spans)
  match @serialization.encode_json(otlp_schema(), "TracesData", msg) {
    Ok(s) => s
    Err(_) =>
      abort(
        "OTLP/JSON 编码失败（模式与构造同源，不可能路径）",
      )
  }
}
