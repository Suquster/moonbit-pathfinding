// sink_layer.mbt —— 日志真实 I/O 落地与运行时调级（任务 3.1，Requirement 2）。
//
// 设计依据：design.md §「Logging Sink 层设计（Requirement 2）」。本文件在既有
// `Sink` / `Formatter` / `format_event` 之上，以「只增不减（bypass）」策略新增
// 一套面向真实输出的 sink 抽象与运行时调级能力，**不修改任何既有签名**：
//
//   * `SinkTarget`  —— sink 的目标种类（Console / Callback / Buffered）；
//   * `SinkHandle`  —— 携带目标、格式器、缓冲与运行时级别的 sink 句柄；
//   * `console` / `callback` / `buffered` —— 三类 sink 的构造器；
//   * `set_level` —— 运行时调级（每个 sink 句柄独立）；
//   * `emit`      —— 按级别过滤后派发一条事件；
//   * `flush`     —— 强制下发缓冲（仅 Buffered 有效）。
//
// 行为严格对应 Requirement 2 的 AC1–AC6（见各函数注释）。

// ───────────────────────────── 常量 ──────────────────────────────────────

///|
/// sink 句柄缺省格式器：JSON（与既有 `format_json` 一致，可往返）。
///
/// 用于 `callback` / `buffered` 在调用方未显式指定 `formatter` 时的回退取值，
/// 避免在函数体内散落字面量（遵循「禁止 magic number / 硬编码」约束）。
let default_sink_formatter : Formatter = Json

///|
/// sink 句柄缺省生效级别：`Trace`（最低级，默认放行全部记录）。
///
/// 选取最低级别作为默认，保证「未显式调级时不丢弃任何记录」，调用方可随后以
/// `set_level` 收紧。集中命名以避免在多个构造器中重复字面量。
let default_sink_level : Level = Trace

// ───────────────────────────── 目标种类 ──────────────────────────────────

///|
/// sink 的目标种类（Requirement 2.1 / 2.2 / 2.3 / 2.4）。
///
///   * `TConsole`        —— 经 `format_event` 渲染后 `println` 写入标准输出；
///   * `TCallback(cb)`   —— 将事件交给调用方回调 `cb` 处理（恰好一次）；
///   * `TBuffered(...)`  —— 内部缓冲到阈值或显式 flush 时，按到达顺序批量下发
///                          给下游 `down`。
///
/// 关于递归结构的处理（重要）：`TBuffered` 直接以 `down~ : SinkHandle` 持有
/// 下游句柄，而 `SinkHandle` 又含 `target : SinkTarget`，构成「枚举 ↔ 结构体」
/// 的相互递归类型。MoonBit 的数据类型默认按引用承载、原生支持相互递归定义，
/// 故无需额外包装即可表达任意深度的 Buffered → … → Console/Callback 下发链，
/// 语义与设计文档完全一致。
pub enum SinkTarget {
  TConsole
  TCallback((Event) -> Unit)
  TBuffered(threshold~ : Int, down~ : SinkHandle)
}

///|
/// sink 句柄：目标 + 绑定格式器 + 缓冲 + 运行时级别（Requirement 2.5）。
///
///   * `target`    —— 目标种类（见 `SinkTarget`）；
///   * `formatter` —— Console 渲染所用格式器（Callback/Buffered 亦携带以备扩展）；
///   * `buffer`    —— 仅 `TBuffered` 使用的到达顺序缓冲；
///   * `level`     —— 本句柄当前生效级别，`set_level` 可在运行时调整（每句柄独立）。
pub struct SinkHandle {
  target : SinkTarget
  formatter : Formatter
  mut buffer : Array[Event]
  mut level : Level
}

// ───────────────────────────── 构造器 ────────────────────────────────────

///|
/// 构造 Console sink：通过 `format_event` 渲染后 `println` 写入标准输出。
///
/// `level` 可选，缺省为 `default_sink_level`（`Trace`，放行全部记录）。
/// 对应 Requirement 2.1。
pub fn SinkHandle::console(
  formatter : Formatter,
  level? : Level = default_sink_level,
) -> SinkHandle {
  { target: TConsole, formatter, buffer: [], level }
}

///|
/// 构造 Callback sink：级别通过时以事件为参数恰好调用一次 `cb`（Requirement 2.2）。
///
/// `formatter` 可选（缺省 `default_sink_formatter`，Callback 当前不依赖它渲染，
/// 仅为统一句柄结构与未来扩展保留）；`level` 可选，缺省放行全部记录。
pub fn SinkHandle::callback(
  cb : (Event) -> Unit,
  formatter? : Formatter = default_sink_formatter,
  level? : Level = default_sink_level,
) -> SinkHandle {
  { target: TCallback(cb), formatter, buffer: [], level }
}

///|
/// 构造 Buffered sink：缓冲到 `threshold` 或显式 `flush` 时按序批量下发 `down`。
///
/// `formatter` / `level` 可选，语义同上。对应 Requirement 2.3 / 2.4。
pub fn SinkHandle::buffered(
  threshold : Int,
  down : SinkHandle,
  formatter? : Formatter = default_sink_formatter,
  level? : Level = default_sink_level,
) -> SinkHandle {
  { target: TBuffered(threshold~, down~), formatter, buffer: [], level }
}

