# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Actor_Framework（方向十）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开 API（`ActorId`、`Mailbox[M]`、`ActorRef[M]` 及邮箱原语、`spawn`/`send`/`stop`/`reset_runtime`，以及确定性串行调度器 `Scheduler[S, M]`、`ActorOutcome[S]{Updated | Errored}`、`ActorStatus{Running | Stopped | Failed}` 与 `spawn`/`step`/`run_until_idle`/`state_of`/`status_of`/`is_running`/`pending`），并在其上扩展为一套对标 Erlang/OTP、Akka、Elixir、Pony 与 Actix 的旗舰级 actor 框架。

本框架是**纯内存确定性模型**：不接入真实并发、线程、网络或分布式，不耦合 `moonbitlang/async`，而以同步 `run`/`step` 驱动模拟消息循环。这一实现边界是刻意选择，目的是保证「三后端 `moon test` 全绿」与「同种子可重放」两条硬性质量门禁。

旗舰目标聚焦以下主线：

- **监督策略与监督树**：`OneForOne`/`OneForAll`/`RestForOne` 三种策略、每子 actor 的重启指令（`Restart`/`Stop`/`Escalate`）、时间窗内最大重启强度与升级、可嵌套的监督树，重启时按生命周期钩子重置状态。
- **生命周期钩子**：`pre_start`/`post_stop`/`pre_restart`/`post_restart`，并明确重启语义（默认丢弃当前消息、重置状态）。
- **请求-响应（ask）**：在既有 `tell`（`send`）之上新增携带关联 id 的请求-响应模式，关联 id 唯一、响应匹配请求，超时/无响应建模为确定性结果。
- **行为切换（become / unbecome）**：以行为栈 push/pop 在运行时切换消息处理行为，切换后续消息按新行为处理。
- **消息暂存（stash / unstash）**：暂存当前不可处理的消息，行为切换后恢复处理并保持相对顺序。
- **死亡监视（death watch）**：`watch`/`unwatch`，被监视 actor 终止时向监视者投递 `Terminated` 通知。
- **路由器（router）**：`round-robin`、`broadcast`、一致性哈希三种路由策略把消息分发到一组 worker actor。
- **有界邮箱与背压**：容量上限邮箱，满时按策略（丢弃最新/丢弃最旧/拒绝）处理，确定且可观测。
- **确定性调度与重放**：以种子驱动的调度顺序探索（复用确定性 `Rng` 思路），同种子产生同处理序列、可重放。
- **性能基准**：`benches/` 覆盖高频 send、大量 actor 调度、ask 往返、路由分发、监督重启，含回归 guard。
- **可解释性**：paper-to-code 可追溯（Hewitt 1973、Agha 1986《Actors》、Erlang/OTP 监督原则、Akka 文档），与 Erlang/OTP、Akka、Elixir、Pony、Actix 的监督/邮箱/ask 模型对比，并显式声明实现边界。
- **端到端示例**：一个贯穿文档与基准的工作池场景（router 分发任务、worker 注入错误触发 `OneForOne` 重启、`watch` 收到 `Terminated`、`ask` 取回结果）。
- **质量门禁**：完整属性测试、三后端一致性、`README.mbt.md` 可执行文档扩充、独立 SemVer 推进与发布就绪门禁。

本规格承袭仓库统一质量基线（见 Requirement 15），复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。新增能力一律以**旁路新增的平行类型**承载，既有 `pub(all)` 类型 `ActorId`/`Mailbox[M]`/`ActorRef[M]`/`ActorOutcome[S]`/`ActorStatus` 不扩容（见 Requirement 14）。

---

## 术语表（Glossary）

