// logging.mbt —— Logging_Library 高层接口实现（任务 10.2）。
//
// 本文件在 10.1 骨架之上落地 design.md 锁定的五个高层接口的**完整语义**：
//   log / enter_span / exit_span / format_json / parse_json_log
//
// 覆盖的验收标准（Requirement 7）：
//   * 7.1 —— log 输出含时间戳、级别与全部结构化字段的事件记录；
//   * 7.2 —— log 丢弃级别低于配置阈值的事件；
//   * 7.3 —— enter_span 将新 span 与其父 span 关联，形成 span 树；
//   * 7.4 —— span 激活期间产生的事件被标注该 span 的上下文标识（span / trace）；
//   * 7.5 —— exit_span 记录该 span 的持续时长（end - start）；
//   * 7.6 —— 跨异步任务边界传播 trace 上下文：子任务保留父任务的 trace 标识；
//   * 7.7 —— format_json 产出可被 parse_json_log 解析的结构化输出（往返）。
//
// 关于「跨异步任务边界」的实现策略（重要）：
//   design.md（R7）声明本方向依赖 `moonbitlang/async` 承载跨异步任务的 trace
//   上下文传播。但当前构建环境尚未在 `moon.mod` 登记该依赖，且引入存在三后端
//   覆盖不一致、阻塞「三后端 moon test 全绿」质量门禁的风险。
//
//   因此本任务沿用 10.1 的本地 `TraceId` 抽象，实现一个**可测的上下文传播
//   模型**：以「显式上下文捕获 + 任务局部存储（task-local storage）模拟」表达
//   异步任务边界——`capture_context` 快照当前 trace / span，`child_context`
//   派生保留父 trace 标识的子上下文，`with_context` 在该上下文下运行一段子任务
//   工作并于结束后恢复父任务状态。其行为不变量（子任务保留父 trace 标识、
//   span 仍正确挂接父 span）与真实异步运行时一致；待 `moonbitlang/async` 稳定
//   登记后，可将 `with_context` 内部替换为基于异步任务局部存储的真实载体，而
//   对外契约（本文件公开 API 与不变量）保持不变。

// ───────────────────────────── 环境状态 ──────────────────────────────────

///|
/// 进程内日志运行时（ambient logger）的可变状态。
///
/// 以单一进程级状态承载：级别阈值、单调逻辑时钟、span / trace 标识分配源、
/// 激活 span 栈、当前 trace 上下文、跨任务继承的父 span，以及已发射事件与
/// 已结束 span 的记录（供 sink / 测试观测）。所有字段为 `mut`，绑定 `logger`
/// 本身不可重新赋值，符合「单一可变运行时 + 纯函数操作」的最小模型。
struct Logger {
  mut threshold : Level
  mut clock : Int64
  mut span_id_source : Int64
  mut trace_id_source : Int64
  mut active : Array[Span]
  mut current_trace : TraceId
  mut inherited_parent : SpanId?
  mut events : Array[Event]
  mut finished : Array[Span]
}

///|
/// 进程级日志运行时单例。默认阈值为 `Trace`（不过滤），逻辑时钟从 0 起。
let logger : Logger = {
  threshold: Trace,
  clock: 0L,
  span_id_source: 0L,
  trace_id_source: 0L,
  active: [],
  current_trace: { value: 0L },
  inherited_parent: None,
  events: [],
  finished: [],
}

///|
/// 标注事件所属 span 的保留字段键（Requirement 7.4）。
let span_field : String = "span"

///|
/// 标注事件所属 trace 上下文的保留字段键（Requirement 7.4 / 7.6）。
let trace_field : String = "trace"

///|
/// 推进逻辑时钟一格并返回新值（单调递增的时间戳源）。
///
/// 不依赖真实墙钟，保证三后端（wasm-gc / js / native）对同一调用序列产生
/// 逐位一致的时间戳，契合 design 的确定性要求。
fn tick() -> Int64 {
  logger.clock = logger.clock + 1L
  logger.clock
}

///|
/// 分配一个进程内唯一、单调递增的 span id。
fn alloc_span_id() -> SpanId {
  logger.span_id_source = logger.span_id_source + 1L
  { value: logger.span_id_source }
}

