# Changelog —— DST_Framework（方向八）

本文件记录 **DST_Framework**（Deterministic Simulation Testing）方向
（子包 `src/dst`）作为**独立发布单元**的全部值得关注的变更。

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

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ 确定性可重放不变量属性测试 + 可执行文档」的方向骨架基线。

### Added
- 确定性随机源：`Rng`（xorshift64：仅逻辑移位 + 按位异或，三后端逐位一致）
  与 `rng_new` / `Rng::next` / `Rng::next_below`，作为确定性可重放的基石；
  种子为 0 时回退到非零常数以保证完整周期，并保留原始 `seed` 以便重放回溯
  （新增种子驱动确定性伪随机源）。
- 核心类型：`Task`、`Event`（`Scheduled` / `Faulted` / `Completed` 事件轨迹
  元素）、`FaultKind`（`Crash` / `Delay` / `Drop`）、`FaultPolicy`（注入点 +
  目标任务 + 故障类型）、`Scenario`（任务集 + 故障策略集 + 步数上限）、
  `SimStatus`（`Completed` / `Failed`）、`SimResult`（种子 + 轨迹 + 终态）与
  `Sim`（随机源 + 待调度任务 + 事件轨迹），并提供配套 `new` 构造器
  （新增仿真核心数据模型）。
- 确定性调度：`Sim::step` 依确定性随机源从待调度任务中选择下一任务，向轨迹
  追加 `Scheduled` 与 `Completed` 事件；`run` 以「任务 id 升序」规范化待调度
  集合，保证「同种子 → 同调度序列 + 同终态」，不依赖输入任务排列
  （新增确定性任务调度）。
- 故障注入：`Sim::inject_fault` 在 `policy.at_step` 命中当前步序号时对目标
  任务触发 `Crash` / `Delay` / `Drop` 故障并追加 `Faulted` 事件；`run` 以
  `(at_step, task_id)` 升序规范化故障注入顺序（新增确定性故障注入）。
- 失败重放：`replay` 依「种子 + 事件轨迹」复现完全一致的 `SimResult`，终态
  由 `status_from_trace` 据轨迹确定性派生（含崩溃故障 → `Failed`）
  （新增种子 + 事件轨迹失败重放）。
- 属性测试：确定性可重放不变量（同种子两次运行逐事件一致、`replay` 复现原
  结果），跨三后端一致（新增确定性可重放属性测试）。
- 可执行文档：展示同种子两次运行产生一致调度序列的 `*.mbt.md` 端到端样例
  （新增 DST 可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/dst/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/dst-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/dst-v0.1.0
