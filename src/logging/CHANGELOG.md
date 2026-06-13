# Changelog —— Logging_Library（方向七）

本文件记录 **Logging_Library** 方向（子包 `src/logging`）作为
**独立发布单元**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`）。

---

## [Unreleased]

## [0.2.0] - 2026-06-12

旗舰深化（🟣 档位 3「业界顶尖」）：在 `0.1.0` 骨架之上做**严格向后兼容**的增量
深化，对标 Rust `tracing`、`slog`、Uber `zap` 与 OpenTelemetry SDK。既有公开类型/
函数签名与运行时语义冻结；`Value` 仅**加性追加** `VMap`/`VList`；私有 JSON 助手
仅追加嵌套臂——仅含标量字段事件的 `format_json`/`parse_json_log` 输出与解析与
`0.1.0` 逐字节不变（已由 Property 2 字节级见证固化）。全部新能力以旁路新增
`.mbt` 文件提供，三后端（wasm-gc / js / native）一致、零回归。

### Added
- **嵌套结构化取值（`types.mbt` / `value_ext.mbt`）**：`Value` 追加 `VMap`/`VList`
  嵌套变体（R1.1/1.2）；`Value::is_scalar`/`is_nested`/`depth` 嵌套助手。
- **嵌套 JSON 往返（`logging.mbt` 私有助手加性追加）**：`value_to_json` 追加
  `VMap`（成员升序）/`VList` 臂、`parse_value` 追加数组分支、`jval_to_value` 还原
  嵌套 `VMap`/`VList`；`format_json`/`parse_json_log` 公开签名与标量行为不变
  （R1.3/1.4/1.5）。
- **多 formatter 与可插拔 sink（`formatter.mbt` / `logfmt.mbt`）**：
  `Formatter{Json|Logfmt|Pretty}` 与 `format_event`；logfmt 格式器 `format_logfmt`
  与解析器 `parse_logfmt`（引号/转义/标量域往返）；内存 `Sink` + `dispatch` 多 sink
  交付（R2.*）。
- **确定性采样与限流（`sampling.mbt`）**：trace 内一致采样 `sample_trace`（纯整型
  混合 `mix`）、事件流系统采样 `sample_stream` + `retained_count`（比例有界、可重放）、
  逻辑时间窗限流 `RateLimiter`（R3.*）。
- **过滤与路由（`filter.mbt`）**：`EnvFilter` 指令解析（`parse_env_filter`，携带
  偏移定位的 `FilterError`）、`threshold_for`/`allows`、字段谓词 `field_filter`、
  路由 `route`（R4.*）。
- **OpenTelemetry span 语义（`otel_span.mbt`）**：`SpanStatus`/`SpanKind`/`SpanEvent`/
  `SpanData`（属性/事件/状态/kind），旁路叠加既有 `Span` 不改其语义（R5.*）。
- **W3C Trace Context（`trace_context.mbt`）**：`inject_traceparent`/
  `extract_traceparent`/`W3CContext`（`is_sampled`/`to_trace_context`），128↔64
  编码映射（R6.*）。
- **脱敏 / PII 过滤（`redaction.mbt`）**：`redaction_mask`/`RedactionPolicy`/`redact`
  （字段名集合 + 谓词，嵌套整体掩码，键集合不变）（R7.*）。
- **指标派生（`metrics.mbt`）**：`count_by_level`（定长数组）/`level_count`、
  `Histogram`/`histogram`（升序边界二分入桶，跳过缺字段/非数值事件）（R8.*）。
- **端到端 demo（`demo.mbt`）**：`run_demo`/`run_downstream` 串联嵌套 span/采样/
  脱敏/双格式/traceparent 跨进程传播（R11.*）。
- **性能基准（`benches/logging_bench`）**：高频 log / 格式化 / 采样判定 / span 进出
  四类负载 + 内联基线回归 guard（R9.*）。
- **属性测试（14 条正确性属性，各 ≥100 迭代，复用 `@infra_pbt`）**：嵌套 JSON 往返、
  既有标量 JSON 往返、logfmt 往返、格式器确定性、trace 内采样一致、采样比例有界、
  采样确定可重放、限流配额上界、过滤判定一致、span 树父子不变量、traceparent 往返、
  脱敏完整性、计数守恒、指标派生确定性（R13.2）。
- **可执行文档**：`README.mbt.md` 扩充覆盖全部新能力与端到端 demo，含 paper-to-code
  追溯（Dapper/OpenTelemetry/W3C Trace Context/logfmt）、`tracing`/`slog`/`zap`/
  OpenTelemetry SDK 对标与实现边界声明（R10.* / R11.4 / R13.4）。

### Changed
- `release.mbt`：版本字符串 `0.1.0` → `0.2.0`（`release_info`/`release_info_with_gates`
  语义不变）。
- `moon.pkg`：`@infra_pbt` 由 test-only 提升为运行时依赖（采样与 demo 复用其确定性
  `Rng`）；新增能力均为旁路追加，不影响既有公开 API。

### 兼容性
- 既有 `Level`/`Event`/`Span`/`SpanId`/`TraceId`/`TraceContext`/`Value`（四个标量
  变体）与 `log`/`enter_span`/`exit_span`/`span_duration`/`begin_trace`/
  `capture_context`/`child_context`/`with_context`/`format_json`/`parse_json_log`/
  `captured_events`/`finished_spans`/`current_span`/`current_trace`/`reset_logger`/
  `set_threshold`/`current_threshold` 签名与语义冻结；既有属性测试（级别过滤/
  span 树/trace 传播/JSON 往返）零回归。

### 计划中（后续任务）
- 接入 `moonbitlang/async`，将 `with_context` 内部的任务局部存储模拟升级为
  基于异步运行时的真实上下文载体（对外契约不变）。

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：建立子包、核心类型与接口桩，达成
「可编译 + 跑通三后端（wasm-gc / js / native）+ 最小单元测试」的方向骨架
基线。完整功能（级别过滤 / span 树 / trace 传播 / 结构化往返）属任务 10.2。

### Added
- 核心类型：`Level`（Trace/Debug/Info/Warn/Error，含严重程度序 `rank` 与阈值
  判定 `is_enabled`）、`Value`（结构化字段取值）、`SpanId` / `TraceId`
  （标识符）、`Event`（时间戳 + 级别 + 字段）、`Span`（id / parent / start /
  end）（新增日志核心数据模型）。
- 接口桩：`log` / `enter_span` / `exit_span` / `format_json` /
  `parse_json_log` 五个高层接口骨架（新增日志高层接口桩）。
- `format_json`：最小结构化 JSON 输出（含时间戳、级别标签与字段）
  （新增结构化输出最小实现）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/logging/CHANGELOG.md`）
  （新增方向发布元数据登记）。

### 依赖说明
- 关于 `moonbitlang/async`：design 声明本方向依赖该库以承载跨异步任务的
  trace 上下文传播（Requirement 7.6）。当前构建环境尚未在 `moon.mod.json`
  登记该依赖，且引入存在三后端覆盖不一致、阻塞「三后端 moon test 全绿」
  的风险。骨架阶段以本地 `TraceId` 最小抽象占位（不引入 async 运行时
  耦合），待依赖稳定登记后由任务 10.2 接入真实传播（详见 `moon.pkg`）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/logging-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/logging-v0.1.0...logging-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/logging-v0.1.0
