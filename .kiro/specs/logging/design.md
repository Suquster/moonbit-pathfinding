# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 `logging 0.1.0` 骨架之上，做**增量式、严格向后兼容**的旗舰级（🟣 档位 3）深化，目标对标 Rust `tracing`、`slog`、Uber `zap` 与 OpenTelemetry SDK 的结构化日志与分布式追踪模型。核心原则一句话：**既有公开类型与函数（`Level`/`Value`/`Event`/`Span`/`SpanId`/`TraceId`/`TraceContext` 与 `log`/`set_threshold`/`current_threshold`/`enter_span`/`exit_span`/`span_duration`/`begin_trace`/`capture_context`/`child_context`/`with_context`/`format_json`/`parse_json_log`/`captured_events`/`finished_spans`/`current_span`/`current_trace`/`reset_logger`）的签名与运行时语义一律冻结，所有新能力以旁路扩展（新增 `.mbt` 文件、新增类型、新增函数 / 方法）的方式提供。**

唯一的、刻意的**就地加性扩展**是 `Value` 枚举：在既有标量变体 `VStr`/`VInt`/`VBool`/`VFloat` 之上**追加** `VMap`/`VList` 两个嵌套变体（MoonBit 枚举变体必须在同一处声明，无法旁路新增）。该扩展严格满足「既有标量变体不变、`format_json`/`parse_json_log` 对仅含标量字段事件逐字节输出与解析行为不变」的兼容契约（Requirement 1.5 / 12.4）——见 §「数据模型」与 §「设计权衡」对此取舍的论证。

本方向**显式声明实现边界**（Requirement 10.6）：Logging_Library 是结构化日志与分布式追踪的**内存与字符串模型层**，停留在「事件、span 树、上下文、格式器 / 解析器、采样 / 过滤 / 脱敏 / 指标的纯函数与确定性运行时」这一抽象层——**不**做真实网络 / 文件导出（sink 以内存缓冲建模）、**不**耦合 `moonbitlang/async`（以既有「显式上下文捕获 + `with_context`」模型替代异步任务局部存储）、**不**接入真实墙钟（以既有单调逻辑时钟建模时间戳）。该边界使核心逻辑可被属性测试穷尽校验，且 `wasm-gc` / `js` / `native` 三后端行为逐位一致。

既有骨架流水线保持不变并被复用：

```
log ─ 级别阈值过滤（冻结）─▶ Event（ts/level/fields，注入 trace/span 保留键）─▶ captured_events
enter_span / exit_span（冻结）─▶ span 树（parent 取进入时激活 span）+ 时长（span_duration）
begin_trace / capture_context / child_context / with_context（冻结）─▶ trace 上下文传播
format_json / parse_json_log（冻结公开签名）─▶ 结构化 JSON 往返
```

旗舰深化在其旁侧新增一条**多格式渲染 → 采样 / 限流 → 过滤 / 路由 → OTel span 语义 → W3C 传播 → 脱敏 → 指标派生**的增量流水线：

```
                          ┌──────────────── 旁路新增能力 ────────────────┐
Event ─▶ Formatter{Json|Logfmt|Pretty} ─render─▶ 文本 ─parse─▶ Event（JSON / logfmt 往返）
  │                                              │
  │       ┌── 采样 / 限流 ──┐  ┌── 过滤 / 路由 ──┐  ┌── 脱敏 ──┐  ┌── 指标 ──┐
  ├──────▶ sample_trace / sample_stream / RateLimiter
  ├──────▶ EnvFilter / field_filter / route ─▶ Sink[]（内存缓冲 + formatter + 路由谓词）
  ├──────▶ redact（敏感字段整体掩码，键集合不变）
  └──────▶ count_by_level / histogram（确定性聚合）

Span（既有）─叠加─▶ SpanData{attributes/events/status/kind}（OTel 语义，旁路）
TraceContext（既有）─inject─▶ traceparent 文本 ─extract─▶ W3CContext ─▶ TraceContext（W3C 传播）
```

旗舰能力分十条主线落地：① 嵌套结构化取值与嵌套 JSON 往返；② 多 sink 与多 formatter（JSON / logfmt / pretty + 解析器往返）；③ 确定性采样与限流；④ 过滤与路由（target 阈值 / 字段谓词 / EnvFilter）；⑤ OpenTelemetry 风格 span 语义；⑥ W3C Trace Context 注入 / 提取；⑦ 脱敏 / PII 过滤；⑧ 指标派生；⑨ 性能基准；⑩ 端到端 demo。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、三后端一致性策略、错误处理与正确性属性。

---

## 架构（Architecture）

### 设计原则与向后兼容契约（Requirement 12）