- **Actor_Framework**：本方向的 actor 框架系统（子包 `src/actor`），是本文档所有验收标准的主体系统。
- **actor**：拥有私有状态、唯一标识与邮箱、只通过消息通信的并发计算单元；本框架以同步串行调度模拟其行为。
- **ActorId**：进程内 actor 的唯一标识，由单调递增的 `Int` 承载（既有 `pub(all) struct`）。
- **Mailbox[M]**：单个 actor 的消息队列，确定性内存 FIFO 实现（既有 `pub(all) struct`，含 `enqueue`/`dequeue`/`peek`/`is_empty`/`length`/`close`/`is_closed`）。
- **ActorRef[M]**：`spawn` 返回的、可向 actor 投递消息的引用句柄（既有 `pub(all) struct`，含 `id` 与 `mailbox`）。
- **ActorOutcome[S]**：actor 处理一条消息后的结果枚举，`Updated(S)`（正常更新状态）或 `Errored(String)`（未捕获错误信号），既有 `pub(all) enum`。
- **ActorStatus**：actor 的生命周期状态枚举，`Running`/`Stopped`/`Failed(String)`，既有 `pub(all) enum`。
- **Scheduler[S, M]**：确定性串行调度器，以 `step`/`run_until_idle` 驱动一组 actor 的消息循环（既有 `pub struct`）。
- **tell / send**：单向「即发即忘」的消息投递（既有 `ActorRef::send`），不期待响应。
- **ask**：携带关联 id 的请求-响应交互；请求方投递请求并以确定性方式获取匹配的响应或超时结果。
- **关联 id（Correlation Id）**：唯一标识一次 ask 交互的标记，用于把响应匹配回对应的请求。
- **AskResult**：一次 ask 交互的确定性结果，`Replied(R)`（收到匹配响应）或 `Timeout`（在给定步数预算内未收到响应）的平行类型。
- **supervisor（监督者）**：负责监视其子 actor、在子 actor 失败时按监督策略与重启指令做出处置的 actor。
- **child（子 actor）**：被某个 supervisor 监督的 actor。
- **监督策略（Supervision Strategy）**：决定一个子 actor 失败时影响范围的策略，取值 `OneForOne`/`OneForAll`/`RestForOne`。
- **OneForOne**：子 actor 失败时仅对该失败子 actor 应用重启指令，其兄弟不受影响。
- **OneForAll**：任一子 actor 失败时对其全部兄弟（含失败者）应用重启指令。
- **RestForOne**：子 actor 失败时对该失败者及其后（按启动顺序在其之后启动）的全部子 actor 应用重启指令。
- **重启指令（Directive）**：对失败子 actor 的处置，`Restart`（重置状态后继续）/`Stop`（永久终止）/`Escalate`（将失败上抛给上层 supervisor）。
- **最大重启强度（Max Restart Intensity）**：在给定逻辑时间窗内允许的最大重启次数；超过该阈值则按策略升级（escalate）或停止。
- **逻辑时钟（Logical Clock）**：以调度步数（step count）度量的确定性时间基准，用于判定重启强度时间窗。
- **监督树（Supervision Tree）**：supervisor 可监督 supervisor 形成的树形监督结构。
- **生命周期钩子（Lifecycle Hooks）**：`pre_start`（启动前）/`post_stop`（停止后）/`pre_restart`（重启前）/`post_restart`（重启后）四个回调。
- **重启（Restart）**：将失败 actor 恢复为可运行状态的过程：默认丢弃当前触发失败的消息、调用 `pre_restart`、以初始状态重置、调用 `post_restart`，随后继续处理后续消息。
- **行为（Behavior）**：actor 当前生效的消息处理函数。
- **行为栈（Behavior Stack）**：以栈结构组织的行为序列，`become` 压入新行为，`unbecome` 弹出回到前一行为。
- **become / unbecome**：运行时切换 actor 处理行为的操作；`become(b)` 使后续消息由 `b` 处理，`unbecome()` 恢复到前一行为。
- **stash / unstash**：`stash` 把当前消息暂存到暂存缓冲；`unstash`（或 `unstash_all`）把暂存消息按原相对顺序重新放回邮箱待处理。
- **死亡监视（Death Watch）**：`watch(target)` 登记对 `target` 终止的监视；`unwatch(target)` 撤销监视。
- **Terminated**：被监视 actor 终止（停止或失败）时向其监视者投递的通知消息，携带终止者的 `ActorId` 与终止原因。
- **路由器（Router）**：把消息按路由策略分发到一组 worker actor 的构造。
- **路由策略（Routing Strategy）**：`RoundRobin`（轮询）/`Broadcast`（广播给全部 worker）/`ConsistentHash`（按消息键的一致性哈希定位 worker）。
- **worker（工作 actor）**：被路由器分发消息的目标 actor 之一。
- **有界邮箱（Bounded Mailbox）**：带容量上限的邮箱。
- **背压策略（Backpressure Policy）**：有界邮箱满时对新消息的处置，`DropNewest`（丢弃最新）/`DropOldest`（丢弃最旧）/`Reject`（拒绝并返回可观测的拒绝信号）。
- **确定性重放（Deterministic Replay）**：以同一调度种子重复执行得到逐步一致的处理序列的能力。
- **调度种子（Scheduling Seed）**：驱动确定性 `Rng` 进而决定就绪 actor 选择顺序的整型种子。
- **处理序列（Processing Trace）**：一次运行中按发生顺序记录的「actor id × 被处理消息」事件序列。
- **朴素实现 / 参照实现（Reference Implementation）**：对某能力以最直接方式实现、用作差分一致性比对基准的版本。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：监督策略与监督树

