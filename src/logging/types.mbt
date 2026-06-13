// types.mbt —— Logging_Library 的核心数据模型。
//
// 设计依据（design.md §「方向七：Logging_Library」核心类型与流水线）：
//
//   pub enum Level { Trace; Debug; Info; Warn; Error }
//   pub struct Event { ts : Int64; level : Level; fields : Map[String, Value] }
//   pub struct Span  { id : SpanId; parent : SpanId?; start : Int64; end : Int64? }
//
//   pub fn log(level : Level, fields : Map[String, Value]) -> Unit
//   pub fn enter_span(name : String) -> Span
//   pub fn exit_span(s : Span) -> Unit
//   pub fn format_json(e : Event) -> String
//   pub fn parse_json_log(s : String) -> Event?
//
// 本文件锁定数据模型骨架；接口桩位于 logging.mbt。`Value`、`SpanId`、`TraceId`
// 在 design 的类型签名中以名义类型出现（`Map[String, Value]`、`SpanId?`），
// 本任务给出其最小、纯、可三后端一致的具体定义。

// ───────────────────────────── 日志级别 ──────────────────────────────────

///|
/// 日志级别（severity）。严重程度自低到高：Trace < Debug < Info < Warn < Error。
///
/// 级别用于阈值过滤（Requirement 7.2）：低于配置阈值的事件将被丢弃。完整的
/// 阈值过滤实现位于任务 10.2；本任务提供级别本身与其严重程度序（见 `rank`）。
pub(all) enum Level {
  Trace
  Debug
  Info
  Warn
  Error
} derive(Eq, Show)

///|
/// 返回级别的严重程度序数（Trace=0 … Error=4），用于阈值比较。
pub fn Level::rank(self : Level) -> Int {
  match self {
    Trace => 0
    Debug => 1
    Info => 2
    Warn => 3
    Error => 4
  }
}

///|
/// 判断本级别在给定阈值下是否应被记录（严重程度不低于阈值即记录）。
///
/// 这是任务 10.2「级别阈值过滤」（Requirement 7.2）的纯判定原语，先行提供
/// 以便单元测试与后续 `log` 实现复用。
pub fn Level::is_enabled(self : Level, threshold : Level) -> Bool {
  self.rank() >= threshold.rank()
}

///|
/// 返回级别的大写文本标签（用于结构化输出）。
pub fn Level::label(self : Level) -> String {
  match self {
    Trace => "TRACE"
    Debug => "DEBUG"
    Info => "INFO"
    Warn => "WARN"
    Error => "ERROR"
  }
}

///|
/// 由大写文本标签还原级别（`label` 的逆映射），用于结构化日志解析。
///
/// 与 `label` 构成双射，支撑 `format_json` / `parse_json_log` 的级别字段往返
/// （Requirement 7.7）。无法识别的标签返回 `None`。
pub fn Level::from_label(s : String) -> Level? {
  match s {
    "TRACE" => Some(Trace)
    "DEBUG" => Some(Debug)
    "INFO" => Some(Info)
    "WARN" => Some(Warn)
    "ERROR" => Some(Error)
    _ => None
  }
}

// ─────────────────────────── 结构化字段取值 ───────────────────────────────

///|
/// 结构化日志字段的取值（structured field value）。
///
/// 标量取值（`VStr` / `VInt` / `VBool` / `VFloat`）覆盖最常见的字段类型；
/// 旗舰深化（Requirement 1.1 / 1.2）在其上**加性追加**两个嵌套取值变体：
///   * `VMap`  —— 对象型键值映射（嵌套结构化字段，对应 JSON 对象）；
///   * `VList` —— 数组型有序元素序列（对应 JSON 数组）。
/// 嵌套取值可任意层级容纳标量与进一步的 `VMap` / `VList`（Requirement 1.2）。
///
/// **向后兼容契约（Requirement 12.1 / 12.4）**：既有四个标量变体的名称、载荷
/// 与 `derive(Eq, Show)` 语义逐字保留；本次仅在其后**追加**两个变体，不改动、
/// 不重排、不重命名任何既有变体，故仅含标量字段事件的 `format_json` /
/// `parse_json_log` 行为逐字节不变（嵌套臂仅在 logging.mbt 私有助手中追加）。
///
/// 注意 `VMap` 的 `Eq` 经由 `Map` 的内容相等（与键插入顺序无关）判定，这正是
/// 「JSON 对象成员升序稳定排序后再往返」仍满足逐字段相等的代数基础
/// （见 Property 1：嵌套 JSON 往返）。
pub(all) enum Value {
  VStr(String)
  VInt(Int64)
  VBool(Bool)
  VFloat(Double)
  VMap(Map[String, Value]) // 新增：对象型嵌套取值（Requirement 1.1）
  VList(Array[Value]) // 新增：数组型嵌套取值（Requirement 1.1）
} derive(Eq, Show)

// ───────────────────────────── 标识符类型 ─────────────────────────────────

///|
/// span 标识（span identifier）—— span 树中节点的唯一标识。
///
/// 以单调递增的 `Int64` 承载，保证进程内唯一；具体分配见 logging.mbt 的
/// `enter_span` 桩。三后端（wasm-gc / js / native）对 `Int64` 语义一致。
pub(all) struct SpanId {
  value : Int64
} derive(Eq, Show)

///|
/// trace 上下文标识（trace identifier）—— 一次逻辑请求/任务链路的根标识。
///
/// 用于「跨异步任务边界传播 trace 上下文」（Requirement 7.6）。本骨架任务以
/// 该**本地最小抽象**占位，刻意不耦合 `moonbitlang/async`；待 async 依赖稳定
/// 登记后，由任务 10.2 升级为基于异步任务局部存储的真实上下文传播载体
/// （详见 moon.pkg 中的依赖处理说明）。
pub(all) struct TraceId {
  value : Int64
} derive(Eq, Show)

// ────────────────────────────── 事件与 span ──────────────────────────────

///|
/// 一条日志事件（log event）：时间戳 + 级别 + 全部结构化字段。
///
/// 对应 Requirement 7.1「输出包含时间戳、级别与全部结构化字段的日志记录」。
/// `ts` 为自纪元起的逻辑时间戳（具体时钟源接入属任务 10.2）。
pub(all) struct Event {
  ts : Int64
  level : Level
  fields : Map[String, Value]
} derive(Eq, Show)

///|
/// 构造一条事件（便于测试与 `log` 内部复用）。
pub fn Event::new(
  ts : Int64,
  level : Level,
  fields : Map[String, Value],
) -> Event {
  { ts, level, fields }
}

///|
/// 一个 span（跨度）—— span 树中的节点：唯一 id、可选父 span、起止时间戳。
///
/// 对应 design 的 `Span { id; parent; start; end }`。`parent` 为 `None` 表示
/// 根 span；`end` 为 `None` 表示该 span 尚未结束（`exit_span` 后由任务 10.2
/// 填充并据此计算时长，Requirement 7.5）。
pub(all) struct Span {
  id : SpanId
  parent : SpanId?
  start : Int64
  end : Int64?
} derive(Eq, Show)
