// formatter.mbt —— 多格式器与可插拔 sink（任务 4.3）。
//
// 设计依据：design.md §4.2「多 sink 与多 formatter」（Requirement 2.1 / 2.2 /
// 2.4 / 2.5）。本文件提供三种内置格式器与内存 sink 抽象：
//
//   * `Formatter{Json|Logfmt|Pretty}` —— 内置格式器种类；
//   * `format_event(fmt, e)` —— 把一条事件按指定格式器渲染为文本（确定性，
//     由事件内容唯一确定，三后端逐字节一致，Requirement 2.2 / Property 4）；
//   * `Sink` —— 可插拔内存 sink：名称 + 绑定格式器 + 路由谓词 + 内存缓冲；
//   * `dispatch(sinks, e)` —— 把事件交付给全部路由匹配的 sink（无匹配不交付，
//     Requirement 2.5）。
//
// 实现边界（Requirement 10.6）：sink 以内存缓冲（`buffer`）建模，不接真实
// 网络 / 文件 IO；多 sink / 多格式 / 路由在内存模型内完整可测。

///|
/// 内置格式器种类（Requirement 2.1）。
///   * `Json`   —— 复用 `format_json`（含嵌套取值），与 `parse_json_log` 往返；
///   * `Logfmt` —— 复用 `format_logfmt`，与 `parse_logfmt` 往返（标量域）；
///   * `Pretty` —— 面向终端阅读的对齐单行，不参与往返。
pub(all) enum Formatter {
  Json
  Logfmt
  Pretty
} derive(Eq, Show)

///|
/// 将一条事件按指定格式器渲染为文本（Requirement 2.1 / 2.2）。
///
/// 输出由事件内容唯一确定（纯函数、字段升序排序），三后端逐字节一致。
pub fn format_event(fmt : Formatter, e : Event) -> String {
  match fmt {
    Json => format_json(e)
    Logfmt => format_logfmt(e)
    Pretty => format_pretty(e)
  }
}

///|
/// 人类可读 pretty 格式器：`ts=<n> [LEVEL] k=v …`（字段按键名升序）。
///
/// 面向终端阅读：字符串取值不带引号，嵌套取值以紧凑 JSON 呈现。仅供阅读，
/// 不提供解析器（不参与往返）；其输出仍由事件内容唯一确定（Property 4）。
pub fn format_pretty(e : Event) -> String {
  let entries : Array[(String, Value)] = []
  e.fields.each(fn(k, v) { entries.push((k, v)) })
  sort_entries(entries)
  let mut out = "ts=" + e.ts.to_string() + " [" + e.level.label() + "]"
  for i = 0; i < entries.length(); i = i + 1 {
    let (k, v) = entries[i]
    out = out + " " + k + "=" + value_to_pretty(v)
  }
  out
}

///|
/// pretty 取值渲染：标量直白呈现，嵌套复用紧凑 JSON。
fn value_to_pretty(v : Value) -> String {
  match v {
    VStr(s) => s
    VInt(i) => i.to_string()
    VBool(b) => if b { "true" } else { "false" }
    VFloat(f) => f.to_string()
    _ => value_to_json(v)
  }
}

///|
/// 可插拔 sink：内存缓冲 + 绑定格式器 + 路由谓词（Requirement 2.4）。
///
/// `route` 为路由条件谓词（返回 true 表示该 sink 接收该事件）；`buffer`
/// 累积已交付事件的渲染文本（内存落地，不接真实 IO，Requirement 10.6）。
pub(all) struct Sink {
  name : String
  formatter : Formatter
  route : (Event) -> Bool
  mut buffer : Array[String]
}

///|
/// 构造一个 sink。`route` 为可选路由谓词，缺省时恒真（接收全部事件）。
pub fn Sink::new(
  name : String,
  formatter : Formatter,
  route? : (Event) -> Bool,
) -> Sink {
  let r = match route {
    Some(f) => f
    None => fn(_e) { true }
  }
  { name, formatter, route: r, buffer: [] }
}

///|
/// 将一条事件交付给全部已注册且路由条件匹配的 sink（Requirement 2.5）。
///
/// 对每个 `route(e)` 为真的 sink，将 `format_event(sink.formatter, e)` 推入其
/// 内存缓冲；无匹配 sink 则不交付（事件不落地任何缓冲）。同一事件可同时落地
/// 多个 sink 的多种格式。
pub fn dispatch(sinks : Array[Sink], e : Event) -> Unit {
  for s in sinks {
    if (s.route)(e) {
      s.buffer.push(format_event(s.formatter, e))
    }
  }
}