1. **冻结即契约**：`types.mbt`（`Level`/`Event`/`Span`/`SpanId`/`TraceId` 及其方法 `Level::rank`/`is_enabled`/`label`/`from_label`、`Event::new`）与 `logging.mbt`（全部既有 `pub` 函数与 `TraceContext`）中现有声明的签名、字段与运行时行为一律不改（R12.1 / R12.2）。`pkg.generated.mbti` 现有条目保持稳定，新增条目仅追加。
2. **`Value` 加性扩展（唯一就地变更，刻意取舍）**：`Value` 枚举追加 `VMap(Map[String, Value])` 与 `VList(Array[Value])`（R1.1 / R1.2）。既有四个标量变体的构造形态、`derive(Eq, Show)` 语义与匹配行为不变；私有 JSON 助手 `value_to_json` / `jval_to_value` / JSON 读取器仅**追加** `VMap`/`VList`/数组的匹配臂，标量臂逐字保留，故 `format_json`/`parse_json_log` 对仅含标量字段事件的输出与解析逐字节不变（R1.5 / R12.4）。详见 §「数据模型」。
3. **既有过滤 / span / 上下文 / JSON 语义不变**：`log` 继续做级别阈值过滤并注入 `trace`/`span` 保留键；`enter_span`/`exit_span` 继续以「进入时激活 span」为父、单调逻辑时钟计时；`with_context` 继续以显式上下文捕获 / 还原模拟任务边界。采样、限流、过滤路由、OTel 语义、traceparent、脱敏、指标全部以**新入口纯函数**提供，不改既有运行时副作用。
4. **既有资产复用而非重写**（R12.3 / R12.5）：嵌套 JSON 复用既有 `JsonReader` / `parse_value` 递归下降骨架（仅追加数组与嵌套对象映射）；span 语义叠加在既有 `Span` 之上；W3C 上下文桥接既有 `TraceContext`；全部新增属性测试复用 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all` / `round_trip`（每条 ≥100 迭代）；发布元数据复用 `@release_meta`，`release_info` / `release_info_with_gates` 语义不变（R12.6）。

### 模块 / 文件划分

下表为 `src/logging/` 下的文件规划。**既有文件**保持冻结（`types.mbt` 仅做 `Value` 加性扩展；其余仅在必要处追加 import）；**新增文件**承载旗舰能力。

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `types.mbt` | 加性扩展 | 既有核心类型；`Value` 追加 `VMap`/`VList` 嵌套变体 | R1.1 / R1.2 / R12.1 |
| `logging.mbt` | 冻结公开签名 / 私有助手追加嵌套臂 | 既有运行时与 JSON 编解码；`value_to_json`/`jval_to_value`/`parse_value` 追加 `VMap`/`VList`/数组分支（标量行为不变） | R1.3 / R1.4 / R12.2 / R12.4 |
| `release.mbt` | 冻结 / 版本字符串更新 | 发布元数据登记（仅推进 SemVer 字符串） | R12.6 / R13.6 |
| `value_ext.mbt` | 新增 | 嵌套取值助手：`Value::is_scalar`/`is_nested`/`depth`，嵌套值构造与（测试用）嵌套生成器约定 | R1.2 |
| `formatter.mbt` | 新增 | `Formatter{Json|Logfmt|Pretty}`、`format_event`、可插拔 `Sink`（内存缓冲 + formatter + 路由谓词）、`dispatch` 多 sink 交付 | R2.1 / R2.2 / R2.4 / R2.5 |
| `logfmt.mbt` | 新增 | logfmt 格式器 `format_logfmt` 与解析器 `parse_logfmt`（引号 / 转义 / 往返） | R2.3 / R2.6 / R2.7 |
| `sampling.mbt` | 新增 | 确定性采样 `sample_trace`（trace 内一致）/ `sample_stream`（比例有界）、限流 `RateLimiter` | R3.* |
| `filter.mbt` | 新增 | `EnvFilter` 指令解析与阈值判定、字段谓词 `field_filter`、路由 `route` | R4.* |
| `otel_span.mbt` | 新增 | `SpanData`（属性 / 事件 / 状态 / kind），旁路叠加既有 `Span` | R5.* |
| `trace_context.mbt` | 新增 | W3C `traceparent` 注入 `inject_traceparent` / 提取 `extract_traceparent`，桥接既有 `TraceContext` | R6.* |
| `redaction.mbt` | 新增 | 脱敏 / PII 掩码 `redact`（字段名集合 / 谓词，嵌套整体掩码，键集合不变） | R7.* |
| `metrics.mbt` | 新增 | 指标派生 `count_by_level`、`histogram`（确定性） | R8.* |
| `demo.mbt` | 新增 | 端到端实战链路 demo（嵌套 span / 采样 / 脱敏 / 多格式 / traceparent 跨进程） | R11.* |
| `README.mbt.md` | 扩充 | 可执行文档覆盖全部新能力 | R11 / R13.4 |
| `CHANGELOG.md` | 扩充 | SemVer 推进记录 | R13.6 |
| `prop_*_test.mbt` | 新增 | 属性测试（见 §「测试策略」「正确性属性」） | R13.2 |

`benches/` 下新增基准包 `benches/logging_bench/`（`logging_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`），结构对齐既有 `benches/astar_bench` 等，产出 `benches/results/` 工件并接入 guard（R9）。

### 依赖方向

```
value_ext ──▶ types（Value 扩展）
formatter ──▶ value_ext, logfmt（JSON 复用 logging.mbt 既有编解码）
logfmt    ──▶ types
sampling  ──▶ types, @infra_pbt(Rng)
filter    ──▶ types, formatter(Sink)
otel_span ──▶ types（叠加既有 Span）
trace_context ──▶ types（桥接既有 TraceContext）
redaction ──▶ value_ext, formatter
metrics   ──▶ types
demo      ──▶ 以上全部
（全部单向依赖既有 types/logging 与共享叶子包；测试依赖 @infra_pbt；发布复用 @release_meta）
```

无反向依赖：既有冻结代码不感知任何新增文件；新增文件单向依赖既有模型与共享叶子包。

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt` / `.mbti` 风格（`pub(all)` 暴露可构造数据，`pub` 暴露只读结构与函数）。

### 4.1 嵌套结构化取值与嵌套 JSON 往返（Requirement 1）

`Value` 枚举加性扩展（声明于 `types.mbt`）：

```moonbit
// types.mbt（加性扩展：既有四个标量变体逐字保留，追加两个嵌套变体）
pub(all) enum Value {
  VStr(String)
  VInt(Int64)
  VBool(Bool)
  VFloat(Double)
  VMap(Map[String, Value])   // 新增：对象型嵌套取值（R1.1）
  VList(Array[Value])        // 新增：数组型嵌套取值（R1.1）
} derive(Eq, Show)
```

嵌套助手（`value_ext.mbt`）：

```moonbit
// value_ext.mbt
pub fn Value::is_scalar(self : Value) -> Bool   // VStr/VInt/VBool/VFloat -> true
pub fn Value::is_nested(self : Value) -> Bool   // VMap/VList -> true
pub fn Value::depth(self : Value) -> Int        // 标量为 0；嵌套为 1 + max(子取值 depth)
```

既有 JSON 编解码（`logging.mbt`）的**加性扩展**（标量臂不变）：

```moonbit
// value_to_json：追加
//   VMap(m)  => "{" + 成员按键名升序、"key":value 递归渲染 + "}"   // R1.3（对象成员升序稳定排序）
//   VList(xs) => "[" + 元素按原序递归渲染、逗号分隔 + "]"          // R1.3
// jval_to_value：追加
//   JObj(pairs) => Some(VMap(...))   // 之前返回 None，改为还原嵌套对象（R1.4）
//   JArr(items) => Some(VList(...))  // 新增数组分支（R1.4）
// JsonReader/parse_value：追加 '[' => parse_array 分支与 JVal::JArr 变体
```