///|
/// 分配一个进程内唯一、单调递增的 trace id。
fn alloc_trace_id() -> TraceId {
  logger.trace_id_source = logger.trace_id_source + 1L
  { value: logger.trace_id_source }
}

// ───────────────────────────── 配置与观测 ─────────────────────────────────

///|
/// 配置最低日志级别阈值（Requirement 7.2）。低于该级别的事件将被 `log` 丢弃。
pub fn set_threshold(level : Level) -> Unit {
  logger.threshold = level
}

///|
/// 返回当前配置的级别阈值。
pub fn current_threshold() -> Level {
  logger.threshold
}

///|
/// 将日志运行时重置为初始状态（阈值 Trace、时钟与标识源归零、清空栈与记录）。
///
/// 主要供测试在用例之间隔离全局状态；也可用于在一次逻辑会话开始前清场。
pub fn reset_logger() -> Unit {
  logger.threshold = Trace
  logger.clock = 0L
  logger.span_id_source = 0L
  logger.trace_id_source = 0L
  logger.active = []
  logger.current_trace = { value: 0L }
  logger.inherited_parent = None
  logger.events = []
  logger.finished = []
}

///|
/// 返回迄今已发射（未被阈值过滤）的全部事件，按发射顺序排列。
pub fn captured_events() -> Array[Event] {
  logger.events
}

///|
/// 返回迄今已结束（`exit_span` 后 `end` 已填充）的全部 span。
pub fn finished_spans() -> Array[Span] {
  logger.finished
}

///|
/// 返回一个 span 的持续时长（end - start）；尚未结束（end 为 None）则返回 None。
///
/// 对应 Requirement 7.5：`exit_span` 后该 span 的时长可由此纯函数计算。
pub fn span_duration(s : Span) -> Int64? {
  match s.end {
    Some(e) => Some(e - s.start)
    None => None
  }
}

///|
/// 返回当前激活 span 的标识：栈顶激活 span；若无激活 span，则回退到跨任务
/// 继承的父 span（见 `with_context`）。无任何上下文时为 None。
pub fn current_span() -> SpanId? {
  let n = logger.active.length()
  if n > 0 {
    Some(logger.active[n - 1].id)
  } else {
    logger.inherited_parent
  }
}

///|
/// 返回当前 trace 上下文标识。
pub fn current_trace() -> TraceId {
  logger.current_trace
}

// ───────────────────────────── 核心接口 ──────────────────────────────────

///|
/// 记录一条带键值字段的日志事件（Requirement 7.1 / 7.2 / 7.4）。
///
/// 行为：
///   1. 级别过滤（7.2）：当 `level` 低于当前阈值时，直接丢弃，不产生任何记录；
///   2. 时间戳（7.1）：以单调逻辑时钟推进得到事件时间戳；
///   3. 上下文标注（7.4）：若存在激活 span，则在事件字段中注入保留键
///      `span`（当前 span id）；并始终注入 `trace`（当前 trace id），从而使
///      span 内事件可被关联到 span 树与 trace 链路；
///   4. 事件含调用方提供的全部结构化字段（7.1），原字段优先级高于保留键。
pub fn log(level : Level, fields : Map[String, Value]) -> Unit {
  // Requirement 7.2：低于阈值的事件被丢弃。
  if not(level.is_enabled(logger.threshold)) {
    return
  }
  let ts = tick()
  // 复制调用方字段，避免就地修改其入参 Map。
  let merged : Map[String, Value] = Map::new()
  // 先写入上下文保留键，再写入调用方字段——调用方显式字段优先（覆盖保留键）。
  merged[trace_field] = VInt(logger.current_trace.value)
  match current_span() {
    Some(id) => merged[span_field] = VInt(id.value)
    None => ()
  }
  fields.each(fn(k, v) { merged[k] = v })
  logger.events.push(Event::new(ts, level, merged))
}