**用户故事（User Story）：** 作为构建可靠 actor 系统的开发者，我想要 `OneForOne`/`OneForAll`/`RestForOne` 三种监督策略与可嵌套的监督树，以便我能按业务关系控制子 actor 失败时的影响范围。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 提供以平行类型表达的监督策略 `OneForOne`、`OneForAll`、`RestForOne`，并允许在派生 supervisor 时为其子 actor 指定其一。
2. WHEN 一个子 actor 在 `OneForOne` 策略下失败，THE Actor_Framework SHALL 仅对该失败子 actor 应用其重启指令，且其兄弟子 actor 的状态与生命周期状态保持不变。
3. WHEN 一个子 actor 在 `OneForAll` 策略下失败，THE Actor_Framework SHALL 对该 supervisor 的全部子 actor（含失败者）应用重启指令。
4. WHEN 一个子 actor 在 `RestForOne` 策略下失败，THE Actor_Framework SHALL 对该失败子 actor 及其后（按启动顺序在其之后启动）的全部子 actor 应用重启指令，且其前启动的子 actor 不受影响。
5. WHERE supervisor 自身被另一 supervisor 监督，THE Actor_Framework SHALL 允许构建监督树，使下层 supervisor 的 `Escalate` 上抛由上层 supervisor 按其策略处置。
6. FOR ALL 由生成器产生的子 actor 集合与策略，THE Actor_Framework SHALL 保证在 `OneForOne` 下未失败兄弟 actor 的状态与状态机不被失败处置改变（兄弟隔离不变量，以 PBT 验证）。
7. FOR ALL 由生成器产生的、按已知顺序启动的子 actor 序列，THE Actor_Framework SHALL 保证 `RestForOne` 仅影响失败者及其后启动者、不影响其前启动者（影响范围不变量，以 PBT 验证）。

---

### Requirement 2：重启指令与最大重启强度升级

**用户故事（User Story）：** 作为防止故障循环的开发者，我想要每子 actor 的重启指令与时间窗内的最大重启强度，以便反复失败的 actor 能被升级或停止而不陷入无限重启。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 提供以平行类型表达的重启指令 `Restart`、`Stop`、`Escalate`，并允许为每个子 actor 配置其失败时采用的指令。
2. WHEN 子 actor 失败且其指令为 `Restart`，THE Actor_Framework SHALL 按生命周期钩子重启该 actor 并使其恢复为 `Running` 状态。
3. WHEN 子 actor 失败且其指令为 `Stop`，THE Actor_Framework SHALL 将该 actor 永久终止为 `Stopped` 状态且不再处理其后续消息。
4. WHEN 子 actor 失败且其指令为 `Escalate`，THE Actor_Framework SHALL 将该失败上抛给其 supervisor，由上层按其策略处置。
5. THE Actor_Framework SHALL 允许配置最大重启强度为「在 `window` 个逻辑时钟步内至多 `max_restarts` 次重启」。
6. IF 某子 actor 在配置的时间窗内的重启次数超过 `max_restarts`，THEN THE Actor_Framework SHALL 不再重启该 actor，而是升级该失败（按 `Escalate` 处置或将该 actor 停止为 `Stopped`）。
7. FOR ALL 由生成器产生的失败序列与重启强度配置，THE Actor_Framework SHALL 保证在任意 `window` 长度的逻辑时钟窗口内，对单个 actor 触发的重启次数不超过 `max_restarts`（重启强度上界不变量，以 PBT 验证）。

---

### Requirement 3：生命周期钩子与重启语义

**用户故事（User Story）：** 作为管理 actor 资源与状态的开发者，我想要 `pre_start`/`post_stop`/`pre_restart`/`post_restart` 钩子与明确的重启语义，以便我能在生命周期转换点初始化、清理并可预期地重置状态。

#### 验收标准（Acceptance Criteria）

