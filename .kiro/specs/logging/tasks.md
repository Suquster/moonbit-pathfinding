# 实现计划（Implementation Plan）：Logging_Library 旗舰深化

## 概述（Overview）

本计划在已发布的 `logging 0.1.0` 骨架之上做**增量式、严格向后兼容**的旗舰级深化。实现顺序遵循 design 的依赖方向：**Value 嵌套扩展 + 嵌套 JSON → formatter/logfmt → 采样限流/过滤路由 → OTel span/traceparent → 脱敏/指标 → demo/基准/文档/发布**，并在阶段边界设置检查点。

向后兼容契约贯穿全程：
- 既有 `types.mbt`（`Level`/`Event`/`Span`/`SpanId`/`TraceId` 及其方法）与 `logging.mbt`/`release.mbt` 的**公开签名与运行时语义冻结**；
- `Value` 仅做**加性扩展**（追加 `VMap`/`VList`，既有四个标量变体逐字保留）；
- 私有 JSON 助手（`value_to_json`/`jval_to_value`/`parse_value`）**仅追加嵌套臂**，标量臂逐字保留，`format_json`/`parse_json_log` 对仅含标量字段事件的输出与解析逐字节不变；
- 全部新能力以**旁路新增** `.mbt` 文件 / 新增类型 / 新增函数提供。

