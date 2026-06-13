# Changelog —— Actor_Framework（方向十）

本文件记录 **Actor_Framework** 方向（子包 `src/actor`）作为
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

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ FIFO / 错误隔离属性测试 + 可执行文档」的方向骨架基线。

### Added
- 核心类型：`ActorId`、`Mailbox[M]`、`ActorRef[M]`，并提供邮箱原语
  `Mailbox::new` / `enqueue` / `dequeue` / `peek` / `is_empty` / `length` /
  `close` / `is_closed`（新增 actor 标识、FIFO 邮箱与引用句柄）。
- 高层接口：`spawn`（派生 actor 返回引用句柄）、`ActorRef::send`（向邮箱
  FIFO 投递消息）、`ActorRef::stop`（请求停止）、`ActorRef::pending`
  与 `reset_runtime`（新增 spawn / send / stop 消息传递接口）。
- 确定性串行调度器 `Scheduler[S, M]`：`Scheduler::new` / `spawn` / `step` /
  `run_until_idle` / `state_of` / `status_of` / `is_running` / `pending`
  （新增确定性内存邮箱 + 显式 run/step 同步驱动的串行调度）。
- 邮箱语义：FIFO 入队 / 出队、单 actor 一次仅处理一条消息（串行处理不变量）、
  空邮箱时挂起不占处理步（新增 FIFO / 串行 / 空闲挂起语义）。
- 监督与错误隔离：处理结果 `ActorOutcome[S]`（`Updated` / `Errored`）与生命
  周期状态 `ActorStatus`（`Running` / `Stopped` / `Failed`）；未捕获错误终止
  该 actor、关闭并清空其邮箱、通知 supervisor，且不影响其他 actor
  （新增监督错误隔离）。
- 属性测试：Actor 串行与 FIFO 顺序不变量（Property 22）、错误隔离不变量
  （Property 23），跨三后端一致（新增 FIFO / 隔离属性测试）。
- 可执行文档：覆盖 spawn / send（FIFO）/ step / run_until_idle / stop /
  错误隔离与 supervisor 通知的 `*.mbt.md` 端到端样例（新增 actor 可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/actor/CHANGELOG.md`）（新增方向发布元数据登记）。

### Notes
- 关于 `moonbitlang/async`：设计中本方向以 `moonbitlang/async` 承载异步消息
  循环，但该外部依赖尚**未登记**到仓库 `moon.mod.json`，且引入存在三后端
  （wasm-gc / js / native）覆盖不一致、可能阻塞「三后端 moon test 全绿」硬性
  门禁的风险。故骨架首版采用**本地确定性内存邮箱 + 同步驱动占位模型**：以纯
  数据 FIFO 邮箱表达消息投递，以 `Scheduler` 的显式 `run` / `step` 同步驱动
  模拟串行调度（同消息序列 → 同处理顺序），不引入任何 async 运行时耦合。待
  上游 API 稳定登记后，可将同步驱动替换为真实异步消息循环，对外契约
  （spawn / send / stop 与 FIFO / 串行 / 隔离不变量）保持不变。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/actor-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/actor-v0.1.0