设计要点：① **对象成员升序**——`value_to_json` 渲染 `VMap` 时对成员键做与顶层 `fields` 同样的升序稳定排序，保证三后端逐字节一致（R1.3）。② **递归任意深度**——`VMap`/`VList` 元素可为任意 `Value`，编解码递归处理（R1.2）。③ **标量行为冻结**——标量变体的渲染与解析臂逐字保留，仅含标量字段的事件输出与解析与 `0.1.0` 逐字节一致（R1.5 / R12.4）。④ **嵌套往返**——`parse_json_log(format_json(e))` 对任意嵌套深度事件还原等价事件（R1.6，正确性属性 1）。

### 4.2 多 sink 与多 formatter（Requirement 2）

```moonbit
// formatter.mbt
/// 内置格式器种类（R2.1）。
pub(all) enum Formatter {
  Json      // 复用 logging.mbt 的 format_json（含嵌套）
  Logfmt    // 复用 logfmt.mbt 的 format_logfmt
  Pretty    // 人类可读对齐文本
} derive(Eq, Show)

/// 将一条事件按指定格式器渲染为文本（R2.1）。输出由事件内容唯一确定，三后端
/// 逐字节一致（R2.2）。
pub fn format_event(fmt : Formatter, e : Event) -> String

/// 可插拔 sink：内存缓冲 + 绑定格式器 + 路由谓词（R2.4）。模型层不接真实 IO。
pub(all) struct Sink {
  name : String
  formatter : Formatter
  route : (Event) -> Bool      // 路由条件；默认恒真（接收全部）
  mut buffer : Array[String]   // 已交付事件的渲染文本（内存落地）
}
pub fn Sink::new(name : String, formatter : Formatter, route? : (Event) -> Bool) -> Sink

/// 将一条事件交付给全部已注册且路由条件匹配的 sink（R2.5）。无匹配则不交付。
pub fn dispatch(sinks : Array[Sink], e : Event) -> Unit
```

`Pretty` 格式器输出形如 `ts=<n> [INFO] key=value …` 的对齐单行；不参与往返（仅供阅读）。`Json` 与 `Logfmt` 均有对应解析器构成往返（见 4.1 与 4.3）。`dispatch` 遍历 sink 列表，对每个 `route(e)` 为真者将 `format_event(sink.formatter, e)` 推入其 `buffer`，从而同一事件可同时落地多种格式（R2.5）。

### 4.3 logfmt 格式器与解析器（Requirement 2.3 / 2.6 / 2.7）

```moonbit
// logfmt.mbt
/// 将事件渲染为单行 logfmt：ts=<n> level=<LABEL> <k>=<v> …（字段按键名升序）。
/// 含空格 / 等号 / 引号 / 控制字符的取值施加双引号包裹与转义（R2.3）。
pub fn format_logfmt(e : Event) -> String

/// 将 logfmt 文本解析回等价事件（R2.6）；语法非法返回 None（不产部分事件）。
pub fn parse_logfmt(s : String) -> Event?
```

logfmt 约定（对标 Go `go-kit/log`、Heroku logfmt）：以空格分隔的 `key=value` 对，无引号值止于空格；含特殊字符的值用双引号包裹并按与 JSON 同源的转义规则编解码。`ts` 渲染为整数、`level` 渲染为大写标签（经 `Level::from_label` 逆映射还原）。标量取值往返：`parse_logfmt(format_logfmt(e))` 对仅含标量字段事件还原等价事件（R2.7，正确性属性 3）。嵌套取值在 logfmt 域内以内嵌 JSON 文本表示，往返保证仅声明于标量字段域（与 R2.7 一致）。

### 4.4 确定性采样与限流（Requirement 3）

采样分两种互补机制，分别服务「trace 内一致」与「比例有界」两类需求；二者均确定性、可重放，并以 `@infra_pbt.Rng` 为随机源。

```moonbit
// sampling.mbt
/// trace 内一致采样判定（R3.3 / R3.6）：决策仅由 trace 标识与配置（rate, seed）
/// 决定，故同一 trace 的全部事件得到相同决策。
/// 算法：keep ⟺ (mix(trace.value, seed) mod DENOM) < threshold(rate)，
/// 其中 threshold(rate) = floor(rate * DENOM)。
/// 边界：rate=0.0 ⟹ threshold=0 ⟹ 恒弃；rate=1.0 ⟹ threshold=DENOM ⟹ 恒采（R3.2）。
pub fn sample_trace(rate : Double, trace : TraceId, seed : UInt64) -> Bool

/// 事件流系统采样（R3.1 / R3.7）：确定性保留 floor(rate*n) 条事件，使保留占比
/// 有上界。以 Rng 决定保留相位（哪些下标），但保留**条数**固定，故比例可证有界。
/// 边界：rate=0.0 ⟹ 全弃；rate=1.0 ⟹ 全采（R3.2）。重放同种子得同结果（R3.4）。
pub fn sample_stream(rate : Double, events : Array[Event], rng : @infra_pbt.Rng) -> Array[Event]

/// 给定事件数 n 与采样率，保留条数上界 = floor(rate*n)（≤ rate*n）。
pub fn retained_count(rate : Double, n : Int) -> Int

/// 限流器：在给定逻辑时间窗内限制某 key（级别标签或字段键）允许通过的条数（R3.5）。
pub(all) struct RateLimiter {
  window : Int64
  limit : Int
  mut state : Map[String, (Int64, Int)]   // key -> (窗口起点, 窗内已通过条数)
}
pub fn RateLimiter::new(window : Int64, limit : Int) -> RateLimiter
/// 在逻辑时间 ts 对 key 申请通过：窗内未超配额则放行并计数，否则丢弃（R3.5）。
pub fn RateLimiter::allow(self : RateLimiter, key : String, ts : Int64) -> Bool
```

`mix` 为纯整型混合函数（FNV/xorshift 风格，见 §「三后端一致性」），保证三后端逐位一致且对 trace 标识均匀散布。`sample_stream` 用系统采样（systematic sampling）：按确定性步长保留事件，保留条数恰为 `floor(rate*n)`，从而「保留占比 ≤ rate（含量化）」成为构造性事实（R3.7，正确性属性 6）；`rng` 仅决定相位（保留下标的起点），不改变条数，故确定且可重放（R3.4，正确性属性 7）。`RateLimiter::allow` 在 `ts` 超出当前窗口时重置窗口起点与计数，窗内放行至 `limit` 条后丢弃超额事件（R3.5，正确性属性 8）。