测试约定：
- 每条正确性属性（Property 1~14）各自独立成 `*` 可选测试子任务，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`，**每条 ≥100 迭代**，标注统一前缀 `Feature: logging, Property {n}: {text}` 并以 `**Validates: Requirements X.Y**` 链接验收标准；
- 涉及 native 测试 / 基准 / 文档校验的任务，运行前先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

## 任务（Tasks）

- [x] 1. Value 嵌套取值加性扩展与嵌套助手
  - [x] 1.1 在 `types.mbt` 加性扩展 `Value` 枚举
    - 在既有 `VStr`/`VInt`/`VBool`/`VFloat` 之后**追加** `VMap(Map[String, Value])` 与 `VList(Array[Value])` 两个嵌套变体，保持 `derive(Eq, Show)`
    - 既有四个标量变体的名称、载荷与构造形态逐字保留；不改 `Event`/`Span`/`SpanId`/`TraceId`/`Level` 的任何声明
    - _Requirements: 1.1, 1.2, 12.1_

  - [x] 1.2 新增 `value_ext.mbt` 嵌套取值助手
    - 实现 `Value::is_scalar`（标量→true）、`Value::is_nested`（`VMap`/`VList`→true）、`Value::depth`（标量为 0，嵌套为 `1 + max(子取值 depth)`）
    - 在文件头注释标注职责与对应需求
    - _Requirements: 1.2_

  - [x]* 1.3 为嵌套助手编写单元测试
    - 覆盖多层 `VMap`/`VList` 的 `depth` 计算、`is_scalar`/`is_nested` 在各变体上的判定（写入 `value_ext_test.mbt`）
    - _Requirements: 1.2_

- [x] 2. 嵌套 JSON 渲染与解析（`logging.mbt` 私有助手加性追加）
  - [x] 2.1 为既有 JSON 编解码助手追加嵌套臂
    - `value_to_json`：追加 `VMap(m)`（成员按键名升序稳定排序、`"key":value` 递归渲染、`{}` 包裹）与 `VList(xs)`（按原序递归渲染、逗号分隔、`[]` 包裹）两臂，标量臂逐字保留
    - `jval_to_value`：将 `JObj(pairs)` 还原为 `VMap`、新增 `JArr(items)` 还原为 `VList`；`JsonReader`/`parse_value` 追加 `'['` → `parse_array` 分支与 `JVal::JArr` 变体
    - 保持 `format_json`/`parse_json_log` 公开签名与对仅含标量字段事件的逐字节行为不变
    - _Requirements: 1.3, 1.4, 1.5, 12.2, 12.4_

  - [x]* 2.2 为嵌套 JSON 往返编写属性测试
    - **Property 1: 嵌套 JSON 往返（nested JSON round-trip）** —— `parse_json_log(format_json(e)) == Some(e)`，`e` 含任意嵌套深度取值（生成器带深度上界）
    - **Validates: Requirements 1.2, 1.3, 1.4, 1.6**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_nested_json_test.mbt`）

  - [x]* 2.3 为既有标量 JSON 往返编写属性测试
    - **Property 2: 既有标量 JSON 往返（legacy scalar JSON round-trip）** —— 仅含标量字段事件 `parse_json_log(format_json(e)) == Some(e)`，且输出与 `0.1.0` 逐字节一致
    - **Validates: Requirements 1.5, 12.4, 12.7**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_legacy_json_test.mbt`）

  - [x]* 2.4 为嵌套样例与标量回归编写单元测试
    - 多层 `VMap`/`VList` 的具体渲染/解析见证；仅含标量字段事件输出与 `0.1.0` 逐字节一致的回归用例（写入 `logging_nested_test.mbt`）
    - _Requirements: 1.3, 1.4, 1.5_

- [x] 3. 检查点 —— 确保嵌套取值与 JSON 往返通过
  - Ensure all tests pass, ask the user if questions arise.（三后端含 native 时先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 4. 多 formatter 与可插拔 sink（`logfmt.mbt` + `formatter.mbt`）
  - [x] 4.1 新增 `logfmt.mbt`：logfmt 格式器与解析器
    - 实现 `format_logfmt`（`ts=<n> level=<LABEL> <k>=<v> …`，字段按键名升序；含空格/等号/引号/控制字符的值施加双引号包裹与转义）
    - 实现 `parse_logfmt`（还原等价 `Event`；语法非法返回 `None`，不产部分事件；`level` 经 `Level::from_label` 还原）；嵌套取值在 logfmt 域内以内嵌 JSON 文本表示
    - _Requirements: 2.3, 2.6_

  - [x]* 4.2 为 logfmt 往返编写属性测试
    - **Property 3: logfmt 往返（logfmt round-trip）** —— 仅含标量字段事件 `parse_logfmt(format_logfmt(e)) == Some(e)`
    - **Validates: Requirements 2.3, 2.6, 2.7**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_logfmt_test.mbt`）

  - [x] 4.3 新增 `formatter.mbt`：格式器枚举、`format_event`、可插拔 `Sink` 与 `dispatch`
    - 实现 `Formatter{Json|Logfmt|Pretty}`（`Json` 复用 `format_json`、`Logfmt` 复用 `format_logfmt`、`Pretty` 输出对齐单行供阅读）与 `format_event(fmt, e)`
    - 实现 `Sink`（name + formatter + 路由谓词 + 内存 `buffer`）、`Sink::new` 与 `dispatch(sinks, e)`（交付给全部路由匹配的 sink，无匹配不交付）
    - _Requirements: 2.1, 2.2, 2.4, 2.5_

  - [x]* 4.4 为格式器确定性编写属性测试
    - **Property 4: 格式器确定性（formatter determinism）** —— 对任一 `fmt ∈ {Json, Logfmt, Pretty}`，`format_event(fmt, e) == format_event(fmt, e)`，渲染由事件内容唯一确定
    - **Validates: Requirements 2.2**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_formatter_test.mbt`）

  - [x]* 4.5 为 logfmt 转义与多 sink 交付编写单元测试
    - logfmt 引号/转义边界（含空格/等号/控制字符的值）；多 sink 多格式交付（同一事件落地多种格式）、路由谓词匹配/不匹配（写入 `formatter_test.mbt`）
    - _Requirements: 2.3, 2.5_

- [x] 5. 确定性采样与限流（`sampling.mbt`）
  - [x] 5.1 实现 trace 内一致采样 `sample_trace` 与混合函数 `mix`
    - `mix` 为纯整型（FNV/xorshift 风格）混合函数，三后端逐位一致；`sample_trace(rate, trace, seed)` 决策仅由 `trace` 标识与配置决定：`keep ⟺ (mix(trace, seed) mod DENOM) < floor(rate*DENOM)`；`rate=0.0` 恒弃、`rate=1.0` 恒采
    - _Requirements: 3.1, 3.2, 3.3_

  - [x]* 5.2 为 trace 内采样一致性编写属性测试
    - **Property 5: trace 内采样一致性（trace-coherent sampling）** —— 同一 `trace` 的全部事件 `sample_trace` 判定相同（全采或全弃）
    - **Validates: Requirements 3.3, 3.6**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_sample_trace_test.mbt`）

  - [x] 5.3 实现事件流系统采样 `sample_stream` 与 `retained_count`
    - 系统采样：确定性保留 `floor(rate*n)` 条事件，`rng` 仅决定保留相位（起点）不改条数；`rate=0.0` 全弃、`rate=1.0` 全采；`retained_count(rate, n) = floor(rate*n)`
    - _Requirements: 3.1, 3.2, 3.4, 3.7_

  - [x]* 5.4 为采样比例有界编写属性测试
    - **Property 6: 采样比例有界（sampling-ratio bound）** —— `len(sample_stream(rate, events, rng)) <= retained_count(rate, len(events))` 且 `retained_count(rate, n) <= ceil(rate*n)`；边界 `rate=0.0`/`1.0`
    - **Validates: Requirements 3.1, 3.2, 3.7**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_sample_bound_test.mbt`）

  - [x]* 5.5 为采样确定性与可重放编写属性测试
    - **Property 7: 采样确定性与可重放（sampling determinism）** —— 相同配置与相同 `Rng` 种子两次重放同一序列，保留/丢弃序列逐元素相等
    - **Validates: Requirements 3.1, 3.4**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_sample_determinism_test.mbt`）

  - [x] 5.6 实现限流器 `RateLimiter`
    - `RateLimiter::new(window, limit)` 与 `RateLimiter::allow(key, ts)`：`ts` 超出当前窗口则重置窗口起点与计数；窗内放行至 `limit` 条后丢弃超额事件
    - _Requirements: 3.5_

  - [x]* 5.7 为限流配额上界编写属性测试
    - **Property 8: 限流配额上界（rate-limit quota bound）** —— 任一逻辑时间窗内对同一 key 放行条数不超过 `limit`，超额事件被丢弃
    - **Validates: Requirements 3.5**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_ratelimit_test.mbt`）

- [x] 6. 过滤与路由（`filter.mbt`）
  - [x] 6.1 实现 `EnvFilter`/`FilterError` 与指令解析、阈值判定
    - `parse_env_filter(spec)`：解析 `target=level,target2=level2,level`（末尾裸 level 为兜底）；先完整校验后构造，任一项非法返回 `Err(FilterError{pos, message})` 且不登记任何阈值
    - `EnvFilter::threshold_for(target)`（命中指令用其阈值，否则用兜底）与 `EnvFilter::allows(e)`（保留 ⟺ `e.level.rank() >= threshold_for(target).rank()`，target 取自事件 `"target"` 字段，缺失走兜底）
    - _Requirements: 4.1, 4.3, 4.4_

  - [x] 6.2 实现字段谓词过滤 `field_filter` 与路由 `route`
    - `field_filter(pred, e)`（仅保留字段满足谓词的事件）；`route(sinks, e)`（返回路由匹配的全部 sink 名称，无匹配返回空数组，与 `dispatch` 协同）
    - _Requirements: 4.2, 4.5_

  - [x]* 6.3 为过滤判定一致性编写属性测试
    - **Property 9: 过滤判定一致性（filter-decision consistency）** —— `EnvFilter::allows(f, e) ⟺ e.level.rank() >= f.threshold_for(target_of(e)).rank()`；且 `field_filter(pred, e) ⟺ pred(e.fields)`
    - **Validates: Requirements 4.1, 4.2, 4.6**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_filter_test.mbt`）

  - [x]* 6.4 为非法指令与路由匹配编写单元测试
    - EnvFilter 非法指令定位（缺 `=`、级别标签不可识别返回携带偏移的错误）；路由匹配/无匹配交付（写入 `filter_test.mbt`）
    - _Requirements: 4.4, 4.5_