1. WHEN 一个 actor 被派生，THE Actor_Framework SHALL 在处理其第一条消息之前调用一次该 actor 的 `pre_start` 钩子。
2. WHEN 一个 actor 因 `stop` 请求或 `Stop` 指令终止，THE Actor_Framework SHALL 在该 actor 停止后调用一次其 `post_stop` 钩子。
3. WHEN 一个 actor 被重启，THE Actor_Framework SHALL 先调用 `pre_restart`（携带触发失败的原因与当前消息）、再以初始状态重置、随后调用 `post_restart`，最后恢复 `Running` 状态。
4. WHEN 一个 actor 被重启，THE Actor_Framework SHALL 默认丢弃触发本次失败的当前消息，并从其邮箱中下一条消息继续处理。
5. WHEN 一个 actor 被重启，THE Actor_Framework SHALL 将其状态重置为派生时的初始状态，而不沿用失败前累积的状态。
6. FOR ALL 由生成器产生的初始状态与失败前的消息历史，THE Actor_Framework SHALL 保证重启后的 actor 状态等于「以初始状态为起点、不重放失败前消息」的状态（重启状态重置不变量，以 PBT 验证）。
7. FOR ALL 由生成器产生的生命周期转换序列，THE Actor_Framework SHALL 保证每个 actor 的 `pre_start` 至多被调用一次、且其调用先于该 actor 的任何消息处理（启动钩子顺序不变量，以 PBT 验证）。

---

### Requirement 4：请求-响应（ask）模式

**用户故事（User Story）：** 作为需要从 actor 获取结果的开发者，我想要在 `tell` 之上的 `ask` 请求-响应模式，以便我能投递请求并以确定性方式取回与该请求匹配的响应或超时结果。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 在保留既有 `send`（tell）语义不变的前提下，提供携带唯一关联 id 的 `ask` 交互入口。
2. WHEN 发起一次 `ask`，THE Actor_Framework SHALL 为该次交互分配一个在本运行内唯一的关联 id。
3. WHEN 被请求 actor 针对某关联 id 产生响应，THE Actor_Framework SHALL 将该响应作为 `Replied` 结果匹配回携带相同关联 id 的发起请求。
4. IF 在配置的步数预算内未收到匹配某关联 id 的响应，THEN THE Actor_Framework SHALL 将该次 `ask` 结果确定性地判定为 `Timeout`。
5. THE Actor_Framework SHALL 保证一个 `ask` 关联 id 的响应至多被消费一次，且不会被匹配到其它关联 id 的请求。
6. FOR ALL 由生成器产生的并发 ask 请求集合，THE Actor_Framework SHALL 保证每个收到的响应恰好匹配其原始请求的关联 id（响应-请求匹配唯一性不变量，以 PBT 验证）。
7. FOR ALL 由生成器产生的 ask 交互序列，THE Actor_Framework SHALL 保证同一运行内分配的关联 id 两两不同（关联 id 唯一性不变量，以 PBT 验证）。

---

### Requirement 5：行为切换（become / unbecome）

**用户故事（User Story）：** 作为为有状态协议建模的开发者，我想要 `become`/`unbecome` 行为切换，以便 actor 能在运行时改变其后续消息的处理方式。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 以行为栈承载 actor 的处理行为，初始行为为派生时给定的处理函数。
2. WHEN 一个 actor 执行 `become(b)`，THE Actor_Framework SHALL 将 `b` 压入行为栈并使其后续消息由 `b` 处理。
3. WHEN 一个 actor 执行 `unbecome()` 且行为栈深度大于一，THE Actor_Framework SHALL 弹出栈顶行为并使其后续消息由前一行为处理。
4. IF 一个 actor 在行为栈仅含初始行为时执行 `unbecome()`，THEN THE Actor_Framework SHALL 保持当前行为不变（不弹空初始行为）。
5. WHEN 一个 actor 被重启，THE Actor_Framework SHALL 将其行为栈重置为仅含初始行为。
6. FOR ALL 由生成器产生的消息序列与行为切换序列，THE Actor_Framework SHALL 保证每条消息由其被处理时刻的栈顶行为处理（当前行为生效不变量，以 PBT 验证）。
7. FOR ALL 由生成器产生的 `become`/`unbecome` 配对序列，THE Actor_Framework SHALL 保证「`become(b)` 紧随 `unbecome()`」后行为栈恢复为操作前的状态（行为栈往返不变量，以 PBT 验证）。