### 4.5 过滤与路由（Requirement 4）

```moonbit
// filter.mbt
/// EnvFilter：各 target 的级别阈值表 + 全局兜底阈值（R4.3）。
pub(all) struct EnvFilter {
  directives : Map[String, Level]
  default : Level
}
/// EnvFilter 指令解析错误（携带定位信息，R4.4）。
pub(all) struct FilterError {
  pos : Int        // 出错字符偏移
  message : String
} derive(Eq, Show)

/// 解析形如 "target=level,target2=level2,level"（末尾裸 level 为兜底）的指令集合。
/// 语法非法返回 Err(FilterError) 且不登记任何阈值（R4.3 / R4.4）。
pub fn parse_env_filter(spec : String) -> Result[EnvFilter, FilterError]

/// 取某 target 的有效阈值：命中指令则用其阈值，否则用全局兜底（R4.1）。
pub fn EnvFilter::threshold_for(self : EnvFilter, target : String) -> Level

/// 事件是否被保留：当且仅当其级别不低于其 target 的有效阈值（R4.1 / R4.6）。
/// target 取自事件的 "target" 字段（缺失则用空串走兜底）。
pub fn EnvFilter::allows(self : EnvFilter, e : Event) -> Bool

/// 字段谓词过滤：仅保留字段满足谓词的事件（R4.2）。
pub fn field_filter(pred : (Map[String, Value]) -> Bool, e : Event) -> Bool

/// 路由：返回条件匹配该事件的全部 sink 名称（R4.5）。无匹配返回空数组（不交付）。
pub fn route(sinks : Array[Sink], e : Event) -> Array[String]
```

EnvFilter 指令文法（对标 Rust `tracing-subscriber` 的 `EnvFilter`）：逗号分隔的项，每项为 `target=level` 或裸 `level`（裸 level 作为全局兜底，多次出现以最后一次为准）；`level` 经 `Level::from_label` 的大小写归一映射识别。解析「先完整校验后构造」：任一项非法（缺 `=`、级别标签不可识别）返回 `Err(FilterError{pos, message})` 且 `directives` 为空（R4.4）。`allows` 是过滤判定一致性（R4.6，正确性属性 9）的单点：保留 ⟺ `e.level.rank() >= threshold_for(target).rank()`。`route` 对路由匹配交付（R4.5）的多 sink 分发与 `dispatch` 协同。

### 4.6 OpenTelemetry 风格 span 语义（Requirement 5）

```moonbit
// otel_span.mbt
/// span 状态（R5.3），默认 Unset。
pub(all) enum SpanStatus { Unset; Ok; Error } derive(Eq, Show)
/// span 类别（R5.4），默认 Internal。
pub(all) enum SpanKind { Internal; Server; Client; Producer; Consumer } derive(Eq, Show)
/// span 事件（R5.2）：名称 + 逻辑时间戳 + 字段。
pub(all) struct SpanEvent {
  name : String
  ts : Int64
  fields : Map[String, Value]
} derive(Eq, Show)

/// OTel 语义包裹：在既有 Span 之上旁路叠加属性 / 事件 / 状态 / kind（R5.5）。
pub(all) struct SpanData {
  span : Span                       // 既有 Span（id/parent/start/end），不改其语义
  mut attributes : Map[String, Value]
  mut events : Array[SpanEvent]
  mut status : SpanStatus
  mut kind : SpanKind
} derive(Eq, Show)

/// 由既有 Span 构造 OTel 包裹（默认 status=Unset, kind=Internal，空属性 / 事件）。
pub fn SpanData::new(span : Span) -> SpanData
pub fn SpanData::set_attribute(self : SpanData, key : String, value : Value) -> Unit  // R5.1
pub fn SpanData::add_event(self : SpanData, name : String, ts : Int64, fields : Map[String, Value]) -> Unit  // R5.2
pub fn SpanData::set_status(self : SpanData, status : SpanStatus) -> Unit  // R5.3
pub fn SpanData::set_kind(self : SpanData, kind : SpanKind) -> Unit        // R5.4
```

OTel 语义为**纯旁路叠加**：`SpanData` 持有既有 `Span` 而不改其字段或 `enter_span`/`exit_span`/`span_duration` 行为（R5.5）。属性设置后在结束记录中保留（R5.1）；span 事件保留名称 / 时间戳 / 字段并归属当前 span（R5.2）；状态与 kind 默认值符合 OTel 规范（R5.3 / R5.4）。既有 `enter_span`/`exit_span` 的 span 树父子不变量与时长非负由属性测试固化（R5.6，正确性属性 10）。

### 4.7 W3C Trace Context 注入 / 提取（Requirement 6）

```moonbit
// trace_context.mbt
/// W3C traceparent 解析结果（十六进制分量 + flags 整数）。
pub(all) struct W3CContext {
  trace_id : String   // 32 位小写 hex
  span_id : String    // 16 位小写 hex
  flags : Int         // 0..=255（trace-flags 字节）
} derive(Eq, Show)

/// 将既有 TraceContext 注入为 traceparent 文本："00-<32hex>-<16hex>-<2hex>"（R6.1）。
/// trace.value(Int64) 编码进低 64 位（高 64 位补 0）→ 32 hex；span 取 16 hex；
/// flags 默认 01（sampled）。
pub fn inject_traceparent(ctx : TraceContext) -> String

/// 提取语法合法的 traceparent，还原 trace-id / span-id / flags 三分量（R6.2）。
/// 字段数 / 分隔符 / 各分量长度不符规范则返回 None，不产部分上下文（R6.4）。
pub fn extract_traceparent(s : String) -> W3CContext?

/// trace-flags 最低位为 1 ⟹ 已采样（R6.3）。
pub fn W3CContext::is_sampled(self : W3CContext) -> Bool

/// 桥接回既有 TraceContext，使可经 with_context 在该上下文下继续记录（R6.5）。
/// trace_id 低 64 位 hex → TraceId.value；span_id → SpanId.value。
pub fn W3CContext::to_trace_context(self : W3CContext) -> TraceContext
```