- [x] 7. 检查点 —— 确保格式器、采样限流、过滤路由通过
  - Ensure all tests pass, ask the user if questions arise.（三后端含 native 时先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 8. OpenTelemetry 风格 span 语义（`otel_span.mbt`）
  - [x] 8.1 实现 `SpanStatus`/`SpanKind`/`SpanEvent`/`SpanData` 与方法
    - `SpanData::new(span)`（默认 `status=Unset`、`kind=Internal`、空属性/事件）、`set_attribute`、`add_event`、`set_status`、`set_kind`；纯旁路叠加既有 `Span`，不改其字段或 `enter_span`/`exit_span`/`span_duration` 行为
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x]* 8.2 为 span 树父子不变量与时长非负编写属性测试
    - **Property 10: span 树父子不变量（span-tree invariant）** —— 每个非根 span 父标识等于进入时刻激活 span 标识，且每个已结束 span `span_duration(s) == Some(d)` 蕴含 `d >= 0`；固化 OTel 旁路叠加后既有行为不变
    - **Validates: Requirements 5.5, 5.6**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_span_tree_test.mbt`）

  - [x]* 8.3 为 span 属性/事件/状态/kind 编写单元测试
    - 属性保留、span 事件名称/时间戳/字段归属当前 span、状态与 kind 默认值（`Unset`/`Internal`）（写入 `otel_span_test.mbt`）
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 9. W3C Trace Context 注入/提取（`trace_context.mbt`）
  - [x] 9.1 实现 `W3CContext` 与 `inject_traceparent`/`extract_traceparent`/`is_sampled`/`to_trace_context`
    - `inject_traceparent(ctx)` 产出 `00-<32hex>-<16hex>-<2hex>`（内部 64 位标识编码进 trace-id 低位、高位补 0，flags 默认 `01`）
    - `extract_traceparent(s)` 严格校验（恰 4 个 `-`、各分量长度精确、合法 hex），非法返回 `None` 不产部分上下文；`W3CContext::is_sampled`（flags 最低位为 1）与 `to_trace_context`（桥接既有 `TraceContext`，可经 `with_context` 续记）
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [x]* 9.2 为 traceparent 注入/提取往返编写属性测试
    - **Property 11: traceparent 注入/提取往返（traceparent inject/extract round-trip）** —— `extract_traceparent(inject_traceparent(ctx))` 为 `Some(w)`，三分量与 `ctx` 标识及采样标志一致，注入文本满足 `00-<32hex>-<16hex>-<2hex>` 形态
    - **Validates: Requirements 6.1, 6.2, 6.6**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_traceparent_test.mbt`）

  - [x]* 9.3 为非法提取与桥接续记编写单元测试
    - 字段数/长度/hex 不符返回 `None`；sampled 位判定；`to_trace_context` 后经 `with_context` 续记保持 trace 关联（写入 `trace_context_test.mbt`）
    - _Requirements: 6.3, 6.4, 6.5_