---

### Requirement 6：消息暂存（stash / unstash）

**用户故事（User Story）：** 作为处理「当前阶段尚不可处理的消息」的开发者，我想要 `stash`/`unstash`，以便我能暂存这些消息并在行为切换后按原顺序恢复处理。

#### 验收标准（Acceptance Criteria）

1. WHEN 一个 actor 对当前消息执行 `stash`，THE Actor_Framework SHALL 将该消息追加到该 actor 的暂存缓冲而不立即处理。
2. WHEN 一个 actor 执行 `unstash_all`，THE Actor_Framework SHALL 将暂存缓冲中的全部消息按其暂存时的相对顺序重新置于邮箱待处理消息之前。
3. WHILE 消息处于暂存缓冲，THE Actor_Framework SHALL 不将其计入「邮箱为空即挂起」的就绪判定，使仅含暂存消息的 actor 不被错误唤醒处理这些消息。
4. WHEN 一个 actor 被重启或停止，THE Actor_Framework SHALL 清空该 actor 的暂存缓冲。
5. FOR ALL 由生成器产生的消息序列与 stash/unstash 操作序列，THE Actor_Framework SHALL 保证 `unstash_all` 后这些被暂存消息的相对处理顺序与其暂存时的相对顺序一致（暂存保序不变量，以 PBT 验证）。

---

### Requirement 7：死亡监视（death watch）

**用户故事（User Story）：** 作为需要感知依赖 actor 生命周期的开发者，我想要 `watch`/`unwatch` 与 `Terminated` 通知，以便我能在被依赖 actor 终止时做出反应。

#### 验收标准（Acceptance Criteria）

1. WHEN 一个 actor 对目标 actor 执行 `watch(target)`，THE Actor_Framework SHALL 登记该监视关系。
2. WHEN 一个被监视的 target 终止（停止或失败），THE Actor_Framework SHALL 向其每个监视者投递一条 `Terminated` 通知，携带 target 的 `ActorId` 与终止原因。
3. WHEN 一个 actor 对目标执行 `unwatch(target)`，THE Actor_Framework SHALL 撤销该监视关系，使该目标其后的终止不再向该监视者投递 `Terminated`。
4. IF 一个 actor 对一个已经终止的 target 执行 `watch`，THEN THE Actor_Framework SHALL 仍向该监视者投递一条携带该 target 标识与原因的 `Terminated` 通知。
5. THE Actor_Framework SHALL 对同一监视者与同一 target 的一次终止至多投递一条 `Terminated` 通知。
6. FOR ALL 由生成器产生的监视关系集合与终止序列，THE Actor_Framework SHALL 保证每个在终止时仍处于监视状态的监视者恰好收到一条对应该 target 的 `Terminated` 通知（终止通知必达且不重复不变量，以 PBT 验证）。

---

### Requirement 8：路由器（router）

**用户故事（User Story）：** 作为需要把负载分发到一组 worker 的开发者，我想要 `round-robin`、`broadcast` 与一致性哈希三种路由策略，以便我能按需均衡、广播或按键稳定地分发消息。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 提供以平行类型表达的路由策略 `RoundRobin`、`Broadcast` 与 `ConsistentHash`，并允许以一组 worker actor 构造路由器。
2. WHEN 一个 `RoundRobin` 路由器接收连续消息，THE Actor_Framework SHALL 按固定循环顺序把每条消息分发给下一个 worker。
3. WHEN 一个 `Broadcast` 路由器接收一条消息，THE Actor_Framework SHALL 把该消息分发给其全部 worker 各一份。
4. WHEN 一个 `ConsistentHash` 路由器接收携带路由键的消息，THE Actor_Framework SHALL 依据该键的一致性哈希把消息分发给确定的 worker。
5. WHILE 一个 `ConsistentHash` 路由器的 worker 集合保持不变，THE Actor_Framework SHALL 把携带相同路由键的消息始终分发给同一个 worker。
6. FOR ALL 由生成器产生的消息序列与 worker 数量，THE Actor_Framework SHALL 保证 `Broadcast` 路由后每个 worker 收到的消息条数等于输入消息条数（广播全达不变量，以 PBT 验证）。
7. FOR ALL 由生成器产生的、长度为 worker 数整数倍的消息序列，THE Actor_Framework SHALL 保证 `RoundRobin` 路由后各 worker 收到的消息条数相等（轮询均衡不变量，以 PBT 验证）。
8. FOR ALL 由生成器产生的路由键序列，THE Actor_Framework SHALL 保证 `ConsistentHash` 对相同键的分发目标在 worker 集合不变时保持稳定（哈希分发稳定性不变量，以 PBT 验证）。