///|
/// 进入一个 span，返回其句柄（Requirement 7.3）。
///
/// 新 span 的父 span 取自当前激活上下文（`current_span`）：在已激活 span 内
/// 进入子 span 时自动挂接为其子节点，从而形成 span 树；无激活上下文时为根
/// span（`parent = None`）。`start` 取自单调逻辑时钟；`end` 初始为 None，待
/// `exit_span` 填充。`name` 在 design 的 `Span` 类型中无对应字段，此处不存储。
pub fn enter_span(name : String) -> Span {
  ignore(name)
  let parent = current_span()
  let span : Span = { id: alloc_span_id(), parent, start: tick(), end: None }
  logger.active.push(span)
  span
}

///|
/// 结束一个 span 并记录其持续时长（Requirement 7.5）。
///
/// 以单调逻辑时钟取得结束时间戳，从激活栈中移除该 span（按 id 匹配，容忍非
/// 严格 LIFO 的退出顺序），将填充了 `end` 的 span 追加到已结束记录。结束后
/// 其时长可由 `span_duration` 计算（end - start）。
pub fn exit_span(s : Span) -> Unit {
  let end_ts = tick()
  // 从激活栈中按 id 移除（自栈顶向下查找首个匹配，兼容嵌套与提前退出）。
  let mut idx = logger.active.length() - 1
  let mut found = -1
  while idx >= 0 {
    if logger.active[idx].id == s.id {
      found = idx
      break
    }
    idx = idx - 1
  }
  if found >= 0 {
    logger.active.remove(found) |> ignore
  }
  let finished_span : Span = {
    id: s.id,
    parent: s.parent,
    start: s.start,
    end: Some(end_ts),
  }
  logger.finished.push(finished_span)
}

// ─────────────────────── 跨异步任务 trace 传播 ────────────────────────────

///|
/// trace 上下文快照（trace context snapshot）。
///
/// 承载一次「跨任务边界传播」所需的最小上下文：当前 trace 标识与当前激活
/// span。用于模拟异步任务局部存储（task-local storage）的捕获与还原。
pub(all) struct TraceContext {
  trace : TraceId
  span : SpanId?
} derive(Eq, Show)

///|
/// 开启一条新的 trace（逻辑请求/任务链路），将其设为当前上下文并返回其标识。
///
/// 后续在该 trace 下 `log` 的事件将被标注此 trace 标识（Requirement 7.4）。
pub fn begin_trace() -> TraceId {
  let t = alloc_trace_id()
  logger.current_trace = t
  t
}

///|
/// 捕获当前 trace 上下文快照（当前 trace 标识 + 当前激活 span）。
///
/// 模拟在派生子任务前于父任务侧读取任务局部存储。
pub fn capture_context() -> TraceContext {
  { trace: logger.current_trace, span: current_span() }
}

///|
/// 由父上下文派生一个子任务上下文（Requirement 7.6）。
///
/// 关键不变量：子上下文**保留父任务的 trace 标识**（`child.trace == parent.trace`），
/// 并以父任务的激活 span 作为子任务的逻辑父 span，从而使跨任务边界产生的
/// 事件与 span 仍正确归属同一 trace 链路与 span 树。
pub fn child_context(parent : TraceContext) -> TraceContext {
  { trace: parent.trace, span: parent.span }
}

///|
/// 在给定 trace 上下文下运行一段子任务工作，结束后恢复父任务状态。
///
/// 模拟异步任务边界：进入子任务时安装传入上下文（保留父 trace 标识、以父
/// span 为继承父节点），子任务内的 `log` / `enter_span` 因此自动归属父 trace
/// 与 span 树；子任务自身的激活 span 栈独立，退出后父任务的 trace、激活栈与
/// 继承父节点被原样还原，互不串扰（Requirement 7.6）。
pub fn[T] with_context(ctx : TraceContext, work : () -> T) -> T {
  // 保存父任务状态。
  let saved_trace = logger.current_trace
  let saved_active = logger.active
  let saved_inherited = logger.inherited_parent
  // 安装子任务上下文：保留父 trace 标识；以父 span 为继承父节点；独立激活栈。
  logger.current_trace = ctx.trace
  logger.inherited_parent = ctx.span
  logger.active = []
  let result = work()
  // 还原父任务状态。
  logger.current_trace = saved_trace
  logger.active = saved_active
  logger.inherited_parent = saved_inherited
  result
}