- [x] 10. 脱敏 / PII 过滤（`redaction.mbt`）
  - [x] 10.1 实现 `redaction_mask`/`RedactionPolicy`/`redact`
    - `redaction_mask`（固定 `VStr("[REDACTED]")`）、`RedactionPolicy::by_names`/`with_predicate`；`redact(policy, e)`：字段名命中集合或谓词为真者取值**整体**替换为掩码（嵌套 `VMap`/`VList` 也整体替换），其余不变，字段键集合保持不变
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x]* 10.2 为脱敏完整性编写属性测试
    - **Property 12: 脱敏完整性（redaction-completeness）** —— 每个敏感字段取值等于掩码（内部无原值片段残留），字段键集合与脱敏前逐一致、非敏感字段不变
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_redaction_test.mbt`）

  - [x]* 10.3 为嵌套整体掩码与键集合不变编写单元测试
    - 敏感字段为嵌套 `VMap`/`VList` 时整体掩码、键集合不变、谓词命中（写入 `redaction_test.mbt`）
    - _Requirements: 7.3, 7.4_

- [x] 11. 指标派生（`metrics.mbt`）
  - [x] 11.1 实现按级别计数 `count_by_level`/`level_count`
    - 返回长度 5 的非负计数定长数组（下标 = `Level::rank`，规避三后端 Map 顺序差异）；`level_count(counts, level)` 取对应级别计数
    - _Requirements: 8.1_

  - [x]* 11.2 为计数守恒编写属性测试
    - **Property 13: 计数守恒（counter-conservation）** —— 各级别计数非负且 `sum(count_by_level(events)) == len(events)`
    - **Validates: Requirements 8.1, 8.4**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_counter_test.mbt`）

  - [x] 11.3 实现直方图 `Histogram`/`histogram`
    - 按升序边界把某数值字段（`VInt`/`VFloat`）二分入桶（桶数 = `len(boundaries)+1`，含上溢桶）；缺该字段或字段非数值（`VStr`/`VBool`/`VMap`/`VList`）的事件跳过不计
    - _Requirements: 8.2, 8.3_

  - [x]* 11.4 为指标派生确定性编写属性测试
    - **Property 14: 指标派生确定性（metrics-determinism）** —— 对同一输入两次派生所得按级别计数与直方图逐桶相等；直方图仅计入数值字段事件，跳过缺字段/非数值事件
    - **Validates: Requirements 8.2, 8.3, 8.5**
    - 复用 `@infra_pbt`，≥100 迭代（写入 `prop_metrics_test.mbt`）

  - [x]* 11.5 为直方图跳过逻辑编写单元测试
    - 缺目标字段、字段为非数值取值的事件不计入任何桶；边界分桶具体见证（写入 `metrics_test.mbt`）
    - _Requirements: 8.3_