---

### Requirement 9：有界邮箱与背压

**用户故事（User Story）：** 作为防止内存无界增长的开发者，我想要带容量上限的邮箱与可选背压策略，以便我能在邮箱满时以确定且可观测的方式处置新消息。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 提供以平行类型表达的有界邮箱构造，可为 actor 配置容量上限与背压策略 `DropNewest`、`DropOldest` 或 `Reject`。
2. WHILE 一个有界邮箱未满，THE Actor_Framework SHALL 把新消息按 FIFO 入队，行为与既有无界邮箱一致。
3. WHEN 向一个已满的 `DropNewest` 邮箱投递新消息，THE Actor_Framework SHALL 丢弃该新消息并保持既有排队消息不变。
4. WHEN 向一个已满的 `DropOldest` 邮箱投递新消息，THE Actor_Framework SHALL 移除队首最旧消息并将新消息入队队尾。
5. WHEN 向一个已满的 `Reject` 邮箱投递新消息，THE Actor_Framework SHALL 拒绝该消息并返回可观测的拒绝信号，且不改变邮箱内容。
6. THE Actor_Framework SHALL 暴露可观测计数（如已入队、已丢弃、已拒绝条数），使背压处置可被检视。
7. FOR ALL 由生成器产生的容量、背压策略与投递序列，THE Actor_Framework SHALL 保证有界邮箱在任意时刻排队消息条数不超过其容量上限（容量上界不变量，以 PBT 验证）。
8. FOR ALL 由生成器产生的投递序列，THE Actor_Framework SHALL 保证「入队条数 + 丢弃条数 + 拒绝条数」等于投递总条数（背压计数守恒不变量，以 PBT 验证）。

---

### Requirement 10：确定性调度与重放

**用户故事（User Story）：** 作为需要复现 actor 系统执行的开发者，我想要以种子驱动的确定性调度与重放，以便同一种子总能产生同一处理序列以便调试与回归。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 提供以调度种子构造的确定性调度入口，复用确定性 `Rng` 决定就绪 actor 的选择顺序。
2. WHEN 以同一种子与同一初始 actor 系统执行两次，THE Actor_Framework SHALL 产生逐事件一致的处理序列（actor id 与被处理消息序列完全一致）。
3. THE Actor_Framework SHALL 提供记录一次运行处理序列的能力，使该序列可被检视与比对。
4. WHILE 以种子驱动调度，THE Actor_Framework SHALL 在每一步至多处理一个就绪 actor 的一条消息，保持既有串行处理不变量。
5. WHEN 邮箱无新消息产生且所有 actor 已停止或挂起，THE Actor_Framework SHALL 终止调度循环，得到有限长度的处理序列。
6. FOR ALL 由生成器产生的种子与 actor 系统，THE Actor_Framework SHALL 保证以同一种子的两次运行产生逐事件一致的处理序列（重放确定性不变量，以 PBT 验证）。

---

### Requirement 11：旗舰端到端示例 —— 受监督的工作池

**用户故事（User Story）：** 作为评估该框架能力的开发者，我想要一个贯穿文档与基准的工作池示例，以便我能看到路由分发、监督重启、死亡监视与 ask 在真实场景中的端到端协作。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 提供一个工作池示例，其中一个 supervisor 以某路由策略派生并监督一组 worker actor。
2. WHEN 该示例的 router 接收一批任务消息，THE Actor_Framework SHALL 按所选路由策略把任务分发给 worker 处理。
3. WHEN 某个 worker 在该示例中处理注入了错误的任务而失败，THE Actor_Framework SHALL 在 `OneForOne` 策略下仅重启该 worker，其它 worker 不受影响并继续处理。
4. WHEN 该示例中某 worker 终止，THE Actor_Framework SHALL 向监视该 worker 的协调者投递 `Terminated` 通知。
5. WHEN 该示例的客户端以 `ask` 取回某任务结果，THE Actor_Framework SHALL 返回与该请求关联 id 匹配的响应或确定性的超时结果。
6. THE Actor_Framework SHALL 使该示例作为 `README.mbt.md` 可执行文档的一部分通过 `moon test *.mbt.md` 编译并运行。
7. FOR ALL 由生成器产生的任务批次与单点注入失败，THE Actor_Framework SHALL 保证该工作池在 `OneForOne` 重启后最终完成所有可完成任务且未失败 worker 的处理结果不丢失（工作池韧性不变量，以 PBT 验证）。

