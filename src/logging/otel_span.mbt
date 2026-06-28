// otel_span.mbt —— OpenTelemetry 风格 span 语义（任务 8.1）。
//
// 设计依据：design.md §4.6「OpenTelemetry 风格 span 语义」（Requirement 5.*）。
// 在既有 `Span`（id / parent / start / end）之上**旁路叠加**属性 / 事件 / 状态 /
// kind，不改既有 `Span` 字段或 `enter_span` / `exit_span` / `span_duration` 行为
// （Requirement 5.5）。语义追溯 OpenTelemetry 规范（见 README，Requirement 10.2）：
//
//   * `SpanStatus{Unset|Ok|Error}` —— span 结果状态，默认 `Unset`（Requirement 5.3）；
//   * `SpanKind{Internal|Server|Client|Producer|Consumer}` —— span 类别，默认
//     `Internal`（Requirement 5.4）；
//   * `SpanEvent{name, ts, fields}` —— span 生命周期内的标注点（Requirement 5.2）；
//   * `SpanData` —— 包裹既有 `Span` 并持有 attributes / events / status / kind。
//
// 注意 `SpanStatus::Ok` / `SpanStatus::Error` 与 `Result` 构造子及 `Level::Error`
// 同名，使用时一律以 `SpanStatus::` 限定避免歧义。

///|
/// span 结果状态（Requirement 5.3），默认 `Unset`。对应 OpenTelemetry span status。
pub(all) enum SpanStatus {
  Unset
  Ok
  Error
} derive(Eq, Show)

///|
/// span 类别（Requirement 5.4），默认 `Internal`。对应 OpenTelemetry span kind。
pub(all) enum SpanKind {
  Internal
  Server
  Client
  Producer
  Consumer
} derive(Eq, Show)

///|
/// span 事件（Requirement 5.2）：名称 + 逻辑时间戳 + 结构化字段。
///
/// 在 span 生命周期内某时刻记录的标注点，归属于其所在 span。
pub(all) struct SpanEvent {
  name : String
  ts : Int64
  fields : Map[String, Value]
} derive(Eq, Show)

///|
/// OTel 语义包裹：在既有 `Span` 之上旁路叠加属性 / 事件 / 状态 / kind
/// （Requirement 5.1–5.5）。持有既有 `Span` 而不改其字段或时长语义。
pub(all) struct SpanData {
  span : Span
  mut attributes : Map[String, Value]
  mut events : Array[SpanEvent]
  mut status : SpanStatus
  mut kind : SpanKind
} derive(Eq, Show)

///|
/// 由既有 `Span` 构造 OTel 包裹：默认 `status=Unset`、`kind=Internal`，空属性
/// 与空事件（Requirement 5.3 / 5.4）。
pub fn SpanData::new(span : Span) -> SpanData {
  {
    span,
    attributes: Map([]),
    events: [],
    status: SpanStatus::Unset,
    kind: SpanKind::Internal,
  }
}

///|
/// 为 span 设置一个键值属性（Requirement 5.1）。同名键覆盖，保留在结束记录中。
pub fn SpanData::set_attribute(
  self : SpanData,
  key : String,
  value : Value,
) -> Unit {
  self.attributes[key] = value
}

///|
/// 在 span 上记录一个 span 事件（Requirement 5.2）：保留名称 / 时间戳 / 字段，
/// 并归属于该 span（按记录顺序追加）。
pub fn SpanData::add_event(
  self : SpanData,
  name : String,
  ts : Int64,
  fields : Map[String, Value],
) -> Unit {
  self.events.push({ name, ts, fields })
}

///|
/// 为 span 设置状态（Requirement 5.3）。
pub fn SpanData::set_status(self : SpanData, status : SpanStatus) -> Unit {
  self.status = status
}

///|
/// 为 span 设置 kind（Requirement 5.4）。
pub fn SpanData::set_kind(self : SpanData, kind : SpanKind) -> Unit {
  self.kind = kind
}
