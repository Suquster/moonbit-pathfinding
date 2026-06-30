// otlp_export.mbt —— 方向七 T7.1：真·OTLP（OpenTelemetry Protocol）追踪导出器。
//
// 设计依据：docs/PRODUCTION_FRONTIER_ROADMAP.md「方向七 Logging」T7.1
// 「真·OTLP 导出器」——按 OTLP/protobuf 线缆格式序列化 span，**复用方向九
// @serialization 的 protobuf wire 编码原语**（`Message` / `FieldEntry` /
// `FieldValue` / `encode` / `double_to_bits`），产出可被真实 OpenTelemetry
// collector 接收的字节。字段编号逐一对齐 OpenTelemetry proto 定义
// （opentelemetry/proto/{common,trace,resource}/v1）：
//
//   * AnyValue   : string_value=1 / bool_value=2 / int_value=3 /
//                  double_value=4 / array_value=5 / kvlist_value=6
//   * KeyValue   : key=1 / value=2(AnyValue)
//   * Span       : trace_id=1 / span_id=2 / parent_span_id=4 / name=5 /
//                  kind=6 / start_time_unix_nano=7(fixed64) /
//                  end_time_unix_nano=8(fixed64) / attributes=9 /
//                  events=11 / status=15
//   * Span.Event : time_unix_nano=1(fixed64) / name=2 / attributes=3
//   * Status     : message=2 / code=3
//   * ScopeSpans : scope=1 / spans=2
//   * ResourceSpans : resource=1 / scope_spans=2
//   * ExportTraceServiceRequest : resource_spans=1
//
// 本模块为**加性**新增：既不改动既有 `Span` / `SpanData` / `Value` 类型，也不
// 触碰既有格式化器（format_json / format_logfmt）。属性按键名升序物化，保证三
// 后端（wasm-gc / js / native）导出字节逐字节一致、可被确定性回归比对。

///|
/// OTLP 导出的单条 span 输入：一次链路标识 `trace`、span 名称 `name` 与既有
/// OTel 语义包裹 `data`（属性 / 事件 / 状态 / kind）。
///
/// 既有 `Span` / `SpanData` 不携带名称字段，故由本输入结构在导出边界补充 span
/// 名称，避免侵入式修改既有数据模型（向后兼容契约）。
pub(all) struct OtlpSpanInput {
  trace : TraceId
  name : String
  data : SpanData
}