---

### Requirement 12：性能基准（benches/）

**用户故事（User Story）：** 作为关心运行时性能的开发者，我想要可复现的基准证据与回归 guard，以便我能量化高频消息、海量 actor 调度、ask 往返、路由分发与监督重启的开销并防止回归。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 在 `benches/` 下提供 actor 基准包，覆盖高频 `send`、大量 actor 调度、ask 往返、路由分发与监督重启五类工作负载。
2. WHEN 运行基准，THE Actor_Framework SHALL 输出包含机器标识、后端目标、负载规模与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE Actor_Framework SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告（回归 guard）。
4. WHEN 运行 native 后端基准，THE Actor_Framework SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Actor_Framework SHALL 在基准文档中记录运行命令与负载参数，以保证基准可复现。

---

### Requirement 13：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个核心语义可追溯到源文献并与主流 actor 实现对比，以便我能理解设计依据、取舍与边界。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 在文档中将 actor 计算模型（消息传递、私有状态、串行处理）追溯到 Hewitt 1973 的 actor model 与 Agha 1986《Actors》。
2. THE Actor_Framework SHALL 在文档中将监督策略、重启指令与监督树追溯到 Erlang/OTP 的 supervision 原则。
3. THE Actor_Framework SHALL 在文档中将 ask、become/unbecome、stash/unstash、router、death watch 等能力与 Akka 文档中的对应概念对照说明。
4. THE Actor_Framework SHALL 在文档中提供与 Erlang/OTP、Akka、Elixir、Pony、Actix 在监督、邮箱与 ask 模型上的对比。
5. THE Actor_Framework SHALL 显式声明其实现边界：纯内存确定性模型，不接入真实并发、线程、网络或分布式，以同步 `step` 驱动模拟消息循环。
6. WHERE 本框架的语义与所对标实现存在差异，THE Actor_Framework SHALL 显式声明该差异及其理由，而非隐式留白。

---

### Requirement 14：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 与语义不变，以便我现有的 actor 代码在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 保留既有公开类型 `ActorId`、`Mailbox[M]`、`ActorRef[M]`、`ActorOutcome[S]`、`ActorStatus` 与 `Scheduler[S, M]` 的现有公开形状与语义，且不向既有 `pub(all)` 枚举/结构追加破坏性变体或字段。
2. THE Actor_Framework SHALL 保留既有函数 `spawn`、`reset_runtime`、`ActorRef::send`、`ActorRef::stop`、`ActorRef::pending` 及 `Scheduler::new`/`spawn`/`step`/`run_until_idle`/`state_of`/`status_of`/`is_running`/`pending` 的现有签名与行为。
3. THE Actor_Framework SHALL 保留既有核心语义：邮箱 FIFO、单 actor 一次处理一条消息的串行处理、空邮箱挂起、未捕获错误终止该 actor 并通知 supervisor 且不影响其他 actor、`stop` 在处理完当前消息后停止。
4. WHERE 新增能力需要扩展行为，THE Actor_Framework SHALL 以旁路新增的平行类型与新增 API 提供，而不破坏既有 API 的调用方。
5. THE Actor_Framework SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板，并复用 `@release_meta` 的发布元数据模型。
6. FOR ALL 由生成器产生的、仅使用既有 `spawn`/`send`/`stop` 与 `Scheduler` API 的消息序列，THE Actor_Framework SHALL 保证其处理结果与 `0.1.0` 骨架逐字段一致（向后兼容不变量，以 PBT 验证）。

---

### Requirement 15：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Actor_Framework SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Actor_Framework SHALL 为本规格的核心正确性属性（FIFO 顺序、串行处理、错误隔离、监督重启状态重置、重启强度上界、ask 匹配唯一、become 当前行为生效、stash 保序、watch 终止通知必达、路由分发完整、有界邮箱背压守恒、确定性重放、向后兼容）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE Actor_Framework SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖监督、ask、become/unbecome、stash、router、death watch、有界邮箱与受监督工作池端到端示例，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE Actor_Framework SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Actor_Framework SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE Actor_Framework SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
