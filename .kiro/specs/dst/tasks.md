# 实施计划（Implementation Plan）：DST_Framework 旗舰深化

## 概述（Overview）

本计划在已发布的 `dst 0.1.0` 骨架之上做**增量、可执行、聚焦编码**的旗舰级深化，对标 FoundationDB 确定性仿真、TigerBeetle VOPR、`madsim`/`turmoil` 与 Jepsen/Knossos。所有任务严格遵循「既有契约冻结、新能力旁路扩展」原则：

- **冻结即契约**：`src/dst/types.mbt`（`Task`/`Event`/`FaultKind`/`FaultPolicy`/`Scenario`/`SimStatus`/`SimResult`/`Sim`）、`rng.mbt`（`Rng`/`rng_new`/`Rng::next`/`Rng::next_below`）、`sim.mbt`（`Sim::new`/`Sim::step`/`Sim::inject_fault`/`run`/`replay`，含「任务按 id 升序、故障按 `(at_step, task_id)` 升序规范化、同种子 → 同调度序列 + 同终态」语义）、`release.mbt`（`release_info`/`release_info_with_gates`）的既有 `pub`/`pub(all)` 声明、字段、变体与运行时行为一律不动；`pkg.generated.mbti` 既有条目稳定、仅追加。既有 `prop_replay_test.mbt` 持续作为回归守卫。
- **枚举不扩容（关键取舍）**：`FaultKind`、`Event`、`SimStatus` 均为 `pub(all) enum`，向其追加变体会破坏下游穷尽匹配。故新故障类型与新事件类型**不修改既有枚举**，而由平行枚举 `NetFaultKind`（旗舰新增 `Partition`/`Reorder`/`Duplicate`/`ClockSkew`/`Byzantine` + `Crash`/`Delay`/`Drop` 语义等价项）与 `SimEvent`（带逻辑时间戳，含 `EvSend`/`EvDeliver`）在 DES 流水线使用；`SimStatus` 直接复用（DES 终态同为 `Completed`/`Failed(reason)`）。以 `NetFaultKind::of_legacy`/`FaultPolicyEx::of_legacy`/`DesScenario::of_legacy` 提供向后兼容桥。
- **复用而非重写**：DES 运行时沿用 dst 自有 `Rng`（xorshift64，三后端逐位一致），不在运行时 import `@infra_pbt`；全部新增属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`；发布元数据复用 `@release_meta`。
- **任务依赖顺序**：逻辑时钟 / DES 数据模型 / 事件队列 → 消息传递 / 故障 / 运行时不变量类型 / DES 核心循环 → 收缩 / 探索 / DPOR → 线性一致性 / 轨迹持久化 → demo / 基准 / 文档 / 发布，并设阶段检查点。
- **实现语言**：MoonBit（仅 `.mbt` / `.mbt.md` / `.md`，不写其他语言）。新增源文件位于 `src/dst/`，基准位于 `benches/dst_bench/`。
- **属性测试**：P1–P15 每条独立成一个 `*` 可选子任务，统一以 `@infra_pbt` 的 `holds_for_all`/`round_trip` 实现，每条至少 100 次迭代，标注 `Feature: dst, Property N`。差分一致类属性以「DES 流水线 vs 既有 `run`」（P1）、「`explore_bounded` vs `explore_dpor`」（P10/P11）作为对照 oracle；探索完整性（P9）以参考枚举器为 oracle。
- **native 前置约束**：凡在 native 后端运行测试、运行基准、或校验 `README.mbt.md` 可执行文档的环节，**必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（见各检查点、基准与文档任务，以及末尾 Notes）。

> **关于运行时不变量的落点说明**：按设计 4.6 / 4.10，`World::step` 在每个可观测状态求值场景附带的不变量是 DES 核心循环的内在组成，且收缩 / 探索 / DPOR 依赖「不变量违反 → `Failed`」作为失败来源。因此运行时不变量类型与每步求值集成（R7.1/7.2/7.3）与 DES 核心循环同波次落地；线性一致性检查（R7.4/7.5）与轨迹持久化（R8）构成后续阶段。`des_types`/`faults_ext`/`invariant`/`des_sim` 等同包文件相互引用，按波次增量落地，至 DES 核心循环波次整体编译通过。

---

## 任务（Tasks）

- [x] 1. 逻辑时钟与虚拟时间（`clock.mbt`，旁路新增）
  - [x] 1.1 实现逻辑时钟类型与时钟偏移
    - 在 `src/dst/clock.mbt` 新增 `pub typealias LogicalTime = UInt64`（统一以 `UInt64` 表示虚拟时间，保三后端整数语义一致且无溢出风险）与 `pub fn skewed_time(base : LogicalTime, offset : Int64) -> LogicalTime`（对基准时间施加确定性偏移，结果下钳到 0 以避免回退，供 `ClockSkew` 故障使用）
    - 以注释固化「(逻辑时间戳升序, 任务 id 升序, 确定性次序键升序)」全序约定，作为事件队列与 `World::step` 的处理顺序依据
    - 文件头注释标注 paper-to-code 出处（虚拟时间 / 离散事件仿真）与设计 4.1
    - _Requirements: 1.2, 1.3, 3.5_

  - [x]* 1.2 时钟单元测试（偏移下钳 / 正负偏移见证）
    - 在 `src/dst/clock_test.mbt` 覆盖 `skewed_time` 正偏移、负偏移下钳到 0、零偏移恒等的具体见证
    - _Requirements: 3.5_

- [x] 2. DES 数据模型（`des_types.mbt`，旁路新增）
  - [x] 2.1 实现 DES 富数据模型
    - 在 `src/dst/des_types.mbt` 新增 `pub(all) struct Message`（`id`/`payload`，`derive(Eq, Show)`）、`pub(all) enum SimEvent`（`EvScheduled`/`EvCompleted`/`EvFaulted`/`EvSend`/`EvDeliver`，均携带 `time : LogicalTime`，`derive(Eq, Show)`；变体名以 `Ev` 前缀与既有 `Event` 区分避免同包构造子歧义）、`pub(all) struct NodeApp`（`log`/`kv`，`derive(Eq, Show)`）、`pub struct Node`（`id`/`name`/`app`/`skew`，含运行态不派生）、`pub(all) enum Action`（`ActSend`/`ActAppend`，`derive(Eq, Show)`）、`pub struct Protocol`（`init`/`on_deliver`/`on_start` 函数值字段，不派生）、`pub struct DesScenario`（`tasks : Array[Task]` 复用既有 `Task`、`faults : Array[FaultPolicyEx]`、`invariants : Array[Invariant]`、`protocol`、`max_steps`，含函数值不派生）、`pub(all) struct DesResult`（`seed`/`trace`/`status : SimStatus` 复用既有终态/`finals : Array[(Int, NodeApp)]` 按 id 升序，`derive(Eq, Show)`）
    - 文件头注释标注设计 4.2 与「枚举不扩容、旁路平行扩展」取舍
    - _Requirements: 2.1, 2.2, 2.3, 12.4_

  - [x]* 2.2 DES 数据模型单元测试（构造 / `Eq`/`Show` 派生见证）
    - 在 `src/dst/des_types_test.mbt` 覆盖 `Message`/`SimEvent`/`NodeApp`/`Action`/`DesResult` 的构造、相等与可显示见证，确认与既有 `Event`/`SimStatus` 形态隔离
    - _Requirements: 2.1, 12.4_

- [x] 3. 事件队列（`event_queue.mbt`，旁路新增）
  - [x] 3.1 实现全序优先队列
    - 在 `src/dst/event_queue.mbt` 新增 `pub(all) struct QueuedEvent`（`time`/`task_id`/`order_key : UInt64`/`pending`，`derive(Eq, Show)`）、`pub(all) enum Pending`（`PDeliver`/`PWake`，`derive(Eq, Show)`）与 `pub struct EventQueue`（按全序 `(time, task_id, order_key)` 组织，不派生）
    - 实现 `EventQueue::new`、`EventQueue::is_empty`、`EventQueue::push`（返回新队列，不可变 API）、`EventQueue::pop_min`（取全序最小，空则 `None`），保证平局打破完全确定
    - 文件头注释标注设计 4.3 与全序约定（依赖 `clock.mbt` 的 `LogicalTime`）
    - _Requirements: 1.3, 2.1_

  - [x]* 3.2 事件队列单元测试（全序 `pop_min` / 平局打破见证）
    - 在 `src/dst/event_queue_test.mbt` 覆盖同时间戳按任务 id、再按 `order_key` 出队的全序见证，以及空队列 `pop_min` 返回 `None`
    - _Requirements: 1.3, 2.1_

- [x] 4. 检查点 —— 确保逻辑时钟、数据模型与事件队列测试通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行至此为止的测试套件；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. 丰富故障模型（`faults_ext.mbt`，旁路新增）
  - [x] 5.1 实现扩展故障类型、策略与向后兼容桥
    - 在 `src/dst/faults_ext.mbt` 新增 `pub(all) enum NetFaultKind`（`Crash`/`Delay(by~)`/`Drop`/`Partition(group~, until_step~)`/`Reorder`/`Duplicate`/`ClockSkew(offset~)`/`Byzantine`，`derive(Eq, Show)`；变体名独立避免同包歧义）与 `pub(all) struct FaultPolicyEx`（`at_step`/`task_id`/`kind`，`derive(Eq, Show)`）及 `FaultPolicyEx::new`
    - 实现向后兼容桥 `NetFaultKind::of_legacy`（`Crash→Crash`、`Delay→Delay(by=1)`、`Drop→Drop`）与 `FaultPolicyEx::of_legacy`，保持既有故障语义等价
    - 实现各故障的确定性效果辅助（供 `des_sim` 调用）：分区分组判定、重排比较规则、重复额外入队、时钟偏移施加、拜占庭矛盾内容生成（默认关闭、经场景显式启用），并以 `(at_step, task_id)` 升序规范化注入点
    - 文件头注释标注设计 4.5、`Crash`/`Delay`/`Drop` 语义保持与「枚举不扩容」取舍
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 12.4_

  - [x]* 5.2 故障语义单元测试（分区阻断 / 重复双投递 / 时钟偏移 / 重排 / `of_legacy` 等价）
    - 在 `src/dst/faults_ext_test.mbt` 经 `run_des` 观测代表性效果：`Partition` 生效区间内阻断跨组投递、`Duplicate` 产生两条独立 `EvDeliver`、`ClockSkew` 偏移目标节点事件时间戳、`Reorder` 调换投递顺序而不丢失消息；并断言 `of_legacy` 桥对 `Crash`/`Delay`/`Drop` 与既有语义等价
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 12.4_

  - [x]* 5.3 编写属性测试：故障注入点确定性与可重放
    - **Property 5: 故障注入点确定性与可重放（两次 `run_des` 的 `EvFaulted` 序列在「步序号、目标任务 id、故障类型」上完全一致，且以 `seed`+`trace` 调用 `replay_des` 逐字段复现）**
    - **Validates: Requirements 3.1, 3.7**
    - 文件 `src/dst/prop_fault_inject_test.mbt`，以 `@infra_pbt` 生成含故障场景与种子，`holds_for_all` ≥100 迭代

  - [x]* 5.4 编写属性测试：网络故障语义（分区隔离与消息重复）
    - **Property 6: 网络故障语义（`Partition` 生效区间内不存在跨组 `EvDeliver`；命中 `Duplicate` 的同一 `id` 消息恰对应两条独立 `EvDeliver`）**
    - **Validates: Requirements 3.2, 3.4**
    - 文件 `src/dst/prop_net_fault_test.mbt`，生成含分区 / 重复故障的收发场景，≥100 迭代

- [x] 6. 消息传递与因果序（`messaging.mbt`，旁路新增）
  - [x] 6.1 实现 `send` / `deliver` 语义与消息 id 分配
    - 在 `src/dst/messaging.mbt` 实现 `World::schedule_send(self, from, to, payload, after) -> World`（记录 `EvSend`，按「当前虚拟时间 + max(after, 1)」计算确定投递时间并入队 `PDeliver`，由 `World.msg_seq` 单调分配消息 id）与 `World::deliver(self, from, to, msg) -> World`（不受分区 / 丢弃阻断时记录 `EvDeliver` 并调用 `protocol.on_deliver` 推进目标节点）
    - 保证无丢弃 / 无分区下每条 `EvSend` 与一条 `EvDeliver` 按 id 一一配对、且 `EvDeliver.time` 严格大于 `EvSend.time`
    - 文件头注释标注设计 4.4（`World` 结构在 `des_sim.mbt`，本文件以同包扩展方法旁路提供）
    - _Requirements: 2.2, 2.3, 2.4_

  - [x]* 6.2 消息传递单元测试（发送—投递配对 / 投递晚于发送）
    - 在 `src/dst/messaging_test.mbt` 覆盖单次发送产生确定投递时间、`EvDeliver.time > EvSend.time`、消息 id 单调分配的见证
    - _Requirements: 2.2, 2.3, 2.4_

  - [x]* 6.3 编写属性测试：因果序保持
    - **Property 3: 因果序保持（不含 `Drop`/`Partition` 的收发场景中，每条 `EvSend` 恰与一条 `EvDeliver` 按 `id` 一一对应，且每对 `EvDeliver` 逻辑时间戳严格大于 `EvSend`）**
    - **Validates: Requirements 2.2, 2.4, 2.6**
    - 文件 `src/dst/prop_causal_test.mbt`，生成无丢弃 / 无分区的随机消息收发场景，≥100 迭代

- [x] 7. 运行时不变量类型与每步求值（`invariant.mbt`，旁路新增）
  - [x] 7.1 实现不变量类型与求值辅助
    - 在 `src/dst/invariant.mbt` 新增 `pub struct Invariant`（`name : String`/`check : (World) -> Bool` 函数值，不派生）与 `Invariant::new(name, check)`，并实现求值辅助 `eval_invariants(world, invs) -> String?`（任一不变量为假时返回「不变量 `<name>` 于逻辑时间 `<t>` 被违反」原因，供 `World::step` 在每个可观测状态调用）
    - 文件头注释标注设计 4.10（`Invariant::check` 取 `World`，与 `des_sim.mbt` 的 `World` 同包相互引用）
    - _Requirements: 7.1, 7.2, 7.3_

  - [x]* 7.2 不变量单元测试（违反原因含名与时间戳）
    - 在 `src/dst/invariant_test.mbt` 覆盖恒假不变量令运行以 `Failed` 终止、原因字符串标识被违反不变量名称与逻辑时间戳的见证
    - _Requirements: 7.3_

  - [x]* 7.3 编写属性测试：不变量违反必检出
    - **Property 12: 不变量违反必检出（必然违反某附加不变量的场景，`run_des` 以 `Failed(reason)` 终止且 `reason` 标识被违反不变量名称与发生逻辑时间戳）**
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.6**
    - 文件 `src/dst/prop_invariant_test.mbt`，对随机场景附加按构造必被违反的不变量，≥100 迭代

- [x] 8. DES 核心循环（`des_sim.mbt`，旁路新增）
  - [x] 8.1 实现世界状态、核心循环、`run_des`/`replay_des` 与遗留桥
    - 在 `src/dst/des_sim.mbt` 新增 `pub struct World`（`rng : Rng` 复用 dst 自有随机源、`clock`/`step_no`/`nodes`/`queue`/`trace`/`msg_seq`，不派生）；实现 `World::new(seed, scenario)`（任务按 id 升序规范化 + 灌入 `on_start` 激励）、`World::step(self)`（取队首事件 → 注入命中故障 → 处理并调用 `deliver` 入队未来事件 → 经 `eval_invariants` 每步求值不变量 → 队空或达 `max_steps` 终止）
    - 实现 `run_des(seed, scenario) -> DesResult`（同种子 → 同执行）与 `replay_des(seed, trace) -> DesResult`（以轨迹为权威记录派生终态，逐字段复现），以及向后兼容桥 `DesScenario::of_legacy(scenario, protocol~, invariants~ = [])`（对「无消息、仅遗留故障」场景的任务选择复用与既有 `step` 相同的 `rng.next_below(待调度数)`，使两条流水线可差分对照）
    - 文件头注释标注设计 4.6、FoundationDB 确定性仿真追溯与规范化语义沿用
    - _Requirements: 1.1, 2.1, 2.5, 12.3, 12.4_

  - [x]* 8.2 DES 核心循环单元测试（取队首处理入队 / 终止 / `of_legacy` 差分 / `replay` 一致）
    - 在 `src/dst/des_sim_test.mbt` 覆盖核心循环推进、队空与达 `max_steps` 终止、`of_legacy` 提升场景的 DES 调度任务投影与既有 `run` 在同种子下任务序列一致、`replay_des` 与 `run_des` 逐字段一致的见证
    - _Requirements: 2.1, 2.5, 12.3_

  - [x]* 8.3 编写属性测试：同种子确定性
    - **Property 1: 同种子确定性（同 `seed` 与 `scenario` 两次 `run_des` 产出 `DesResult` 逐字段一致；对「无消息、仅遗留故障」场景，`of_legacy` 提升后的 `EvScheduled` 任务投影与既有 `run` 同种子下 `Scheduled` 任务序列一致）**
    - **Validates: Requirements 1.1, 1.4, 1.5, 12.3**
    - 文件 `src/dst/prop_determinism_test.mbt`，生成随机种子与场景，以既有 `run` 作差分对照，≥100 迭代

  - [x]* 8.4 编写属性测试：虚拟时间单调性与事件全序
    - **Property 2: 虚拟时间单调性与事件全序（`trace` 相邻事件逻辑时间戳单调不减；同一时间戳内相邻事件按「(任务 id 升序, 次序键升序)」非降，处理顺序严格遵循全序）**
    - **Validates: Requirements 1.2, 1.3, 1.6**
    - 文件 `src/dst/prop_time_order_test.mbt`，生成随机场景校验 `trace` 全序，≥100 迭代

  - [x]* 8.5 编写属性测试：仿真循环终止性
    - **Property 4: 仿真循环终止性（`run_des` 在有限步内终止，执行步数不超过 `max_steps`，终止时队空或达上限，不存在无限循环）**
    - **Validates: Requirements 2.5**
    - 文件 `src/dst/prop_termination_test.mbt`，生成随机场景与步数上限，≥100 迭代

- [x] 9. 检查点 —— 确保消息传递、故障、不变量与 DES 核心循环测试通过
  - 在三后端运行至此为止的全部单元测试与属性测试（P1–P6、P12，各 ≥100 迭代）；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. 失败用例收缩（`shrink.mbt`，旁路新增）
  - [x] 10.1 实现 delta-debugging 收缩与规模度量
    - 在 `src/dst/shrink.mbt` 新增 `pub fn DesScenario::size(self) -> Int`（任务数 + 故障数 + `max_steps`）、`pub enum ShrinkOutcome`（`Minimal(DesScenario)` / `NotFailing`）与 `pub fn shrink(seed, scenario, fails~ = default_fails) -> ShrinkOutcome`
    - 实现收缩算子（移除一个任务、移除一条故障策略、缩减 `max_steps`）的贪婪 ddmin 式流程：仅接受仍复现原失败的候选、丢弃任何转为 `Completed` 者，无更小失败候选时返回当前最小反例；输入本不失败则返回 `NotFailing`（不返回任意场景）；每次接受使 `size` 严格递减且有下界保证终止
    - 文件头注释标注设计 4.7、Zeller delta debugging 与 QuickCheck shrinking 追溯
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7_

  - [x]* 10.2 收缩单元测试（非失败输入返回 `NotFailing` / 各算子见证）
    - 在 `src/dst/shrink_test.mbt` 覆盖非失败场景返回 `NotFailing`、移除任务 / 移除故障 / 缩减 `max_steps` 三算子各自缩小反例的见证
    - _Requirements: 4.4, 4.5_

  - [x]* 10.3 编写属性测试：收缩保真
    - **Property 7: 收缩保真（对失败场景，`shrink` 返回 `Minimal(s')` 且 `run_des(seed, s')` 仍以 `Failed` 终止）**
    - **Validates: Requirements 4.1, 4.3, 4.6**
    - 文件 `src/dst/prop_shrink_fidelity_test.mbt`，生成使运行失败的随机场景，≥100 迭代

  - [x]* 10.4 编写属性测试：收缩终止与单调
    - **Property 8: 收缩终止与单调（`shrink` 有限步内终止，返回的 `s'` 满足 `size(s') <= size(scenario)`，且每次接受候选规模严格递减、有下界、最终不可再小）**
    - **Validates: Requirements 4.2, 4.4, 4.7**
    - 文件 `src/dst/prop_shrink_termination_test.mbt`，生成随机失败场景，≥100 迭代

- [x] 11. 有界穷尽交错探索（`explore.mbt`，旁路新增）
  - [x] 11.1 实现有界穷尽交错枚举
    - 在 `src/dst/explore.mbt` 新增 `pub typealias Schedule = Array[Int]`、`pub(all) struct ExploreReport`（`explored : Int` 覆盖可审计 / `failing : (UInt64, Array[SimEvent])?` 首个失败交错的可重放凭据，`derive(Eq, Show)`）与 `pub fn explore_bounded(seed, scenario, depth) -> ExploreReport`
    - 以 DFS 枚举深度 ≤ `depth` 的全部可达交错（每调度点的可运行集为当前全序最小时间层内可选事件，`Schedule` 记录每点选择下标），对每个交错执行一次 DES 并对终态 / 不变量求值；任一失败即记录可重放种子 + 轨迹；不修改既有 `run`/`run_des` 语义
    - 文件头注释标注设计 4.8
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x]* 11.2 探索单元测试（计数报告 / 失败交错可重放）
    - 在 `src/dst/explore_test.mbt` 覆盖 `explored` 计数与已知小场景期望值一致、`failing` 携带的 `seed`+`trace` 经 `replay_des` 复现失败的见证
    - _Requirements: 5.3, 5.4_

  - [x]* 11.3 编写属性测试：有界穷尽探索完整性
    - **Property 9: 有界穷尽探索完整性（`explore_bounded` 枚举的交错集合恰等于参考枚举器在该深度内的全部可达交错，不遗漏 / 不重复计数，`explored` 等于集合大小；失败交错经 `replay_des` 复现）**
    - **Validates: Requirements 5.1, 5.3, 5.5**
    - 文件 `src/dst/prop_explore_complete_test.mbt`，生成小规模场景与深度上界，以独立参考枚举器为 oracle，≥100 迭代

- [x] 12. DPOR 偏序约简（`dpor.mbt`，旁路新增）
  - [x] 12.1 实现依赖关系与动态偏序约简
    - 在 `src/dst/dpor.mbt` 实现 `pub fn depends(a : SimEvent, b : SimEvent) -> Bool`（作用于同一任务、或存在消息因果关联 / 读写同一节点状态者为依赖；作用于不同任务且无因果关联者为独立可交换）与 `pub fn explore_dpor(seed, scenario, depth) -> ExploreReport`
    - 沿单条执行前进，对每个转移维护回溯集，遇与已执行转移依赖的可交换事件时向最近相关调度点添加回溯点，仅枚举每个 Mazurkiewicz 迹等价类的代表交错；`ExploreReport` 结构与 `explore_bounded` 一致以便差分对照
    - 文件头注释标注设计 4.9、Flanagan & Godefroid 2005《Dynamic Partial-Order Reduction》追溯
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x]* 12.2 DPOR 单元测试（`depends` 分类样例）
    - 在 `src/dst/dpor_test.mbt` 覆盖同任务事件 / 同消息 `send`-`deliver` / 读写同节点判为依赖，不同任务无因果关联判为独立的具体见证
    - _Requirements: 6.2_

  - [x]* 12.3 编写属性测试：DPOR 可靠性
    - **Property 10: DPOR 可靠性（`explore_dpor` 与 `explore_bounded` 报告相同的「是否存在失败交错」结论，DPOR 对每个等价类至少探索一个代表、绝不漏报任一可被穷尽探索发现的失败）**
    - **Validates: Requirements 6.2, 6.3, 6.4, 6.5**
    - 文件 `src/dst/prop_dpor_sound_test.mbt`，生成小规模场景，以 `explore_bounded` 为对照，≥100 迭代

  - [x]* 12.4 编写属性测试：DPOR 约简有效性
    - **Property 11: DPOR 约简有效性（`explore_dpor(...).explored` 不超过 `explore_bounded(...).explored`）**
    - **Validates: Requirements 6.6**
    - 文件 `src/dst/prop_dpor_reduction_test.mbt`，生成小规模场景比较两者交错计数，≥100 迭代

- [x] 13. 检查点 —— 确保收缩、有界穷尽探索与 DPOR 测试通过
  - 在三后端运行至此为止的全部单元测试与属性测试（P7–P11，各 ≥100 迭代）；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. 线性一致性检查（`linearizability.mbt`，旁路新增）
  - [x] 14.1 实现 Wing & Gong 线性化点检查
    - 在 `src/dst/linearizability.mbt` 新增 `pub(all) enum OpKind`（`Invoke`/`Return`，`derive(Eq, Show)`）、`pub(all) struct OpEvent`（`proc`/`kind`/`op`/`arg`/`ret`/`time`，`derive(Eq, Show)`）、`pub typealias History = Array[OpEvent]`、`pub(all) struct RegisterModel`（`init`，`derive(Eq, Show)`）、`pub enum LinResult`（`Linearizable` / `NotLinearizable(conflict~ : Array[OpEvent])`）与 `pub fn is_linearizable(history, model) -> LinResult`
    - 以回溯搜索逐步选取一个其调用区间可线性化的已完成操作直至清空历史（保持实时先后序 + 满足顺序规约）；无法清空即非线性一致并报告导致冲突的操作（可选能力，`WHERE` 启用）
    - 文件头注释标注设计 4.10、Herlihy & Wing 1990 与 Wing & Gong 线性化点 / Jepsen-Knossos 追溯
    - _Requirements: 7.4, 7.5_

  - [x]* 14.2 线性一致性单元测试（一致 / 非一致历史各一例）
    - 在 `src/dst/linearizability_test.mbt` 覆盖一个可线性化历史返回 `Linearizable`、一个违反顺序规约历史返回 `NotLinearizable` 且 `conflict` 非空的见证
    - _Requirements: 7.4, 7.5_

  - [x]* 14.3 编写属性测试：线性一致性判定可靠性
    - **Property 13: 线性一致性判定可靠性（按构造生成的可线性化历史返回 `Linearizable`；按构造注入违反实时先后序或顺序规约的历史返回 `NotLinearizable(conflict)` 且 `conflict` 非空）**
    - **Validates: Requirements 7.4, 7.5**
    - 文件 `src/dst/prop_linearizable_test.mbt`，在寄存器 / 单键 KV 顺序规约下按构造生成两类历史，≥100 迭代

- [x] 15. 轨迹持久化与跨会话重放（`trace_codec.mbt`，旁路新增）
  - [x] 15.1 实现序列化 / 反序列化与 round_trip 适配
    - 在 `src/dst/trace_codec.mbt` 新增 `pub(all) enum CodecError`（`Malformed(reason~, pos~)`，`derive(Eq, Show)`）、`pub fn serialize_result(r : DesResult) -> String`（确定性、自描述行式文本，事件逐行编码）、`pub fn deserialize_result(s : String) -> Result[DesResult, CodecError]`（任一字段非法返回 `Malformed`，绝不返回部分构造值）与 round_trip 适配 `result_to_bytes(r) -> Bytes`/`result_of_bytes(b) -> DesResult?`（对接 `@infra_pbt.round_trip`）
    - 文件头注释标注设计 4.11
    - _Requirements: 8.1, 8.2, 8.3, 8.5_

  - [x]* 15.2 持久化单元测试（损坏输入报 `Malformed`）
    - 在 `src/dst/trace_codec_test.mbt` 覆盖格式非法 / 损坏文本返回携带原因与偏移的 `Malformed`、且不产生部分构造 `DesResult` 的见证
    - _Requirements: 8.5_

  - [x]* 15.3 编写属性测试：序列化往返
    - **Property 14: 序列化往返（对任意 `DesResult` `r`，`deserialize_result(serialize_result(r))` 返回 `Ok(r')` 且 `r'` 与 `r` 逐字段一致；等价地经 `result_to_bytes`/`result_of_bytes` 适配的 `@infra_pbt.round_trip` 成立）**
    - **Validates: Requirements 8.3, 8.6**
    - 文件 `src/dst/prop_codec_roundtrip_test.mbt`，以 `@infra_pbt.round_trip` 生成随机 `DesResult`，≥100 迭代

  - [x]* 15.4 编写属性测试：跨会话重放保真
    - **Property 15: 跨会话重放保真（`r = run_des(seed, scenario)` 经 `serialize_result` 持久化再 `deserialize_result` 还原为 `r'`，以 `r'.seed`+`r'.trace` 调用 `replay_des` 复现的 `DesResult` 其 `status` 与 `trace` 与 `r` 逐字段一致）**
    - **Validates: Requirements 8.4, 8.7**
    - 文件 `src/dst/prop_replay_persist_test.mbt`，生成随机运行结果，校验持久化—还原—重放闭环，≥100 迭代

- [x] 16. 检查点 —— 确保线性一致性与轨迹持久化测试通过
  - 在三后端运行至此为止的全部单元测试与属性测试（P13–P15，各 ≥100 迭代）；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 17. 多副本复制端到端 demo（`demo.mbt`，旁路新增）
  - [x] 17.1 实现多副本复制协议、场景、不变量与「发现—收缩—重放—校验」闭环
    - 在 `src/dst/demo.mbt` 实现 `replication_protocol(replicas) -> Protocol`（简化领导者广播 + 副本追加日志协议）、`demo_replication_scenario(replicas) -> DesScenario`（正常达成日志同步）、`demo_partition_crash_scenario() -> DesScenario`（注入网络分区 + 崩溃，必然违反一致性）与 `replica_consistency_invariant() -> Invariant`（已提交前缀在各副本一致）
    - 串起闭环：`demo_partition_crash_scenario` 经 `run_des` 产生违反一致性的失败运行 → `shrink` 收缩到仍触发同一不变量违反的最小反例 → 以最小反例 `seed`+`trace` 经 `replay_des` 复现同一失败终态 → 每步校验副本一致性并在违反时报告不变量名与逻辑时间戳；该 demo 同时供 `README.mbt.md` 文档与 `benches/dst_bench` 复用
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

  - [x]* 17.2 端到端 demo 单元测试（注入→失败→收缩→重放→校验闭环）
    - 在 `src/dst/demo_test.mbt` 断言：`demo_partition_crash_scenario` 触发副本一致性不变量违反并以 `Failed` 终止、`shrink` 产出仍触发同一违反的最小反例、`replay_des` 复现同一失败终态、违反报告含不变量名与逻辑时间戳
    - _Requirements: 9.2, 9.3, 9.4, 9.5_

- [x] 18. 性能基准（`benches/dst_bench/`，新增包）
  - [x] 18.1 创建基准包骨架
    - 新增 `benches/dst_bench/moon.pkg` 与 `benches/dst_bench/pkg.generated.mbti`，结构对齐既有 `benches/astar_bench`，声明对 `dst` 的依赖
    - _Requirements: 10.1_

  - [x] 18.2 实现五类工作负载基准、约简比、回归 guard 与工件
    - 在 `benches/dst_bench/dst_bench.mbt` 实现大规模场景生成与五类负载：`run_des`、`replay_des`、`explore_bounded`、`explore_dpor`、`shrink`；输出含机器标识、后端目标、场景规模与计时统计的 JSON / Markdown 工件至 `benches/results/`，并记录 DPOR 相对有界穷尽的交错数量约简比；接入 guard 与基线中位数比较、超声明容差给出可审计失败报告
    - 在基准文档 / 脚本注明：运行 native 基准前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`，并记录可复现运行命令与规模参数
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 19. 集成、文档与发布推进
  - [x] 19.1 同步公开接口签名文件
    - 重新生成并提交 `src/dst/pkg.generated.mbti`，追加全部新增 `pub` 声明（`LogicalTime`/`Message`/`SimEvent`/`NodeApp`/`Node`/`Action`/`Protocol`/`DesScenario`/`DesResult`/`QueuedEvent`/`Pending`/`EventQueue`/`NetFaultKind`/`FaultPolicyEx`/`World`/`ShrinkOutcome`/`Schedule`/`ExploreReport`/`Invariant`/`OpKind`/`OpEvent`/`History`/`RegisterModel`/`LinResult`/`CodecError` 及新增函数 / 方法），既有条目保持稳定不删改
    - _Requirements: 12.1, 12.2, 12.4_

  - [x] 19.2 扩充 `README.mbt.md` 可执行文档（能力 / 对标 / 边界）
    - 在 `src/dst/README.mbt.md` 串联虚拟时间与消息传递、丰富故障注入、收缩、探索与多副本 demo 的可运行示例（经 `moon test *.mbt.md` 验证），并补充 paper-to-code 追溯（FoundationDB 确定性仿真、Flanagan & Godefroid 2005 DPOR、Herlihy & Wing 1990 / Wing & Gong 线性一致性、Zeller delta debugging / QuickCheck shrinking、xorshift64）、与 FoundationDB simulation / TigerBeetle VOPR / `madsim`/`turmoil` / Jepsen-Knossos 的能力与模型对比、以及实现边界声明（纯内存确定性模型，不接入真实网络 / 真实时间 / 操作系统线程）
    - 注明：校验 native 后端可执行文档前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 9.6, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 13.3_

  - [x] 19.3 推进 SemVer 版本字符串
    - 在 `src/dst/release.mbt` 仅更新本方向版本号字符串（自 `0.1.0` 起按本次旗舰深化做次 / 主版本推进），保持 `release_info` / `release_info_with_gates` 语义不变
    - _Requirements: 13.5_

  - [x] 19.4 更新方向 CHANGELOG
    - 在 `src/dst/CHANGELOG.md` 追加本次旗舰深化的新增能力与 SemVer 版本条目
    - _Requirements: 13.5_

  - [x]* 19.5 既有 API 向后兼容回归测试
    - 在 `src/dst/compat_test.mbt` 补充回归断言：`Sim::new`/`Sim::step`/`Sim::inject_fault`/`run`/`replay`/`rng_new`/`Rng::next`/`Rng::next_below` 行为与 `0.1.0` 逐字段一致，既有 `Task`/`Event`/`FaultKind`/`FaultPolicy`/`Scenario`/`SimStatus`/`SimResult`/`Sim`/`Rng` 字段与派生语义不变，`run` 规范化语义（任务按 id 升序、故障按 `(at_step, task_id)` 升序、同种子 → 同调度序列 + 同终态）保持；既有 `prop_replay_test.mbt` 继续作为回归守卫
    - _Requirements: 12.1, 12.2, 12.3_

  - [x]* 19.6 发布门禁真值表测试
    - 在 `src/dst/release_test.mbt` 追加覆盖 `release_info_with_gates`：三后端测试 / 属性测试 / 可执行文档任一未过即阻止本方向进入 release-ready
    - _Requirements: 13.1, 13.2, 13.6_

- [x] 20. 最终检查点 —— 确保三后端全部测试与文档校验通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行全部单元测试、15 条属性测试（P1–P15，各 ≥100 迭代）与 `moon test *.mbt.md`；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。任一后端输出分歧即判失败；经 `release_info_with_gates` 确认本方向 release-ready。
  - Ensure all tests pass, ask the user if questions arise.

## 备注（Notes）

- 标记 `*` 的子任务为可选测试任务（单元 / 属性 / 集成 / 门禁），可为加速 MVP 跳过，但 P1–P15 属性测试是 Requirement 13.2 的质量门禁，发布前应全部补齐。
- 每个任务引用具体需求条款（`_Requirements: X.Y_`）以保证可追溯；每条属性子任务标注 `Property N` 与 `**Validates: Requirements X.Y**`，统一以 `@infra_pbt` 的 `holds_for_all`/`round_trip` 实现且每条 ≥100 迭代，标注 `Feature: dst, Property N`。
- **严格向后兼容**：`types.mbt`/`rng.mbt`/`sim.mbt`/`release.mbt`（除版本字符串）既有 `pub`/`pub(all)` 声明、字段、变体与运行时语义冻结；`FaultKind`/`Event`/`SimStatus` 枚举不扩容，新故障 / 新事件由平行枚举 `NetFaultKind`/`SimEvent` 旁路提供，并以 `NetFaultKind::of_legacy`/`FaultPolicyEx::of_legacy`/`DesScenario::of_legacy` 桥接；新能力一律以新增 `.mbt` 文件旁路扩展。
- **差分对照 oracle**：同种子确定性（P1）以 DES 流水线 vs 既有 `run` 对照；探索完整性（P9）以独立参考枚举器为 oracle；DPOR 可靠性 / 约简有效性（P10/P11）以 `explore_bounded` 为对照。
- **运行时不变量落点**：运行时不变量类型与每步求值（任务 7，R7.1/7.2/7.3）随 DES 核心循环落地（设计 4.6/4.10 中属 `World::step` 内在组成，且为收缩 / 探索 / DPOR 的失败来源）；线性一致性（任务 14，R7.4/7.5）属后续阶段。
- **native 前置**：凡涉及 native 后端测试、基准运行、`README.mbt.md` 文档校验的任务（含检查点任务 4、9、13、16、20，以及 18.2、19.2），均须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "3.1"] },
    { "id": 1, "tasks": ["1.2", "2.2", "3.2", "5.1"] },
    { "id": 2, "tasks": ["6.1", "7.1", "8.1"] },
    { "id": 3, "tasks": ["5.2", "5.3", "5.4", "6.2", "6.3", "7.2", "7.3", "8.2", "8.3", "8.4", "8.5", "10.1", "11.1"] },
    { "id": 4, "tasks": ["10.2", "10.3", "10.4", "11.2", "11.3", "12.1"] },
    { "id": 5, "tasks": ["12.2", "12.3", "12.4", "14.1", "15.1"] },
    { "id": 6, "tasks": ["14.2", "14.3", "15.2", "15.3", "15.4", "17.1"] },
    { "id": 7, "tasks": ["17.2", "18.1", "19.1", "19.2", "19.3", "19.4"] },
    { "id": 8, "tasks": ["18.2", "19.5", "19.6"] }
  ]
}
```
