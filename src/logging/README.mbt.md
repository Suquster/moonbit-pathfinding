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
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`assert_*` 断言不符，`moon test` 会立即报错——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