// ─────────────────────────── 结构化输出 ──────────────────────────────────

///|
/// 将一条事件序列化为 JSON 结构化输出（Requirement 7.1 / 7.7）。
///
/// 产出形如
///   {"ts":<int>,"level":"INFO","fields":{"k":<value>,...}}
/// 的 JSON 文本。字段按键名升序稳定排序，确保同一事件在三后端产生逐字节
/// 一致的输出，并与 `parse_json_log` 构成「序列化再解析」往返闭环。
pub fn format_json(e : Event) -> String {
  // 收集字段为数组并按键名稳定排序（保证确定性输出）。
  let entries : Array[(String, Value)] = []
  e.fields.each(fn(k, v) { entries.push((k, v)) })
  sort_entries(entries)
  let body = @infra_text.TextBuilder::new()
  for i = 0; i < entries.length(); i = i + 1 {
    if i > 0 {
      body.push_str(",")
    }
    let (k, v) = entries[i]
    body.push_str("\"")
    body.push_str(json_escape(k))
    body.push_str("\":")
    body.push_str(value_to_json(v))
  }
  "{\"ts\":" +
  e.ts.to_string() +
  ",\"level\":\"" +
  e.level.label() +
  "\",\"fields\":{" +
  body.build() +
  "}}"
}

///|
/// 按键名升序对字段条目做插入排序（小规模、确定性、零外部 API 依赖）。
fn sort_entries(entries : Array[(String, Value)]) -> Unit {
  let n = entries.length()
  for i = 1; i < n; i = i + 1 {
    let cur = entries[i]
    let mut j = i - 1
    while j >= 0 && entries[j].0 > cur.0 {
      entries[j + 1] = entries[j]
      j = j - 1
    }
    entries[j + 1] = cur
  }
}

///|
/// 将一个结构化字段取值渲染为 JSON 片段。
///
/// 标量臂（`VStr` / `VInt` / `VBool` / `VFloat`）逐字保留既有渲染语义，确保
/// 仅含标量字段事件的输出与 `0.1.0` 逐字节一致（Requirement 1.5 / 12.4）。
/// 旗舰深化加性追加两条嵌套臂（Requirement 1.3）：
///   * `VMap(m)`  —— 渲染为 JSON 对象 `{...}`，成员**按键名升序稳定排序**后
///     以 `"key":value` 递归渲染（保证三后端逐字节一致与往返稳定）；
///   * `VList(xs)` —— 渲染为 JSON 数组 `[...]`，元素**按原序**递归渲染。
fn value_to_json(v : Value) -> String {
  match v {
    VStr(s) => "\"" + json_escape(s) + "\""
    VInt(i) => i.to_string()
    VBool(b) => if b { "true" } else { "false" }
    VFloat(f) => f.to_string()
    VMap(m) => {
      // 成员按键名升序稳定排序（与顶层 fields 同一规则），保证确定性输出。
      let entries : Array[(String, Value)] = []
      m.each(fn(k, vv) { entries.push((k, vv)) })
      sort_entries(entries)
      let body = @infra_text.TextBuilder::new()
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          body.push_str(",")
        }
        let (k, vv) = entries[i]
        body.push_str("\"")
        body.push_str(json_escape(k))
        body.push_str("\":")
        body.push_str(value_to_json(vv))
      }
      "{" + body.build() + "}"
    }
    VList(xs) => {
      let body = @infra_text.TextBuilder::new()
      for i = 0; i < xs.length(); i = i + 1 {
        if i > 0 {
          body.push_str(",")
        }
        body.push_str(value_to_json(xs[i]))
      }
      "[" + body.build() + "]"
    }
  }
}

///|
/// JSON 字符串转义：处理双引号、反斜杠、常见控制字符（\n \r \t \b \f），
/// 其余 < 0x20 的控制字符转义为 \u00XX。其余字符原样输出。
fn json_escape(s : String) -> String {
  let out = @infra_text.TextBuilder::new()
  for c in s {
    let code = c.to_int()
    out.push_str(
      match c {
        '"' => "\\\""
        '\\' => "\\\\"
        '\n' => "\\n"
        '\r' => "\\r"
        '\t' => "\\t"
        _ =>
          if code == 0x08 {
            "\\b"
          } else if code == 0x0C {
            "\\f"
          } else if code < 0x20 {
            "\\u" + hex4(code)
          } else {
            c.to_string()
          }
      },
    )
  }
  out.build()
}

