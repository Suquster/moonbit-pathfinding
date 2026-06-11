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

### Added（任务 10.2 已实现）
- `log` 级别阈值过滤：低于 `set_threshold` 配置阈值的事件被丢弃（R7.2）。
- `log` 事件上下文标注：激活 span 内的事件自动注入保留字段 `span`（当前
  span id）与 `trace`（当前 trace id）（R7.1 / R7.4）；单调逻辑时钟提供
  确定性时间戳（三后端逐位一致）。
- `enter_span` 关联当前激活 span 形成 span 树（根 span 无父，嵌套 span 挂接
  父 span）（R7.3）；`exit_span` 填充 `end` 并据此由 `span_duration` 计算
  持续时长（R7.5）。
- 跨异步任务边界 trace 上下文传播：`capture_context` / `child_context` /
  `with_context` 以「显式上下文 + 任务局部存储模拟」实现，保证子任务保留
  父任务的 trace 标识、子 span 正确挂接父 span（R7.6）。详见下方依赖说明。
- `format_json` / `parse_json_log` 完整结构化往返：字段按键名稳定排序、
  完整 JSON 转义（`\" \\ \n \r \t \b \f \uXXXX`）与还原，数值按整数/浮点
  分类解析，非法输入返回 `None` 不构造部分事件（R7.1 / R7.7）。
- 运行时观测/配置 API：`set_threshold` / `current_threshold` /
  `reset_logger` / `captured_events` / `finished_spans` / `current_span` /
  `current_trace` / `begin_trace`（新增日志运行时配置与观测接口）。
- `Level::from_label`：`Level::label` 的逆映射，支撑级别字段往返。

### 计划中（后续任务）
- 接入 `moonbitlang/async`，将 `with_context` 内部的任务局部存储模拟升级为
  基于异步运行时的真实上下文载体（对外契约不变）。
- 级别过滤 / span/trace 不变量属性测试（Property 16 / 17，任务 10.3）与
  结构化日志往返属性测试（Property 18，任务 10.4）。

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/logging-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/logging-v0.1.0