// ───────────────────────────── 运行时调级 ────────────────────────────────

///|
/// 运行时设置本句柄的生效级别（Requirement 2.5）。
///
/// 调用后，其后 `emit` 的、级别低于新生效级别的记录将被丢弃，不再输出。
pub fn SinkHandle::set_level(self : SinkHandle, level : Level) -> Unit {
  self.level = level
}

// ───────────────────────────── 派发与下发 ────────────────────────────────

///|
/// 派发一条事件（按本句柄生效级别过滤后交付目标，Requirement 2.1–2.6）。
///
/// 级别判定（AC6）：仅当 `event.level.rank() >= self.level.rank()` 时才继续，
/// 否则直接丢弃——既不写 Console、不调用回调，也不进入 Buffered 的缓冲。
///
/// 各目标行为：
///   * `TConsole`（AC1）：`println(format_event(self.formatter, event))`；
///   * `TCallback`（AC2）：以 `event` 为参数恰好调用一次回调；
///   * `TBuffered`（AC3/AC4）：`buffer.push(event)`；当缓冲数达到 `threshold`
///     时调用 `flush` 按到达顺序全部下发并清空。
pub fn SinkHandle::emit(self : SinkHandle, event : Event) -> Unit {
  // AC6：级别低于生效级别的记录不交付任何下游（含不进入 Buffered 缓冲）。
  if event.level.rank() < self.level.rank() {
    return
  }
  match self.target {
    TConsole =>
      // AC1：经格式器渲染后写入标准输出。
      println(format_event(self.formatter, event))
    TCallback(cb) =>
      // AC2：恰好调用一次回调。
      cb(event)
    TBuffered(threshold~, ..) => {
      // AC3：未达阈值时仅暂存，不交付下游。
      self.buffer.push(event)
      // AC4：达到阈值即按到达顺序批量下发并清空缓冲。
      if self.buffer.length() >= threshold {
        self.flush()
      }
    }
  }
}

///|
/// 强制下发缓冲（Requirement 2.4）。
///
/// 仅 `TBuffered` 有实质行为：按记录到达顺序对下游 `down` 逐条 `emit`，随后清空
/// 本句柄缓冲。非 Buffered 句柄无缓冲，`flush` 为安全的空操作。
///
/// 注意：下发时对下游调用 `down.emit`，故下游会再次按其自身生效级别过滤——
/// 这与「每个 sink 句柄独立调级」的语义一致。
pub fn SinkHandle::flush(self : SinkHandle) -> Unit {
  match self.target {
    TBuffered(down~, ..) => {
      // 按到达顺序逐条下发。
      for ev in self.buffer {
        down.emit(ev)
      }
      // 清空缓冲（下游已接收全部记录）。
      self.buffer = []
    }
    // Console / Callback 无缓冲，flush 无需动作。
    _ => ()
  }
}

// ───────────────────────────── 内联烟雾测试 ──────────────────────────────
// 仅极少量基础冒烟，完整属性测试见任务 3.2。

///|
/// 构造一条用于测试的最小事件（空字段）。
fn smoke_event(level : Level) -> Event {
  Event::new(0L, level, {})
}

///|
test "callback sink 级别通过时恰好调用一次" {
  let hits = []
  let sink = SinkHandle::callback(fn(e) { hits.push(e) })
  sink.emit(smoke_event(Info))
  assert_eq(hits.length(), 1)
}

///|
test "callback sink 级别不足时不调用（AC6）" {
  let hits = []
  let sink = SinkHandle::callback(fn(e) { hits.push(e) }, level=Warn)
  sink.emit(smoke_event(Info)) // Info < Warn，应被丢弃
  assert_eq(hits.length(), 0)
}

///|
test "buffered sink 阈值前不下发、达阈值按序全发（AC3/AC4）" {
  let received : Array[Level] = []
  let down = SinkHandle::callback(fn(e) { received.push(e.level) })
  let buf = SinkHandle::buffered(2, down)
  buf.emit(smoke_event(Info))
  assert_eq(received.length(), 0) // 未达阈值，暂存不下发
  buf.emit(smoke_event(Warn))
  assert_eq(received, [Info, Warn]) // 达阈值，按到达顺序全部下发
  assert_eq(buf.buffer.length(), 0) // 缓冲已清空
}

///|
test "buffered sink 显式 flush 下发剩余缓冲（AC4）" {
  let received : Array[Level] = []
  let down = SinkHandle::callback(fn(e) { received.push(e.level) })
  let buf = SinkHandle::buffered(10, down)
  buf.emit(smoke_event(Error))
  assert_eq(received.length(), 0)
  buf.flush()
  assert_eq(received, [Error])
}

///|
test "set_level 运行时调级后丢弃低级别记录（AC5）" {
  let hits = []
  let sink = SinkHandle::callback(fn(e) { hits.push(e) })
  sink.set_level(Error)
  sink.emit(smoke_event(Info)) // 调级后 Info < Error，应丢弃
  assert_eq(hits.length(), 0)
  sink.emit(smoke_event(Error))
  assert_eq(hits.length(), 1)
}