格式与字段语义追溯 W3C Trace Context 规范：`version(2hex)-trace-id(32hex)-parent-id(16hex)-trace-flags(2hex)`。提取做严格校验：恰 4 个 `-` 分隔字段、各分量长度精确、各字符为合法 hex，否则返回 `None`（R6.4）。**实现边界**：内部 `TraceId`/`SpanId` 为 64 位 `Int64`，而 traceparent trace-id 为 128 位——本库将 64 位标识编码进低 64 位、高位补 0，故 `inject` 再 `extract` 对内部标识做无损往返（R6.6，正确性属性 11），此 128↔64 映射在文档中显式声明（R10.6）。`to_trace_context` 使提取结果与既有 `TraceContext` 模型兼容（R6.5）。

### 4.8 脱敏 / PII 过滤（Requirement 7）

```moonbit
// redaction.mbt
/// 固定掩码标记（R7 掩码标记）：不泄露原值任何片段。
pub let redaction_mask : Value = VStr("[REDACTED]")

/// 脱敏策略：敏感字段名集合 + 可选字段谓词（按名或按谓词判定敏感）。
pub(all) struct RedactionPolicy {
  sensitive : Array[String]
  predicate : (String, Value) -> Bool   // 默认恒假
}
pub fn RedactionPolicy::by_names(names : Array[String]) -> RedactionPolicy
pub fn RedactionPolicy::with_predicate(self : RedactionPolicy, pred : (String, Value) -> Bool) -> RedactionPolicy

/// 对事件施加脱敏：敏感字段（名命中或谓词为真）取值整体替换为 redaction_mask，
/// 其余字段不变；字段键集合保持不变（R7.1 / R7.2 / R7.3）。嵌套 VMap/VList
/// 敏感字段整体掩码，内部无任何原值片段残留（R7.4）。
pub fn redact(policy : RedactionPolicy, e : Event) -> Event
```

脱敏对每个字段判定「名命中 `sensitive` 集合 或 `predicate(key, value)` 为真」；命中者其取值**整体**替换为常量 `redaction_mask`（即使原值为嵌套 `VMap`/`VList` 也整体替换，杜绝深层泄露，R7.4），未命中者原样保留。键集合不变（R7.3）。脱敏完整性（R7.5，正确性属性 12）：脱敏后每个敏感字段取值等于掩码、且字段键集合与脱敏前逐一致——由于整体常量替换，输出不含任何敏感字段原值片段为构造性事实。

### 4.9 指标派生（Requirement 8）

```moonbit
// metrics.mbt
/// 按级别计数：返回长度 5 的非负计数数组，下标 = Level::rank（Trace=0..Error=4）。
/// 用定长数组（而非 Map[Level,_]）规避三后端 Map 迭代顺序差异（R8.1）。
pub fn count_by_level(events : Array[Event]) -> Array[Int]
pub fn level_count(counts : Array[Int], level : Level) -> Int

/// 直方图：按升序边界把某数值字段分桶并计数。
/// 桶数 = len(boundaries)+1（含上溢桶）。缺该字段或字段非数值的事件被跳过（R8.3）。
pub(all) struct Histogram {
  boundaries : Array[Double]
  buckets : Array[Int]
} derive(Eq, Show)
pub fn histogram(events : Array[Event], field : String, boundaries : Array[Double]) -> Histogram
```

`count_by_level` 遍历事件按 `level.rank()` 累加（R8.1）；计数守恒：各级别计数之和等于事件总数（R8.4，正确性属性 13）。`histogram` 对每条含目标数值字段（`VInt`/`VFloat`）的事件按边界二分入桶，缺字段或非数值（`VStr`/`VBool`/`VMap`/`VList`）的事件跳过不计（R8.3）。两个派生均为纯函数，对同一输入两次派生逐桶相等（R8.5，正确性属性 14）。

### 4.10 端到端实战 demo（Requirement 11）

```moonbit
// demo.mbt
/// 实战请求处理链路：begin_trace → 嵌套 enter_span/exit_span + 属性 / 事件 →
/// 采样 + 脱敏 → JSON / logfmt 渲染 → traceparent 注入。返回该链路产出工件。
pub(all) struct DemoOutcome {
  trace : TraceId
  json_lines : Array[String]
  logfmt_lines : Array[String]
  traceparent : String
  span_count : Int
} derive(Eq, Show)
pub fn run_demo() -> DemoOutcome

/// 模拟下游进程：从 traceparent 提取上下文并在其下记录，返回下游事件的 trace-id。
pub fn run_downstream(traceparent : String) -> TraceId?
```

`run_demo` 串联全部能力（R11.1 / R11.2）：开启 trace、嵌套 span 与 OTel 属性 / 事件标注、对事件流采样、对敏感字段脱敏、以 JSON 与 logfmt 双格式渲染、注入 `traceparent`；`run_downstream` 在模拟下游进程提取 `traceparent` 并继续记录，使下游事件与父进程归属同一 trace-id（R11.3）。`README.mbt.md` 以该 demo 演示端到端流程，全部示例经 `moon test *.mbt.md` 验证（R11.4 / R13.4）。

### 4.11 性能基准设计（Requirement 9）

`benches/logging_bench/` 覆盖四类工作负载（R9.1）：① **高频 `log`**（大批量事件发射 + 级别过滤）；② **格式化**（JSON 与 logfmt 渲染于不同字段规模 / 嵌套深度）；③ **采样判定**（`sample_trace` / `sample_stream` 于大事件流）；④ **span 进入 / 退出**（深 / 宽 span 树）。输出含机器标识、后端目标、输入规模与计时统计的 JSON / Markdown 工件（R9.2），写入 `benches/results/`；新运行与基线中位数比较、超声明容差给可审计回归报告（R9.3，复用既有 guard 模式）。文档记录可复现运行命令（R9.4），并要求 native 后端先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

## 数据模型（Data Models）

新增 / 扩展类型一览（既有 `Level`/`Event`/`Span`/`SpanId`/`TraceId`/`TraceContext` 结构不变）：