///|
/// 将一个 0..=15 的半字节渲染为 1 位小写十六进制字符。
fn hex_digit(nibble : Int) -> String {
  let d = nibble & 0xF
  let ch = if d < 10 {
    ('0'.to_int() + d).unsafe_to_char()
  } else {
    ('a'.to_int() + (d - 10)).unsafe_to_char()
  }
  ch.to_string()
}

///|
/// 将一个 0..=0xFFFF 的整数渲染为 4 位小写十六进制（用于 \uXXXX 转义）。
fn hex4(n : Int) -> String {
  hex_digit(n >> 12) + hex_digit(n >> 8) + hex_digit(n >> 4) + hex_digit(n)
}

// ─────────────────────────── 结构化解析 ──────────────────────────────────

///|
/// 解析阶段的中间 JSON 取值表示（仅覆盖本库结构化日志所需的子集）。
///
/// 旗舰深化加性追加 `JArr`（JSON 数组），并使 `JObj` 在字段取值域内可还原为
/// 嵌套 `VMap`（Requirement 1.4）。
enum JVal {
  JStr(String)
  JNum(String)
  JBool(Bool)
  JObj(Array[(String, JVal)])
  JArr(Array[JVal])
}

///|
/// 极简 JSON 读取器：以字符数组 + 游标的形式做递归下降解析。
struct JsonReader {
  chars : Array[Char]
  mut pos : Int
}

///|
/// 从一行结构化 JSON 日志解析回事件（Requirement 7.7）。
///
/// 与 `format_json` 构成往返：解析顶层对象，提取 `ts`（整数时间戳）、`level`
/// （级别标签）与 `fields`（结构化字段对象）。任意结构不符（缺字段、类型
/// 不符、语法错误）一律返回 `None`，绝不产生部分构造的事件。
pub fn parse_json_log(s : String) -> Event? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let reader = { chars, pos: 0 }
  match parse_value(reader) {
    Some(JObj(pairs)) => {
      reader.skip_ws()
      // 顶层对象后不应有多余非空白字符。
      if reader.pos != reader.chars.length() {
        return None
      }
      build_event(pairs)
    }
    _ => None
  }
}

///|
/// 由顶层对象的键值对构造 `Event`；缺少必需键或类型不符则返回 None。
fn build_event(pairs : Array[(String, JVal)]) -> Event? {
  let mut ts_val : Int64? = None
  let mut level_val : Level? = None
  let mut fields_val : Map[String, Value]? = None
  for i = 0; i < pairs.length(); i = i + 1 {
    let (k, v) = pairs[i]
    if k == "ts" {
      match v {
        JNum(num) =>
          match parse_int64(num) {
            Some(n) => ts_val = Some(n)
            None => return None
          }
        _ => return None
      }
    } else if k == "level" {
      match v {
        JStr(label) =>
          match Level::from_label(label) {
            Some(lv) => level_val = Some(lv)
            None => return None
          }
        _ => return None
      }
    } else if k == "fields" {
      match v {
        JObj(fpairs) =>
          match build_fields(fpairs) {
            Some(m) => fields_val = Some(m)
            None => return None
          }
        _ => return None
      }
    }
    // 未知顶层键被忽略（向前兼容）。
  }
  match (ts_val, level_val, fields_val) {
    (Some(ts), Some(level), Some(fields)) => Some(Event::new(ts, level, fields))
    _ => None
  }
}

///|
/// 将 `fields` 对象的键值对转换为 `Map[String, Value]`；类型不符则返回 None。
fn build_fields(fpairs : Array[(String, JVal)]) -> Map[String, Value]? {
  let m : Map[String, Value] = Map::new()
  for i = 0; i < fpairs.length(); i = i + 1 {
    let (k, v) = fpairs[i]
    match jval_to_value(v) {
      Some(value) => m[k] = value
      None => return None
    }
  }
  Some(m)
}