///|
/// 将 `String`（UTF-16 码元）按 UTF-8 编码为字节序列（proto string 的 wire 形态）。
///
/// 与 @serialization 内部的字符串编码约定一致：BMP 外字符按四字节序列编码，
/// 保证导出字节可被任意符合 UTF-8 的 collector 正确解读。
fn otlp_utf8(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for ch in s {
    let cp = ch.to_int()
    if cp < 0x80 {
      buf.push(cp.to_byte())
    } else if cp < 0x800 {
      buf.push((0xC0 | (cp >> 6)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      buf.push((0xE0 | (cp >> 12)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (cp >> 18)).to_byte())
      buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
/// 将 64 位无符号整数按**大端**展开为 8 字节（OTel trace/span id 的字节序）。
fn u64_be_bytes(v : UInt64) -> Array[Byte] {
  let a : Array[Byte] = []
  for i in 0..<8 {
    let shift = (7 - i) * 8
    a.push(((v >> shift) & 0xFFUL).to_int().to_byte())
  }
  a
}

///|
/// 将 `SpanId` 渲染为 OTLP 的 8 字节 span_id（大端）。
fn span_id_bytes(id : SpanId) -> Bytes {
  Bytes::from_array(u64_be_bytes(id.value.reinterpret_as_uint64()))
}

///|
/// 将 `TraceId` 渲染为 OTLP 的 16 字节 trace_id：高 8 字节置零，低 8 字节为
/// 大端 id。满足 OTel「trace_id 为 16 字节」约束。
fn trace_id_bytes(id : TraceId) -> Bytes {
  let a : Array[Byte] = []
  for _ in 0..<8 {
    a.push((0).to_byte())
  }
  for b in u64_be_bytes(id.value.reinterpret_as_uint64()) {
    a.push(b)
  }
  Bytes::from_array(a)
}

///|
/// OTLP SpanKind 线缆枚举值（opentelemetry.proto.trace.v1.Span.SpanKind）。
fn otlp_kind_code(k : SpanKind) -> UInt64 {
  match k {
    Internal => 1
    Server => 2
    Client => 3
    Producer => 4
    Consumer => 5
  }
}

///|
/// OTLP StatusCode 线缆枚举值（UNSET=0 / OK=1 / ERROR=2）。
fn otlp_status_code(s : SpanStatus) -> UInt64 {
  match s {
    Unset => 0
    Ok => 1
    Error => 2
  }
}

///|
/// 构造一个「长度分隔」字段：将子消息编码为字节后以该字段号承载。
fn f_msg(num : Int, m : @serialization.Message) -> @serialization.FieldEntry {
  @serialization.FieldEntry::new(
    num,
    @serialization.FieldValue::bytes(@serialization.encode(m)),
  )
}

///|
/// 构造一个 UTF-8 字符串字段（proto string，wire type LEN）。
fn f_string(num : Int, s : String) -> @serialization.FieldEntry {
  @serialization.FieldEntry::new(
    num,
    @serialization.FieldValue::bytes(otlp_utf8(s)),
  )
}

///|
/// 构造一个原始字节字段（proto bytes，wire type LEN）。
fn f_bytes(num : Int, b : Bytes) -> @serialization.FieldEntry {
  @serialization.FieldEntry::new(num, @serialization.FieldValue::bytes(b))
}

///|
/// 构造一个 varint 字段（proto int64/uint64/enum/bool，wire type VARINT）。
fn f_varint(num : Int, v : UInt64) -> @serialization.FieldEntry {
  @serialization.FieldEntry::new(num, @serialization.FieldValue::varint(v))
}

///|
/// 构造一个 fixed64 字段（proto fixed64/double，wire type I64）。
fn f_fixed64(num : Int, v : UInt64) -> @serialization.FieldEntry {
  @serialization.FieldEntry::new(num, @serialization.FieldValue::i64(v))
}

///|
/// 将结构化字段取值 `Value` 映射为 OTLP `AnyValue` 消息。
///
/// 标量映射到 string/bool/int/double 标量字段；`VList` 映射为 `ArrayValue`
/// （values=1 repeated AnyValue），`VMap` 映射为 `KeyValueList`
/// （values=1 repeated KeyValue），可任意层级嵌套。整数按 proto int64 的两补
/// 码 varint 编码，浮点按 IEEE-754 位型以 `@serialization.double_to_bits` 编码。
pub fn otlp_any_value(v : Value) -> @serialization.Message {
  match v {
    VStr(s) => @serialization.Message::from_fields([f_string(1, s)])
    VBool(b) =>
      @serialization.Message::from_fields([f_varint(2, if b { 1 } else { 0 })])
    VInt(i) =>
      @serialization.Message::from_fields([
        f_varint(3, i.reinterpret_as_uint64()),
      ])
    VFloat(d) =>
      @serialization.Message::from_fields([
        f_fixed64(4, @serialization.double_to_bits(d)),
      ])
    VList(xs) => {
      let inner : Array[@serialization.FieldEntry] = []
      for x in xs {
        inner.push(f_msg(1, otlp_any_value(x)))
      }
      let arr = @serialization.Message::from_fields(inner)
      @serialization.Message::from_fields([f_msg(5, arr)])
    }
    VMap(m) => {
      let kvl = @serialization.Message::from_fields(otlp_key_values(1, m))
      @serialization.Message::from_fields([f_msg(6, kvl)])
    }
  }
}

///|
/// 将一个键值对映射为 OTLP `KeyValue` 消息（key=1 / value=2(AnyValue)）。
///
/// 用于 span 属性、事件属性、资源属性与 `VMap` 嵌套取值的统一编码。
pub fn otlp_key_value(key : String, value : Value) -> @serialization.Message {
  @serialization.Message::from_fields([
    f_string(1, key),
    f_msg(2, otlp_any_value(value)),
  ])
}

///|
/// 将一个属性映射物化为给定字段号下的 repeated `KeyValue` 字段序列。
///
/// 键名按字典序升序排序后再编码，保证三后端导出字节逐字节一致（确定性、可对比）。
fn otlp_key_values(
  num : Int,
  attrs : Map[String, Value],
) -> Array[@serialization.FieldEntry] {
  let keys : Array[String] = []
  for k, _ in attrs {
    keys.push(k)
  }
  keys.sort()
  let out : Array[@serialization.FieldEntry] = []
  for k in keys {
    match attrs.get(k) {
      Some(v) => out.push(f_msg(num, otlp_key_value(k, v)))
      None => ()
    }
  }
  out
}

///|
/// 将一个 span 事件映射为 OTLP `Span.Event` 消息。
///
/// 字段：time_unix_nano=1(fixed64) / name=2(string) / attributes=3(repeated
/// KeyValue)。时间戳按 `Int64` 位型转 `UInt64` 写入 fixed64。
fn otlp_event(ev : SpanEvent) -> @serialization.Message {
  let fields : Array[@serialization.FieldEntry] = []
  fields.push(f_fixed64(1, ev.ts.reinterpret_as_uint64()))
  fields.push(f_string(2, ev.name))
  for e in otlp_key_values(3, ev.fields) {
    fields.push(e)
  }
  @serialization.Message::from_fields(fields)
}

///|
/// 将一条 span 输入映射为 OTLP `Span` 消息（含 trace/span id、父 span、名称、
/// kind、起止纳秒时间、属性、事件与状态）。
///
/// `parent_span_id`（字段 4）仅在存在父 span 时写入；`end_time_unix_nano`
/// （字段 8）仅在 span 已结束时写入；`status`（字段 15）仅在状态非 `Unset`
/// 时写入（遵循 proto3 缺省值省略约定）。属性按键名升序物化。
pub fn otlp_span(input : OtlpSpanInput) -> @serialization.Message {
  let sd = input.data
  let fields : Array[@serialization.FieldEntry] = []
  fields.push(f_bytes(1, trace_id_bytes(input.trace)))
  fields.push(f_bytes(2, span_id_bytes(sd.span.id)))
  match sd.span.parent {
    Some(p) => fields.push(f_bytes(4, span_id_bytes(p)))
    None => ()
  }
  fields.push(f_string(5, input.name))
  fields.push(f_varint(6, otlp_kind_code(sd.kind)))
  fields.push(f_fixed64(7, sd.span.start.reinterpret_as_uint64()))
  match sd.span.end {
    Some(e) => fields.push(f_fixed64(8, e.reinterpret_as_uint64()))
    None => ()
  }
  for e in otlp_key_values(9, sd.attributes) {
    fields.push(e)
  }
  for ev in sd.events {
    fields.push(f_msg(11, otlp_event(ev)))
  }
  match sd.status {
    Unset => ()
    other =>
      fields.push(
        f_msg(
          15,
          @serialization.Message::from_fields([
            f_varint(3, otlp_status_code(other)),
          ]),
        ),
      )
  }
  @serialization.Message::from_fields(fields)
}

///|
/// 构造 OTLP `InstrumentationScope` 消息（name=1 / version=2）。
fn otlp_scope(name : String, version : String) -> @serialization.Message {
  @serialization.Message::from_fields([f_string(1, name), f_string(2, version)])
}

///|
/// 构造 OTLP `Resource` 消息（attributes=1 repeated KeyValue，键名升序）。
fn otlp_resource(attrs : Map[String, Value]) -> @serialization.Message {
  @serialization.Message::from_fields(otlp_key_values(1, attrs))
}

///|
/// 将一批 span 与作用域、资源属性组装为单条 OTLP `ExportTraceServiceRequest`
/// 的 protobuf 字节，可直接作为 OTLP/HTTP 或 OTLP/gRPC 的请求体发送给真实
/// collector。
///
/// 结构：ExportTraceServiceRequest{ resource_spans=1: ResourceSpans{
/// resource=1, scope_spans=2: ScopeSpans{ scope=1, spans=2: [Span...] } } }。
/// 所有 span 归入单一资源与单一作用域；属性键升序物化以保证字节确定性。
pub fn otlp_export_trace(
  spans : Array[OtlpSpanInput],
  resource_attrs? : Map[String, Value] = Map([]),
  scope_name? : String = logging_name,
  scope_version? : String = logging_version,
) -> Bytes {
  let scope_span_fields : Array[@serialization.FieldEntry] = []
  scope_span_fields.push(f_msg(1, otlp_scope(scope_name, scope_version)))
  for s in spans {
    scope_span_fields.push(f_msg(2, otlp_span(s)))
  }
  let scope_spans = @serialization.Message::from_fields(scope_span_fields)
  let resource_spans = @serialization.Message::from_fields([
    f_msg(1, otlp_resource(resource_attrs)),
    f_msg(2, scope_spans),
  ])
  let request = @serialization.Message::from_fields([f_msg(1, resource_spans)])
  @serialization.encode(request)
}