| 类型 | 文件 | 说明 |
|---|---|---|
| `Value`（扩展） | `types.mbt` | 追加 `VMap(Map[String,Value])` / `VList(Array[Value])` 嵌套变体（加性，标量变体不变） |
| `Formatter` / `Sink` | `formatter.mbt` | 格式器种类 / 可插拔内存 sink（formatter + 路由谓词 + 缓冲） |
| `EnvFilter` / `FilterError` | `filter.mbt` | 分 target 阈值表 + 兜底；解析错误（含偏移定位） |
| `SamplingConfig` / `RateLimiter` | `sampling.mbt` | 采样率配置 / 逻辑时间窗限流器 |
| `SpanStatus` / `SpanKind` / `SpanEvent` / `SpanData` | `otel_span.mbt` | OTel 语义（状态 / 类别 / 事件 / 包裹），叠加既有 `Span` |
| `W3CContext` | `trace_context.mbt` | traceparent 三分量（hex trace-id / span-id + flags） |
| `RedactionPolicy` | `redaction.mbt` | 敏感字段名集合 + 谓词 |
| `Histogram` | `metrics.mbt` | 边界 + 桶计数 |
| `DemoOutcome` | `demo.mbt` | 端到端 demo 产出工件 |

**`Value` 扩展的兼容性论证**：MoonBit 枚举变体必须在单一声明处给出，故 `VMap`/`VList` 无法以「旁路新类型」提供，只能就地追加到 `Value`。该变更为**纯加性**：既有四个标量变体的名称、载荷与 `derive(Eq, Show)` 语义不变；既有对 `Value` 的匹配（仅 `value_to_json`/`jval_to_value` 两处私有助手）追加 `VMap`/`VList` 臂以恢复穷尽性，标量臂逐字保留。因此 `format_json`/`parse_json_log` 对仅含标量字段事件的输出与解析逐字节不变（R1.5 / R12.4），既有 JSON 往返性质（R12.7）继续成立。**发布元数据**：版本自 `0.1.0` 起按旗舰深化做次 / 主版本推进（R13.6），`release_info` / `release_info_with_gates` 语义不变，仅版本字符串与 `CHANGELOG.md` 更新。

---

## 错误处理（Error Handling）

- **既有 JSON 解析（冻结公开签名）**：`parse_json_log` 继续返回 `Event?`，任意结构不符（缺字段、类型不符、语法错误、顶层对象后有多余字符）一律 `None`，绝不产部分构造事件；嵌套扩展沿用同一「全有或全无」纪律（R13.3）。
- **logfmt 解析错误**：`parse_logfmt` 返回 `Event?`，键值结构非法 / 引号未闭合 / 级别标签不可识别返回 `None`（不产部分事件）。
- **EnvFilter 指令错误**：`parse_env_filter` 返回 `Result[EnvFilter, FilterError]`，任一项非法返回 `Err(FilterError{pos, message})` 且不登记任何阈值（R4.4 / R13.3）。
- **traceparent 提取错误**：`extract_traceparent` 返回 `W3CContext?`，字段数 / 分隔符 / 分量长度 / hex 字符不符规范返回 `None`，不产部分上下文（R6.4 / R13.3）。
- **无部分产物契约**：全部解析 / 提取一律「先完整校验后构造」——失败返回 `None`/`Err` 而非部分产物，与既有 `parse_json_log` 一致（R13.3）。

---

## 算法说明与 paper-to-code 可追溯（Requirement 10）

| 算法 / 规范 | 来源 | 本库落点 |
|---|---|---|
| span 树 + 上下文传播模型 | Google Dapper（Sigelman 等，2010） | 既有 `enter_span`/`exit_span`/`with_context` + `otel_span.mbt` 叠加（R10.1） |
| span 属性 / 事件 / 状态 / kind 语义 | OpenTelemetry 规范（Tracing / SpanKind / Status） | `otel_span.mbt`：`SpanData`/`SpanEvent`/`SpanStatus`/`SpanKind`（R10.2） |
| traceparent 格式与字段语义 | W3C Trace Context 规范 | `trace_context.mbt`：`inject_traceparent`/`extract_traceparent`（R10.3） |
| logfmt 文本表示 | 结构化日志 / logfmt 约定（Heroku / go-kit） | `logfmt.mbt`：`format_logfmt`/`parse_logfmt`（R10.4） |
| EnvFilter 分 target 级别控制 | Rust `tracing-subscriber` EnvFilter | `filter.mbt`：`parse_env_filter`/`threshold_for`（R4 / R10.5） |
| 确定性 / 系统采样 + trace 内一致采样 | 采样理论（systematic sampling）+ Dapper 一致采样 | `sampling.mbt`：`sample_stream`/`sample_trace`（R3） |
| 直方图分桶聚合 | 直方图 / 度量聚合 | `metrics.mbt`：`histogram`/`count_by_level`（R8） |

各新增文件头部以注释标注其对应规范与本设计章节（沿用既有 `logging.mbt`/`types.mbt` 注释风格），实现 paper-to-code 可追溯（R10.1–10.4）。

---

## 三后端一致性与可移植性（Requirement 13.1 / 13.5）

- **纯整型 / 字符串运算**：采样混合函数 `mix`、hex 编解码、`cache`/`key` 类计算全程以确定性整型与字符串运算实现（不依赖平台整型宽度、不依赖哈希表迭代顺序），`wasm-gc`/`js`/`native` 三后端逐位一致。
- **Map 序列化的确定性**：`format_json`（既有）与 `format_logfmt`、`VMap` 渲染均对键**显式升序排序**后输出，规避三后端 `Map` 迭代顺序差异，保证文本确定、往返稳定。
- **指标用定长数组**：`count_by_level` 用长度 5 的数组（下标 = `Level::rank`）而非 `Map[Level,_]`，规避 Map 顺序差异（R8 确定性）。
- **确定性随机源**：采样复用 `@infra_pbt` 种子驱动 `Rng`（`rng_new(seed)`），保证三后端逐位一致、可重放；任一后端输出分歧即判构建失败（R13.1）。
- **Int64 语义一致**：span/trace 标识、时间戳为 `Int64`，三后端语义一致；traceparent 的 128↔64 编码以纯位运算实现。
- **native 前置**：文档与脚本要求 native 后端运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R9.4 / R13.5）。
- **门禁聚合**：三后端测试、属性测试、可执行文档任一未过，`release_info_with_gates` 经 `@release_meta` 聚合阻止本方向进入 release-ready（R13.7）。

---

## 设计权衡与开源对标（Requirement 10.5 / 10.6）