///|
/// 将中间 JSON 取值转换为结构化字段取值。
///
/// 标量臂逐字保留既有语义（Requirement 1.5）；旗舰深化加性追加（Requirement
/// 1.4）：`JObj` 还原为嵌套 `VMap`、`JArr` 还原为嵌套 `VList`，递归处理任意层级。
fn jval_to_value(v : JVal) -> Value? {
  match v {
    JStr(s) => Some(VStr(s))
    JBool(b) => Some(VBool(b))
    JNum(num) =>
      // 含小数点或指数视为浮点，否则视为整数（与 value_to_json 渲染对应）。
      if num_is_float(num) {
        match parse_double(num) {
          Some(f) => Some(VFloat(f))
          None => None
        }
      } else {
        match parse_int64(num) {
          Some(n) => Some(VInt(n))
          None => None
        }
      }
    JObj(pairs) => {
      // 嵌套对象 → VMap（Requirement 1.4），递归还原成员取值。
      let m : Map[String, Value] = Map::new()
      for i = 0; i < pairs.length(); i = i + 1 {
        let (k, jv) = pairs[i]
        match jval_to_value(jv) {
          Some(value) => m[k] = value
          None => return None
        }
      }
      Some(VMap(m))
    }
    JArr(items) => {
      // 嵌套数组 → VList（Requirement 1.4），按原序递归还原元素取值。
      let xs : Array[Value] = []
      for i = 0; i < items.length(); i = i + 1 {
        match jval_to_value(items[i]) {
          Some(value) => xs.push(value)
          None => return None
        }
      }
      Some(VList(xs))
    }
  }
}

///|
/// 判断数值字面量文本是否为浮点（含小数点或指数）。
fn num_is_float(s : String) -> Bool {
  for c in s {
    if c == '.' || c == 'e' || c == 'E' {
      return true
    }
  }
  false
}

///|
/// 解析 Int64（包装 @strconv，失败返回 None）。
fn parse_int64(s : String) -> Int64? {
  match (try? @strconv.parse_int64(s)) {
    Ok(n) => Some(n)
    Err(_) => None
  }
}

///|
/// 解析 Double（包装 @strconv，失败返回 None）。
fn parse_double(s : String) -> Double? {
  match (try? @strconv.parse_double(s)) {
    Ok(f) => Some(f)
    Err(_) => None
  }
}

// ─────────────────────── JSON 读取器原语 ──────────────────────────────────

