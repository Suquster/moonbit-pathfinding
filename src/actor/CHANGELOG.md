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

### Added
- **async/await 风格 ask API `Future[R]`（C2，2026-07-07）**：`future.mbt` 旁路
  新增——`ask_future` 发起立即返回句柄（发起与等待解耦，支持多请求并发在飞），
  `await_within` 确定性驱动等待（无墙钟），`poll_result`/`is_ready` 非阻塞
  轮询，`ready`/`map`/`and_then` 组合子；重复 await 幂等（结果缓存，不二次
  消费）。既有 `ask` / `send` 语义零改动。测试 `future_test.mbt`。
- 高吞吐批量调度驱动 `ActorSystem::run_until_idle_throughput`
  （throughput.mbt，旁路新增、既有 `step` / `run_until_idle` 冻结）：
  轮转批量策略把每消息 O(A) 的就绪扫描摊还为 O(A×轮数+消息数)，
  10k actor × 10 msgs 负载实测 ≈9.58M msgs/sec（逐步驱动 ≈12.4k，≈772×）；
  保持串行处理 / per-actor FIFO / 恰好一次 / 监督重启 / 停止结算语义，
  终态与逐步驱动差分一致（throughput_test.mbt）。

## [0.2.0] - 2026-06-12

旗舰深化版（breadth + depth 深化）：在冻结骨架首版对外契约的前提下，以旁路平行
类型承载业界对标的 actor 能力——行为/上下文、生命周期与重启语义、监督树、
请求-响应（ask）、消息暂存、死亡监视、路由、有界邮箱背压、确定性重放，以及
一个与既有 `Scheduler` 平行共存的旗舰驱动器 `ActorSystem`。版本自 `0.1.0`
推进至 `0.2.0`。

### Added
- 行为与处理上下文：`Behavior[S, M]`、`ActorContext[S, M]`；通过 ctx 记录
  `become_` / `unbecome` / `stash` / `unstash_all` / `watch` / `unwatch`
  等效果（新增可组合行为切换与上下文效果记录）。
- 生命周期钩子与重启语义：`LifecycleHooks[S]`、`TerminationReason`，以及
  `restart_state` / `start_state`（新增 pre/post 钩子驱动的重启状态推导）。
- 监督策略 / 指令 / 强度 / 监督树：`SupervisionStrategy`
  （`OneForOne` / `OneForAll` / `RestForOne`）、`Directive`
  （`Restart` / `Stop` / `Escalate`）、`RestartIntensity`、`SupervisorSpec`，
  以及 `affected_children` / `within_intensity`（新增受影响子集推导与重启
  强度窗口判定）。
- 请求-响应 ask：`CorrelationId`、`AskResult[R]`、`AskBroker[R]`，以及系统级
  `ask()`（新增基于关联 ID 的请求-响应往返）。
- 消息暂存：`StashBuffer[M]`，保序回流（新增暂存缓冲与 FIFO 顺序回灌）。
- 死亡监视：`WatchRegistry` / `WatchEntry`，以及 Akka `watchWith` 风格的
  `Terminated` 适配器（新增观察者注册与终止通知投递）。
- 路由器：`RoutingStrategy`（`RoundRobin` / `Broadcast` / `ConsistentHash`）、
  `Router[M]`，一致性哈希采用整数 FNV-1a + 排序环（新增确定性消息路由）。
- 有界邮箱与背压：`BackpressurePolicy`
  （`DropNewest` / `DropOldest` / `Reject`）、`OfferResult`、
  `BoundedMailbox[M]`，并保持计数守恒（新增容量上限与背压投递结果）。
- 旗舰驱动器：`ActorSystem[S, M]`（与既有 `Scheduler` 平行共存）、私有
  `SupervisedCell`，以及 `spawn` / `supervise` / `step` / `run_until_idle`
  与状态观测接口（新增受监督的旗舰驱动器）。
- 确定性调度与重放：`TraceEvent`、`replay_consistent`、`trace_of`，以及种子
  驱动调度（新增可重放的确定性事件迹）。
- 端到端示例：`worker_pool_demo` / `WorkerPoolReport`，演示受监督的工作池
  （新增受监督工作池端到端样例）。
- 属性测试：Property 1~31 各 ≥100 迭代、跨三后端（wasm-gc / js / native）
  一致；可执行文档（`README.mbt.md`）扩充覆盖八大能力；`benches/actor_bench/`
  新增五类负载基准与回归 guard（新增旗舰能力的属性测试、可执行文档与基准）。
- release：`actor_version` 自 `0.1.0` 推进至 `0.2.0`（新增版本推进登记）。

### Notes
- 纯内存确定性模型：以同步 `step` 驱动模拟消息循环，不接入真实并发 / 线程 /
  网络 / 分布式，也不耦合 `moonbitlang/async`。
- 失败以显式枚举信号（`Errored` / `Rejected` / `Timeout`）表达，不使用 `raise`
  跨后端传播，保证三后端语义一致。
- 向后兼容：既有 `pub(all)` 类型与 `Scheduler` 的形状 / 语义保持冻结，全部新增
  能力以旁路平行类型承载，既有使用方式继续工作（对应 R13.5）。

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/actor-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/actor-v0.1.0...actor-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/actor-v0.1.0