- [x] 12. 检查点 —— 确保 OTel span、traceparent、脱敏、指标通过
  - Ensure all tests pass, ask the user if questions arise.（三后端含 native 时先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 13. 端到端实战 demo（`demo.mbt`）
  - [x] 13.1 实现 `DemoOutcome` 与 `run_demo`
    - 串联 `begin_trace` → 嵌套 `enter_span`/`exit_span` + OTel 属性/事件 → 采样 + 脱敏 → JSON 与 logfmt 双格式渲染 → `traceparent` 注入，返回 `DemoOutcome`（trace / json_lines / logfmt_lines / traceparent / span_count）
    - _Requirements: 11.1, 11.2_

  - [x] 13.2 实现模拟下游进程 `run_downstream`
    - 从 `traceparent` 提取上下文并在其下继续记录，返回下游事件的 trace-id（与父进程归属同一 trace-id）
    - _Requirements: 11.3_

  - [x]* 13.3 为 demo 端到端流程编写单元测试
    - 验证嵌套 span/采样/脱敏/多格式输出，以及 `run_demo` 注入 → `run_downstream` 提取后下游与父进程同 trace-id（写入 `demo_test.mbt`）
    - _Requirements: 11.2, 11.3_

- [x] 14. 性能基准包（`benches/logging_bench/`）
  - [x] 14.1 新增 `benches/logging_bench` 基准包
    - 创建 `logging_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`（结构对齐既有 `benches/astar_bench`），覆盖四类负载：高频 `log`、格式化（JSON 与 logfmt）、采样判定（`sample_trace`/`sample_stream`）、span 进入/退出；产出含机器标识/后端目标/输入规模/计时统计的 JSON 或 Markdown 工件至 `benches/results/`
    - native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 9.1, 9.2_

  - [x] 14.2 接入基准回归基线 guard
    - 将新基准运行与已记入基线中位数比较，超声明容差时产出可审计失败报告（复用既有 guard 模式）；在基准文档记录可复现运行命令与 native 前置导出
    - _Requirements: 9.3, 9.4_