///|
/// 跳过空白字符。
fn JsonReader::skip_ws(self : JsonReader) -> Unit {
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
/// 查看当前字符（不前进）。
fn JsonReader::peek(self : JsonReader) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
/// 解析一个 JSON 取值（对象 / 数组 / 字符串 / 数值 / 布尔）。
fn parse_value(r : JsonReader) -> JVal? {
  r.skip_ws()
  match r.peek() {
    Some('{') => parse_object(r)
    Some('[') => parse_array(r)
    Some('"') =>
      match parse_string(r) {
        Some(s) => Some(JStr(s))
        None => None
      }
    Some('t') => parse_keyword(r, "true", JBool(true))
    Some('f') => parse_keyword(r, "false", JBool(false))
    Some(c) =>
      if c == '-' || (c >= '0' && c <= '9') {
        parse_num(r)
      } else {
        None
      }
    None => None
  }
}

///|
/// 解析一个 JSON 数组，返回有序元素数组（Requirement 1.4）。消费起止方括号。
fn parse_array(r : JsonReader) -> JVal? {
  // 已确认当前为 '['。
  r.pos = r.pos + 1
  let items : Array[JVal] = []
  r.skip_ws()
  if r.peek() == Some(']') {
    r.pos = r.pos + 1
    return Some(JArr(items))
  }
  while true {
    let value = match parse_value(r) {
      Some(v) => v
      None => return None
    }
    items.push(value)
    r.skip_ws()
    match r.peek() {
      Some(',') => {
        r.pos = r.pos + 1
        continue
      }
      Some(']') => {
        r.pos = r.pos + 1
        break
      }
      _ => return None
    }
  }
  Some(JArr(items))
}

///|
/// 解析一个 JSON 对象，返回有序键值对数组。
fn parse_object(r : JsonReader) -> JVal? {
  // 已确认当前为 '{'。
  r.pos = r.pos + 1
  let pairs : Array[(String, JVal)] = []
  r.skip_ws()
  if r.peek() == Some('}') {
    r.pos = r.pos + 1
    return Some(JObj(pairs))
  }
  while true {
    r.skip_ws()
    // 键必须为字符串。
    if r.peek() != Some('"') {
      return None
    }
    let key = match parse_string(r) {
      Some(k) => k
      None => return None
    }
    r.skip_ws()
    if r.peek() != Some(':') {
      return None
    }
    r.pos = r.pos + 1
    let value = match parse_value(r) {
      Some(v) => v
      None => return None
    }
    pairs.push((key, value))
    r.skip_ws()
    match r.peek() {
      Some(',') => {
        r.pos = r.pos + 1
        continue
      }
      Some('}') => {
        r.pos = r.pos + 1
        break
      }
      _ => return None
    }
  }
  Some(JObj(pairs))
}

///|
/// 解析一个 JSON 字符串（含转义还原），消费起止双引号。
fn parse_string(r : JsonReader) -> String? {
  // 已确认当前为 '"'。
  r.pos = r.pos + 1
  let out = @infra_text.TextBuilder::new()
  while r.pos < r.chars.length() {
    let c = r.chars[r.pos]
    r.pos = r.pos + 1
    if c == '"' {
      return Some(out.build())
    } else if c == '\\' {
      if r.pos >= r.chars.length() {
        return None
      }
      let esc = r.chars[r.pos]
      r.pos = r.pos + 1
      match esc {
        '"' => out.push_str("\"")
        '\\' => out.push_str("\\")
        '/' => out.push_str("/")
        'n' => out.push_str("\n")
        'r' => out.push_str("\r")
        't' => out.push_str("\t")
        'b' => out.push_str("\u{08}")
        'f' => out.push_str("\u{0C}")
        'u' => {
          if r.pos + 4 > r.chars.length() {
            return None
          }
          match parse_hex4(r) {
            Some(code) => out.push_str(code.unsafe_to_char().to_string())
            None => return None
          }
        }
        _ => return None
      }
    } else {
      out.push_char(c)
    }
  }
  // 未遇到收尾双引号。
  None
}

///|
/// 读取 4 位十六进制并返回其整数值（用于 \uXXXX 还原），消费这 4 个字符。
fn parse_hex4(r : JsonReader) -> Int? {
  let mut value = 0
  for i = 0; i < 4; i = i + 1 {
    let c = r.chars[r.pos]
    r.pos = r.pos + 1
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    value = value * 16 + d
  }
  Some(value)
}

///|
/// 解析一个 JSON 数值字面量（保留原始文本，由调用方按整数/浮点分类）。
fn parse_num(r : JsonReader) -> JVal? {
  let start = r.pos
  // 可选负号。
  if r.peek() == Some('-') {
    r.pos = r.pos + 1
  }
  let mut seen_digit = false
  while r.pos < r.chars.length() {
    let c = r.chars[r.pos]
    if c >= '0' && c <= '9' {
      seen_digit = true
      r.pos = r.pos + 1
    } else if c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-' {
      r.pos = r.pos + 1
    } else {
      break
    }
  }
  if not(seen_digit) {
    return None
  }
  let num = @infra_text.TextBuilder::new()
  for i = start; i < r.pos; i = i + 1 {
    num.push_char(r.chars[i])
  }
  Some(JNum(num.build()))
}

///|
/// 匹配一个字面关键字（true / false），命中则前进并返回对应取值。
fn parse_keyword(r : JsonReader, kw : String, value : JVal) -> JVal? {
  let kwchars : Array[Char] = []
  for c in kw {
    kwchars.push(c)
  }
  if r.pos + kwchars.length() > r.chars.length() {
    return None
  }
  for i = 0; i < kwchars.length(); i = i + 1 {
    if r.chars[r.pos + i] != kwchars[i] {
      return None
    }
  }
  r.pos = r.pos + kwchars.length()
  Some(value)
}
