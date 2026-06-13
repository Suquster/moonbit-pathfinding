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

## [0.2.0] - 2026-06-11

旗舰深化（深度优先）：在 `0.1.0` 骨架之上做**严格向后兼容的增量深化**，对标
FoundationDB 确定性仿真、TigerBeetle VOPR、`madsim`/`turmoil` 与 Jepsen/Knossos。
既有 `Rng` / `Sim` / `run` / `replay` / 核心类型与发布门禁的公开签名、字段、变体与
运行时语义全部冻结，新能力一律旁路扩展（新增类型 / 文件 / 函数），既有
`FaultKind` / `Event` / `SimStatus` 枚举不扩容。

### Added
- 逻辑时钟 / 虚拟时间：`LogicalTime`（`UInt64` 透明别名）与 `skewed_time`（时钟偏移
  下钳），并固化「(逻辑时间戳, 任务 id, 次序键)」全序约定（`clock.mbt`）。
- 离散事件仿真（DES）数据模型：`Message` / `SimEvent`（带时间戳，含 `EvSend` /
  `EvDeliver`）/ `NodeApp` / `Node` / `Action` / `Protocol` / `DesScenario` /
  `DesResult`，复用既有 `Task` / `SimStatus`（`des_types.mbt`）。
- 全序事件队列：`EventQueue` / `QueuedEvent` / `Pending`，不可变 `push` /
  `pop_min`（`event_queue.mbt`）。
- 消息传递与因果序：`World::schedule_send` / `World::deliver`，无丢弃 / 分区下
  发送—投递一一配对且投递严格晚于发送（`messaging.mbt`）。
- 丰富故障模型：平行枚举 `NetFaultKind`（`Partition` / `Reorder` / `Duplicate` /
  `ClockSkew` / `Byzantine` + `Crash` / `Delay` / `Drop` 语义等价项）与
  `FaultPolicyEx`，以及向后兼容桥 `NetFaultKind::of_legacy` /
  `FaultPolicyEx::of_legacy`（`faults_ext.mbt`）。
- DES 核心循环：`World` / `World::new` / `World::step` / `run_des` / `replay_des`，
  同种子 → 同执行；遗留桥 `DesScenario::of_legacy`（无消息场景调度与既有 `run`
  逐事件一致）（`des_sim.mbt`）。
- 运行时不变量：`Invariant` 与每步求值，违反即以 `Failed`（含不变量名与逻辑时间戳）
  终止（`invariant.mbt`）。
- 失败用例收缩：`shrink`（delta debugging，单调 + 终止）/ `ShrinkOutcome` /
  `DesScenario::size`（`shrink.mbt`）。
- 调度空间探索：`explore_bounded`（有界穷尽交错枚举）/ `Schedule` / `ExploreReport`
  （`explore.mbt`）。
- DPOR 偏序约简：`depends`（事件依赖）/ `explore_dpor`（睡眠集约简，每等价类至少
  一代表，不漏报）（`dpor.mbt`）。
- 线性一致性检查：Wing & Gong 线性化点 `is_linearizable` / `History` / `OpEvent` /
  `RegisterModel` / `LinResult`（`linearizability.mbt`）。
- 轨迹持久化：`serialize_result` / `deserialize_result`（`Result` + `CodecError`，
  损坏输入返回带偏移的 `Malformed`，绝不部分构造）与 `@infra_pbt.round_trip` 适配
  `result_to_bytes` / `result_of_bytes`（`trace_codec.mbt`）。
- 多副本复制端到端 demo：`replication_protocol` / `demo_replication_scenario` /
  `demo_partition_crash_scenario` / `replica_consistency_invariant`，串起「发现—收缩
  —重放—校验」闭环（`demo.mbt`）。
- 属性测试：15 条正确性属性（Property 1~15，各 ≥100 迭代，复用 `@infra_pbt`）覆盖
  同种子确定性、虚拟时间单调 + 事件全序、因果序保持、仿真终止、故障注入确定可重放、
  网络故障语义、收缩保真 / 终止单调、有界穷尽完整、DPOR 可靠性 / 约简有效性、不变量
  违反检出、线性一致性判定、序列化往返、跨会话重放保真。
- 性能基准：`benches/dst_bench` 覆盖 `run_des` / `replay_des` / `explore_bounded` /
  `explore_dpor` / `shrink` 五类工作负载与 DPOR 约简比 guard。
- 可执行文档：`README.mbt.md` 扩充虚拟时间 / 消息 / 丰富故障 / 收缩 / 探索 / 持久化
  示例与 paper-to-code 追溯、开源对标、实现边界声明。

### Changed
- 版本号自 `0.1.0` 推进至 `0.2.0`（次版本，向后兼容的新增能力）。

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/dst-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/dst-v0.1.0...dst-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/dst-v0.1.0