- [x] 15. 可执行文档与 paper-to-code 可解释性（`README.mbt.md`）
  - [x] 15.1 扩充 `README.mbt.md` 覆盖全部新能力与 demo
    - 可执行示例覆盖嵌套取值、多 formatter、采样与限流、过滤与路由、span 语义、traceparent、脱敏、指标派生与端到端 demo（含 `run_demo`/`run_downstream`），全部经 `moon test *.mbt.md` 验证（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
    - _Requirements: 11.4, 13.4_

  - [x] 15.2 补充 paper-to-code 追溯、开源对标与实现边界声明
    - 在 `README.mbt.md` 写入：span 树/上下文追溯 Dapper、OTel 语义追溯 OpenTelemetry 规范、traceparent 追溯 W3C Trace Context、logfmt 追溯结构化日志约定；与 `tracing`/`slog`/`zap`/OpenTelemetry SDK 的模型与权衡对比；显式声明实现边界（内存 sink/不耦合 async/逻辑时钟/128↔64 映射）
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

- [x] 16. 发布推进与门禁（`release.mbt` + `CHANGELOG.md`）
  - [x] 16.1 推进 SemVer 版本并更新 CHANGELOG
    - 在 `release.mbt` 仅推进版本字符串（自 `0.1.0` 起按旗舰深化做次/主版本推进），保持 `release_info`/`release_info_with_gates` 语义不变；更新 `src/logging/CHANGELOG.md` 记录本次深化
    - _Requirements: 12.6, 13.6_

  - [x]* 16.2 为发布门禁真值表编写回归测试
    - 验证三后端测试/属性测试/可执行文档任一未过时 `release_info_with_gates` 阻止进入 release-ready；`release_info` 稳定性（写入 `release_gate_test.mbt`）
    - _Requirements: 13.7_

  - [x]* 16.3 三后端一致性回归校验
    - 在 `wasm-gc`/`js`/`native` 运行同一套件并断言输出一致（任一分歧判失败）；native 运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 13.1, 13.5_

- [x] 17. 最终检查点 —— 确保全部测试、属性测试与可执行文档通过
  - Ensure all tests pass, ask the user if questions arise.（三后端含 native 时先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

## 备注（Notes）

- 标 `*` 的子任务为可选（单元测试 / 属性测试 / 回归测试），可为更快的 MVP 跳过；顶层任务不标 `*`。
- 每条正确性属性（Property 1~14）独立成一个 `*` 子任务，复用 `@infra_pbt` 且**每条 ≥100 迭代**，并以 `**Validates: Requirements X.Y**` 链接验收标准。
- 严格向后兼容：既有 `types`/`logging`/`release` 公开签名与行为冻结；`Value` 仅加性追加 `VMap`/`VList`；私有 JSON 助手仅追加嵌套臂，标量行为与 `format_json`/`parse_json_log` 逐字节不变。
- 检查点（任务 3/7/12/17）用于阶段性增量验证。
- 涉及 native 的测试 / 基准 / 文档校验，运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "4.1", "5.1", "6.1", "8.1", "9.1", "11.1"] },
    { "id": 2, "tasks": ["1.3", "2.2", "2.3", "2.4", "4.2", "4.3", "5.2", "5.3", "8.2", "8.3", "9.2", "9.3", "11.2", "11.3"] },
    { "id": 3, "tasks": ["4.4", "4.5", "5.4", "5.5", "5.6", "6.2", "10.1", "11.4", "11.5"] },
    { "id": 4, "tasks": ["5.7", "6.3", "6.4", "10.2", "10.3", "13.1", "14.1"] },
    { "id": 5, "tasks": ["13.2", "14.2", "16.1"] },
    { "id": 6, "tasks": ["13.3", "15.1", "16.2"] },
    { "id": 7, "tasks": ["15.2", "16.3"] }
  ]
}
```