| 维度 | 本库 | Rust `tracing` | `slog` | Uber `zap` | OpenTelemetry SDK |
|---|---|---|---|---|---|
| 结构化字段 | `Value`（标量 + 嵌套 VMap/VList） | `Value`（typed fields） | `Key-Value` serializer | 强类型 `Field` | `Attributes`（有限类型 + 数组） |
| span / scope 模型 | 既有 span 树 + OTel 语义叠加 | `Span`/`Subscriber` | 无原生 span（logger 层级） | 无原生 span | `Span`/`Tracer`/`Context` |
| 采样 | 确定性系统采样 + trace 内一致 | 由 subscriber 自定义 | 由 Drain 自定义 | sampler core | `Sampler`（TraceIdRatioBased 等） |
| 上下文传播 | 显式捕获 + `with_context`；W3C traceparent | task-local + `Span` | logger 传递 | logger 传递 | `Context` + W3C Propagator |
| 导出 | 内存 sink（模型层） | 多 subscriber / layer | 多 Drain | 多 Core / WriteSyncer | 多 Exporter（OTLP 等） |
| 格式 | JSON / logfmt / pretty + 解析往返 | fmt / json layer | json / logfmt | json / console | OTLP / 自定义 |

**核心取舍**：与 OpenTelemetry SDK 同侧——**以可形式化验证的纯模型层（确定性采样 / 往返编解码 / 不变量可证）换取三后端一致性与可审计性**，而非 `tracing`/`zap` 的「面向真实 IO 与运行时的高性能导出管线」。同时吸收 `tracing` 的 EnvFilter 分模块控制、`slog`/`zap` 的多格式器与结构化字段表达力。

**实现边界声明（R10.6，显式而非隐式留白）**：
- **不接真实网络 / 文件导出**：sink 以内存缓冲（`Sink.buffer`）建模，不做真实 IO；多 sink / 路由 / 多格式在内存模型内完整可测。
- **不耦合 `moonbitlang/async`**：跨任务 trace 传播以既有「显式上下文捕获 + `with_context`」模型替代异步任务局部存储，行为不变量（子任务保留父 trace 标识）与真实异步运行时一致。
- **不接真实墙钟**：时间戳以既有单调逻辑时钟建模，保证三后端对同一调用序列产逐位一致时间戳。
- **traceparent 128↔64 映射**：内部 64 位标识编码进 traceparent 的 128 位 trace-id 低位（高位补 0），inject/extract 对内部标识无损往返，但不承载完整 128 位外部 trace-id 语义。
- 以上边界在 `README.mbt.md` 与本文档显式声明（R10.6）。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 |
|---|---|
| R1 嵌套取值与嵌套 JSON 往返 | 4.1 `Value` 扩展 + `value_to_json`/`jval_to_value` 嵌套臂 |
| R2 多 sink 与多 formatter | 4.2 `Formatter`/`Sink`/`dispatch` + 4.3 logfmt |
| R3 采样与限流 | 4.4 `sample_trace`/`sample_stream`/`RateLimiter` |
| R4 过滤与路由 | 4.5 `EnvFilter`/`field_filter`/`route` |
| R5 OTel span 语义 | 4.6 `SpanData`/`SpanEvent`/`SpanStatus`/`SpanKind` |
| R6 W3C Trace Context | 4.7 `inject_traceparent`/`extract_traceparent`/`W3CContext` |
| R7 脱敏 / PII | 4.8 `RedactionPolicy`/`redact`/`redaction_mask` |
| R8 指标派生 | 4.9 `count_by_level`/`histogram` |
| R9 性能基准 | 4.11 `benches/logging_bench` |
| R10 可解释性 / 对标 | 「算法说明」「设计权衡与开源对标」 |
| R11 端到端 demo | 4.10 `run_demo`/`run_downstream` + README |
| R12 向后兼容 | 「设计原则与兼容契约」「数据模型」`Value` 扩展论证 |
| R13 质量门禁 | 「三后端一致性」+ 测试策略 + 正确性属性 |

---

## 测试策略（Testing Strategy）

**双轨测试**：单元测试锁定具体见证与边界 / 错误条件；属性测试以 `@infra_pbt` 覆盖通用不变量（每条 ≥100 迭代，R13.2）。

- **单元测试（示例 / 边界 / 错误）**：
  - 嵌套取值具体样例（多层 `VMap`/`VList` 的 JSON 渲染与解析）、标量行为回归（仅含标量字段事件输出与 `0.1.0` 逐字节一致，R1.5 / R12.4）；
  - logfmt 引号 / 转义边界（含空格 / 等号 / 控制字符的值，R2.3）、多 sink 多格式交付（R2.5）；
  - 采样边界（rate=0 全弃 / rate=1 全采，R3.2）、限流窗口配额（R3.5）；
  - EnvFilter 非法指令位置（缺 `=`、级别标签不可识别，R4.4）、字段谓词与路由匹配 / 无匹配（R4.2 / R4.5）；
  - span 属性 / 事件 / 状态 / kind 设置与默认值（R5.1–5.4）；
  - traceparent 非法提取（字段数 / 长度 / hex 不符返回 None，R6.4）、sampled 位（R6.3）、桥接 `to_trace_context` 后 `with_context` 续记（R6.5）；
  - 脱敏嵌套整体掩码与键集合不变（R7.3 / R7.4）；
  - 直方图跳过缺字段 / 非数值事件（R8.3）；
  - 端到端 demo 流程（嵌套 span / 采样 / 脱敏 / 多格式 / 跨进程 traceparent，R11.2 / R11.3）；
  - 既有 API 回归（`log`/`enter_span`/`with_context`/`format_json` 行为不变，R12.1 / R12.2）、`release_info` 稳定与门禁真值表（R12.6 / R13.7）。
- **属性测试**：见下 §「正确性属性」P1–P14，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`；生成器涵盖随机嵌套 `Value`（含深度上界）、随机 `Event`、随机采样率与事件流、随机 EnvFilter 指令集、随机 span 进出序列、随机合法 `TraceContext`、随机敏感字段集与事件、随机边界集。往返类属性以 `round_trip`（经 `String`→`Bytes` 适配编解码）或 `holds_for_all` 配合 `Eq` 比较实现。
- **基准与冒烟**：`benches/logging_bench` 四类负载（R9.1）、工件产出（R9.2）、guard 回归（R9.3）；`README.mbt.md` 经 `moon test *.mbt.md`（R11.4 / R13.4）。
- **三后端**：同一套件在 `wasm-gc`/`js`/`native` 运行，分歧判失败（R13.1）；native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R13.5）。
- **属性测试标注**：统一 `Feature: logging, Property {n}: {text}`，并以 `**Validates: Requirements X.Y**` 链接验收标准。


---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有合法执行下应恒成立行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。下列属性均以全称量化表述，并复用 `@infra_pbt` 的 `holds_for_all`/`round_trip`（每条 ≥100 迭代）。*

### Property 1：嵌套 JSON 往返（nested JSON round-trip）

*对任意*由生成器产出的、含任意嵌套深度取值（`VMap`/`VList` 任意层级嵌套标量与复合取值）的事件 `e`，先以 JSON 格式化再以 JSON 解析应得到与原事件逐字段相等的事件：`parse_json_log(format_json(e)) == Some(e)`。该属性统摄 `VMap`→对象 / `VList`→数组的渲染与还原、对象成员升序稳定排序与任意层级嵌套的结构保真性（解析器易错，强制 round-trip 验证）。

**Validates: Requirements 1.2, 1.3, 1.4, 1.6**

### Property 2：既有标量 JSON 往返（legacy scalar JSON round-trip）

*对任意*由生成器产出的、仅含标量字段（`VStr`/`VInt`/`VBool`/`VFloat`）的事件 `e`，`parse_json_log(format_json(e))` 得到与 `e` 相等的事件，且 `format_json` 对该类事件的输出与 `0.1.0` 逐字节一致（向后兼容契约）。

**Validates: Requirements 1.5, 12.4, 12.7**

### Property 3：logfmt 往返（logfmt round-trip）

*对任意*由生成器产出的、仅含标量字段的事件 `e`，先以 logfmt 格式化再以 logfmt 解析应得到与原事件逐字段相等的事件：`parse_logfmt(format_logfmt(e)) == Some(e)`。该属性统摄 `key=value` 空格分隔结构、含特殊字符取值的引号与转义编解码的保真性。

**Validates: Requirements 2.3, 2.6, 2.7**

### Property 4：格式器确定性（formatter determinism）

*对任意*由生成器产出的事件 `e` 与任一格式器 `fmt ∈ {Json, Logfmt, Pretty}`，两次渲染产出逐字节相同的文本：`format_event(fmt, e) == format_event(fmt, e)`，即渲染结果由事件内容唯一确定（三后端逐字节一致）。

**Validates: Requirements 2.2**

### Property 5：trace 内采样一致性（trace-coherent sampling）

*对任意*由生成器产出的采样率、种子与归属同一 trace 的事件集合，该 trace 的全部事件采样判定相同——要么全部被采样、要么全部被丢弃：对同一 `trace`，`sample_trace(rate, trace, seed)` 为常量。

**Validates: Requirements 3.3, 3.6**

### Property 6：采样比例有界（sampling-ratio bound）

*对任意*由生成器产出的采样率 `rate ∈ [0.0, 1.0]` 与事件流 `events`，系统采样后被保留事件占比不超过采样率所允许的上界：`len(sample_stream(rate, events, rng)) <= retained_count(rate, len(events))` 且 `retained_count(rate, n) <= ceil(rate * n)`；边界上 `rate=0.0` 保留 0 条、`rate=1.0` 保留全部。

**Validates: Requirements 3.1, 3.2, 3.7**

### Property 7：采样确定性与可重放（sampling determinism）

*对任意*由生成器产出的采样率、种子与事件流，以相同采样配置与相同 `Rng` 种子两次重放同一序列，产出逐条相同的采样判定结果（保留 / 丢弃序列逐元素相等）。

**Validates: Requirements 3.1, 3.4**

### Property 8：限流配额上界（rate-limit quota bound）

*对任意*由生成器产出的窗口大小、配额 `limit` 与（key, 逻辑时间戳）事件序列，限流器在任一逻辑时间窗内对同一 key 放行的事件条数不超过 `limit`，超额事件被丢弃。

**Validates: Requirements 3.5**

### Property 9：过滤判定一致性（filter-decision consistency）

*对任意*由生成器产出的 EnvFilter 指令集与事件，事件被保留当且仅当其级别不低于其 target 的有效阈值：`EnvFilter::allows(f, e) ⟺ e.level.rank() >= f.threshold_for(target_of(e)).rank()`；且对任意字段谓词与事件，`field_filter(pred, e) ⟺ pred(e.fields)`。

**Validates: Requirements 4.1, 4.2, 4.6**

### Property 10：span 树父子不变量与时长非负（span-tree invariant）

*对任意*由生成器产出的 `enter_span`/`exit_span` 进入 / 退出序列，每个非根 span 的父标识等于其进入时刻的激活 span 标识，且每个已结束 span 的时长非负（`span_duration(s) == Some(d)` 蕴含 `d >= 0`）。该属性同时固化 OTel 语义旁路叠加后既有 span 树构建与时长计算行为不变。

**Validates: Requirements 5.5, 5.6**

### Property 11：traceparent 注入 / 提取往返（traceparent inject/extract round-trip）

*对任意*由生成器产出的合法 `TraceContext` `ctx`，注入为 traceparent 文本再提取，所得 trace-id、span-id 与 flags 与原上下文相等：`extract_traceparent(inject_traceparent(ctx))` 为 `Some(w)`，且 `w` 的三分量与 `ctx` 的标识及采样标志一致；注入文本满足 `00-<32hex>-<16hex>-<2hex>` 形态。

**Validates: Requirements 6.1, 6.2, 6.6**

### Property 12：脱敏完整性（redaction-completeness）

*对任意*由生成器产出的（敏感字段集 / 谓词, 事件）对，脱敏后输出满足：每个被判定为敏感的字段取值等于固定掩码标记（即使原值为嵌套 `VMap`/`VList` 也整体替换，内部无任何原始取值片段残留），且脱敏后字段键集合与脱敏前逐一致、非敏感字段取值不变。

**Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**

### Property 13：计数守恒（counter-conservation）

*对任意*由生成器产出的事件流，按级别派生的各级别计数均为非负，且各级别计数之和等于输入事件总数：`sum(count_by_level(events)) == len(events)`。

**Validates: Requirements 8.1, 8.4**

### Property 14：指标派生确定性（metrics-determinism）

*对任意*由生成器产出的事件流与边界集，对同一输入两次派生所得按级别计数与直方图逐桶相等；且直方图仅计入该字段为数值取值（`VInt`/`VFloat`）的事件，跳过缺字段或字段非数值的事件（被跳过事件不计入任何桶）。

**Validates: Requirements 8.2, 8.3, 8.5**
