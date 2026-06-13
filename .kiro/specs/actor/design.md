# 设计文档（Design Document）

## 引言（Introduction）

本设计文档对应 **Actor_Framework（方向十）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化方案，落地 `requirements.md` 的 15 条需求。本设计的根本立场是**增量深化、严格向后兼容**：不重写、不破坏已发布 `0.1.0` 骨架的任何公开 API，而在其旁路新增一套对标 Erlang/OTP、Akka、Elixir、Pony、Actix 的旗舰级 actor 能力。

### 设计目标与非目标

**目标**
- 在既有确定性串行调度骨架之上，新增：监督策略与监督树、重启指令与最大重启强度、生命周期钩子与重启语义、请求-响应（ask）、行为切换（become/unbecome）、消息暂存（stash/unstash）、死亡监视（death watch）、路由器（router）、有界邮箱与背压、确定性调度与重放、受监督工作池端到端示例、性能基准与回归 guard、paper-to-code 可追溯与开源对标。
- 所有新增能力以**旁路平行类型 + 新增 `.mbt` 文件**承载，既有 `pub(all)` 类型与 `Scheduler[S, M]` 形状/语义零改动。
- 全部核心语义以全称量化的正确性属性表达，复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`），每条属性 ≥100 次迭代，三后端（`wasm-gc`/`js`/`native`）逐位一致、可重放。

**非目标（实现边界，见 §实现边界）**
- 不接入真实并发、线程、网络或分布式；不耦合 `moonbitlang/async`。
- 不提供持久化、跨进程消息传输、远程 actor、热代码替换。

### 实现边界（Implementation Boundary，对应 R13.5）

本框架是**纯内存确定性模型（pure in-memory deterministic model）**，以**同步 `step` 驱动**模拟消息循环：

1. 不引入异步运行时与真实并发；所有「并发」语义以单线程确定性串行调度模拟。
2. 调度顺序由确定性 `Rng`（种子驱动）决定，**同种子 → 同处理序列 → 可重放**。
3. 失败一律以**显式枚举信号**（`ActorOutcome::Errored` / `OfferResult::Rejected` / `AskResult::Timeout`）表达，不使用 `raise`/异常跨后端传播，杜绝三后端行为分歧。
4. 该边界是刻意选择，目的是守住两条硬性质量门禁：**三后端 `moon test` 全绿** 与 **同种子可重放**。待 `moonbitlang/async` 在 `moon.mod.json` 稳定登记后，可将同步驱动替换为真实异步消息循环，而对外契约（spawn/send/stop 与 FIFO/串行/隔离不变量）保持不变。


---

## 向后兼容契约（Backward-Compatibility Contract，对应 R14）

本设计把「向后兼容」提升为可审计的硬约束。下列既有公开资产**冻结（frozen）**，本次深化不得修改其形状或语义：

### 冻结的既有公开 API（来自 `pkg.generated.mbti`）

```moonbit
// —— 既有 pub(all) 类型：形状与变体冻结，不新增/不重排变体或字段 ——
pub(all) struct ActorId { value : Int } derive(Eq, Show)
pub(all) struct Mailbox[M] { mut items : Array[M]; mut closed : Bool }
pub(all) struct ActorRef[M] { id : ActorId; mailbox : Mailbox[M] }
pub(all) enum ActorOutcome[S] { Updated(S); Errored(String) }
pub(all) enum ActorStatus { Running; Stopped; Failed(String) } derive(Eq, Show)

// —— 既有 pub struct：字段与方法签名冻结 ——
pub struct Scheduler[S, M] { cells : Array[ActorCell[S, M]]; mut next_id : Int }

// —— 既有自由函数 / 方法：签名与行为冻结 ——
pub fn[S, M] spawn(S, (S, M) -> S) -> ActorRef[M]
pub fn reset_runtime() -> Unit
pub fn[M] ActorRef::send(Self[M], M) -> Unit
pub fn[M] ActorRef::stop(Self[M]) -> Unit
pub fn[M] ActorRef::pending(Self[M]) -> Int
pub fn[S, M] Scheduler::new() -> Self[S, M]
pub fn[S, M] Scheduler::spawn(Self[S, M], S, (S, M) -> ActorOutcome[S], supervisor? : (ActorId, String) -> Unit) -> ActorRef[M]
pub fn[S, M] Scheduler::step(Self[S, M]) -> Bool
pub fn[S, M] Scheduler::run_until_idle(Self[S, M]) -> Unit
pub fn[S, M] Scheduler::state_of(Self[S, M], ActorRef[M]) -> S?
pub fn[S, M] Scheduler::status_of(Self[S, M], ActorRef[M]) -> ActorStatus?
pub fn[S, M] Scheduler::is_running(Self[S, M], ActorRef[M]) -> Bool
pub fn[S, M] Scheduler::pending(Self[S, M], ActorRef[M]) -> Int
```

### 兼容策略

1. **不扩容既有枚举/结构**：监督、ask、行为栈、stash、router、有界邮箱等所需的全部新变体一律以**新类型**承载（如 `SupervisionStrategy`、`Directive`、`AskResult[R]`、`OfferResult` 等），绝不向 `ActorOutcome`/`ActorStatus`/`Mailbox`/`ActorRef`/`ActorId` 追加变体或字段。
2. **平行系统类型**：新增能力的统一驱动器是**全新的 `ActorSystem[S, M]`**（与既有 `Scheduler[S, M]` 平行共存），既有 `Scheduler` 保持纯净，旧代码继续可用。
3. **复用既有原语**：`ActorSystem` 内部复用既有 `ActorId`/`Mailbox[M]`/`ActorRef[M]` 的 FIFO 入队/出队原语与 `ActorOutcome[S]` 的 `Updated/Errored` 信号，避免语义重复。
4. **新增 `.mbt` 文件，不改既有文件主体**：除在 `release.mbt` 推进 SemVer、在 `README.mbt.md` 追加可执行示例外，既有 `types.mbt`/`actor.mbt`/`scheduler.mbt` 的公开主体保持不变。
5. **`.mbti` 快照即兼容门禁**：既有 `pkg.generated.mbti` 的既有条目不得回归（删除/改签名）；新增条目只增不改（R14 由 §correctness Property「向后兼容」验证）。


---

## 总体架构（Architecture）

### 分层视图

```
┌─────────────────────────────────────────────────────────────────────┐
│  可执行文档 / 端到端示例（README.mbt.md · demo.mbt：受监督工作池）         │  R11
├─────────────────────────────────────────────────────────────────────┤
│  能力层（平行新增，旁路既有 API）                                          │
│   supervision · lifecycle · ask · behavior · stash · deathwatch        │  R1~R7
│   router · bounded_mailbox                                              │  R8 R9
├─────────────────────────────────────────────────────────────────────┤
│  驱动层  ActorSystem[S, M]（确定性串行 + 种子驱动 + trace 记录）            │  R10
├─────────────────────────────────────────────────────────────────────┤
│  既有骨架（冻结）  Scheduler[S, M] · spawn/send/stop · Mailbox FIFO        │  R14
│   ActorId · ActorRef[M] · ActorOutcome[S] · ActorStatus                │
├─────────────────────────────────────────────────────────────────────┤
│  横切共享      @infra_pbt（Gen/Rng/holds_for_all）· @release_meta         │  R14.5 R15
└─────────────────────────────────────────────────────────────────────┘
```

设计原则：**上层只向下依赖**。能力层与驱动层均不反向依赖示例层；`@infra_pbt` 仅在 `for "test"` 作用域引入，不进入运行时产物；`@release_meta` 为零反向耦合的横切叶子包。

### 核心执行流水线（确定性串行循环）

`ActorSystem` 的单步 `step` 是整个框架的心脏，在既有 `Scheduler::step`（每步处理某一就绪 actor 的一条消息）之上扩展监督/钩子/暂存/监视语义：

```
step():
  1. 选取就绪 actor：以种子 Rng 在「Running 且邮箱非空」的 actor 中确定性选择一个（R10.1）
                     —— 无种子时退化为登记顺序，与既有 Scheduler 行为一致
  2. 取队首一条消息（FIFO，R10.4），交给当前栈顶 Behavior 处理（R5.6）
  3. 处理期间，handler 经 ActorContext 记录效果：become/unbecome/stash/unstash/watch/unwatch
  4. 处理结果：
       Updated(s)  → 更新状态；应用 ctx 记录的效果（行为栈、暂存、监视登记）
       Errored(e)  → 触发监督：按 supervisor 的策略 + 该子的 directive + 重启强度处置
  5. 终止处置时：投递 Terminated 给监视者（R7）；按 Restart/Stop/Escalate 改写生命周期
  6. 记录一条 trace 事件（actor id × 序号），供重放比对（R10.3）
  返回 true（有进展）/ false（已空闲：无 Running 且邮箱非空者，R10.5）
```

`run_until_idle` 反复 `step` 直至返回 `false`。由于 handler 不能凭空增殖无界消息、暂存缓冲在 `unstash_all` 时一次性回流，待处理消息总数随调度单调收敛，循环必然停机，得到**有限长度处理序列**（R10.5）。


### 文件划分（File Layout）

全部新增文件位于 `src/actor/`（横切叶子子包，不新增子目录），与既有文件平行共存：

| 文件 | 职责 | 主要类型/函数 | 覆盖需求 |
|------|------|---------------|----------|
| `types.mbt` *(既有，冻结)* | 核心数据模型 | `ActorId`/`Mailbox[M]`/`ActorRef[M]` | R14 |
| `actor.mbt` *(既有，冻结)* | spawn/send/stop 骨架 | `spawn`/`send`/`stop`/`reset_runtime` | R14 |
| `scheduler.mbt` *(既有，冻结)* | 确定性串行调度 | `Scheduler`/`ActorOutcome`/`ActorStatus` | R14 |
| `behavior.mbt` *(新增)* | 行为与处理上下文 | `Behavior[S,M]`/`ActorContext[S,M]` | R5 |
| `lifecycle.mbt` *(新增)* | 生命周期钩子与重启语义 | `LifecycleHooks[S]`/`TerminationReason` | R3 |
| `supervision.mbt` *(新增)* | 监督策略/指令/强度/监督树 | `SupervisionStrategy`/`Directive`/`RestartIntensity` | R1 R2 |
| `ask.mbt` *(新增)* | 请求-响应与关联 id | `CorrelationId`/`AskResult[R]`/`AskBroker[R]`/`ask` | R4 |
| `stash.mbt` *(新增)* | 消息暂存与保序回流 | `StashBuffer[M]` | R6 |
| `deathwatch.mbt` *(新增)* | 死亡监视与 Terminated | `WatchRegistry`/`Terminated` | R7 |
| `router.mbt` *(新增)* | 三种路由策略 | `RoutingStrategy`/`Router[M]` | R8 |
| `bounded_mailbox.mbt` *(新增)* | 有界邮箱与背压 | `BackpressurePolicy`/`BoundedMailbox[M]`/`OfferResult` | R9 |
| `system.mbt` *(新增)* | 旗舰驱动器（整合上述能力） | `ActorSystem[S,M]` | R1~R11 |
| `deterministic.mbt` *(新增)* | 种子调度与 trace 重放 | `TraceEvent`/`replay` 辅助 | R10 |
| `demo.mbt` *(新增)* | 受监督工作池端到端示例 | `worker_pool_demo` | R11 |
| `release.mbt` *(既有，仅推进 SemVer)* | 发布元数据 | `release_info`/`release_info_with_gates` | R15 |
| `README.mbt.md` *(既有，追加示例)* | 可执行文档 | 各能力 `mbt check` 块 | R11 R15 |
| `*_test.mbt`、`prop_*_test.mbt` *(新增)* | 单元测试与属性测试 | `holds_for_all` 谓词 | R15 |
| `benches/actor_bench/` *(新增)* | 性能基准 + 回归 guard | 五类负载 | R12 |


---

## 组件与接口（Components and Interfaces）

> 下列签名为**设计级（signature-level）接口契约**，描述类型形状与语义意图；实现细节在 tasks 阶段落地。所有签名遵循既有房屋风格（`pub fn[T] Type::method(...)`、`derive(Eq, Show)`、`?` 可选参数）。

### 1. 行为与处理上下文（behavior.mbt，R5）

为支持 `become/unbecome/stash/watch` 等运行时效果，新系统的处理函数接收一个 **`ActorContext`**（效果记录器）。处理函数把副作用记录进上下文，由 `ActorSystem` 在 `step` 末尾**确定性地**统一应用——避免隐藏可变状态导致的三后端分歧。返回值复用既有冻结枚举 `ActorOutcome[S]`（`Updated`/`Errored`），不新增结果类型。

```moonbit
/// 行为：一个 actor 当前生效的消息处理函数（包装为结构以入行为栈）。
pub(all) struct Behavior[S, M] {
  receive : (ActorContext[S, M], S, M) -> ActorOutcome[S]
}

pub fn[S, M] Behavior::new(
  receive : (ActorContext[S, M], S, M) -> ActorOutcome[S],
) -> Behavior[S, M]

/// 处理上下文：handler 经此记录效果；step 末尾由系统统一应用（确定性）。
pub struct ActorContext[S, M] {
  self_id : ActorId
  mut effects : Array[ContextEffect[S, M]]
}

/// handler 可记录的效果（私有变体集合，旁路新增，不污染既有枚举）。
priv enum ContextEffect[S, M] {
  PushBehavior(Behavior[S, M])   // become
  PopBehavior                    // unbecome
  StashCurrent                   // stash 当前消息
  UnstashAll                     // unstash_all
  Watch(ActorId)                 // 监视（适配器另存于注册表）
  Unwatch(ActorId)
}

pub fn[S, M] ActorContext::become_(self : ActorContext[S, M], next : Behavior[S, M]) -> Unit
pub fn[S, M] ActorContext::unbecome(self : ActorContext[S, M]) -> Unit
pub fn[S, M] ActorContext::stash(self : ActorContext[S, M]) -> Unit
pub fn[S, M] ActorContext::unstash_all(self : ActorContext[S, M]) -> Unit
pub fn[S, M] ActorContext::watch(self : ActorContext[S, M], target : ActorId, on_terminated : (ActorId, TerminationReason) -> M) -> Unit
pub fn[S, M] ActorContext::unwatch(self : ActorContext[S, M], target : ActorId) -> Unit
```

**行为栈语义**：每个 actor 内部维护 `Array[Behavior[S, M]]` 作为行为栈，初始仅含派生时给定行为（R5.1）。`become_` 压栈使后续消息由新栈顶处理（R5.2）；`unbecome` 在深度 > 1 时弹栈（R5.3），深度 == 1 时为**空操作**（不弹空初始行为，R5.4）；重启时行为栈重置为仅含初始行为（R5.5）。每条消息恒由其被处理时刻的栈顶行为处理（R5.6）。


### 2. 生命周期钩子与重启语义（lifecycle.mbt，R3）

```moonbit
/// 四个生命周期钩子；默认实现为恒等/空操作（以 new 的可选参数省略时取默认）。
pub(all) struct LifecycleHooks[S] {
  pre_start : (S) -> S            // 派生后、处理首条消息前调用一次（R3.1）
  post_stop : (S) -> Unit         // 停止后调用一次（R3.2）
  pre_restart : (S, String) -> Unit  // 重启前，携带 (当前状态, 失败原因)（R3.3）
  post_restart : (S) -> S         // 以初始状态为入参，返回重启后初始状态（R3.3）
}

pub fn[S] LifecycleHooks::identity() -> LifecycleHooks[S]   // 全默认（恒等/空）

/// 终止原因：投递给监视者的 Terminated 携带此原因（R7.2）。
pub(all) enum TerminationReason {
  StoppedNormally          // 因 stop 请求或 Stop 指令正常终止
  FailedWith(String)       // 因未捕获错误终止，附带原因
} derive(Eq, Show)
```

**重启语义（R3.3~R3.6）**，严格定义为有序步骤：

```
restart(cell, reason, failing_msg):
  1. 调用 pre_restart(cell.state, reason)                   // R3.3 步一
  2. 丢弃 failing_msg（默认不重放触发失败的当前消息）            // R3.4
  3. cell.state := post_restart(cell.init_state)            // R3.5 以初始状态重置
  4. 行为栈 := [initial_behavior]；暂存缓冲 := []             // R5.5 / R6.4
  5. cell.status := Running                                  // R3.3 步四
  // 随后从邮箱下一条消息继续处理
```

**关键不变量**：重启后状态等于「以初始状态为起点、不重放失败前消息」的状态（R3.6）。`pre_start` 至多调用一次，且严格先于该 actor 的任何消息处理（R3.7）。


### 3. 监督策略、重启指令与最大重启强度（supervision.mbt，R1 R2）

```moonbit
/// 监督策略：决定一个子失败时的影响范围（R1.1）。
pub(all) enum SupervisionStrategy {
  OneForOne     // 仅处置失败者（R1.2）
  OneForAll     // 处置全部兄弟，含失败者（R1.3）
  RestForOne    // 处置失败者及其后启动者（R1.4）
} derive(Eq, Show)

/// 重启指令：对失败子的处置（R2.1）。
pub(all) enum Directive {
  Restart       // 按钩子重启并恢复 Running（R2.2）
  Stop          // 永久终止为 Stopped（R2.3）
  Escalate      // 上抛给上层 supervisor（R2.4）
} derive(Eq, Show)

/// 最大重启强度：window 个逻辑时钟（step）内至多 max_restarts 次（R2.5）。
pub(all) struct RestartIntensity {
  max_restarts : Int
  window : Int
} derive(Eq, Show)

pub fn RestartIntensity::new(max_restarts : Int, window : Int) -> RestartIntensity

/// 监督者配置：策略 + 强度 + 每子的默认指令（每子也可单独覆盖）。
pub(all) struct SupervisorSpec {
  strategy : SupervisionStrategy
  intensity : RestartIntensity
  default_directive : Directive
}
```

**监督决策（在 `step` 检测到 `Errored` 时执行）**：

```
on_child_failed(sup, child, reason, failing_msg):
  1. 记录该 child 在逻辑时钟（当前 step 计数）上的一次重启请求
  2. IF 该 child 在最近 window 步内重启次数 ≥ max_restarts:       // R2.6 强度超限
        升级：按 child.directive==Escalate 上抛 sup 的 supervisor；
              否则将该 child 停止为 Stopped（不再重启）            // R2.7 上界保证
     ELSE 按 child.directive 处置：
        Restart  → 重启 child（lifecycle.restart）                // R2.2
        Stop     → 终止 child 为 Stopped                          // R2.3
        Escalate → 把失败上抛给 sup 的 supervisor，由其按策略处置    // R2.4 / R1.5
  3. 按 sup.strategy 扩展处置范围：
        OneForOne  → 仅 child                                    // R1.2
        OneForAll  → sup 的全部子（含 child）                      // R1.3
        RestForOne → child 及按启动顺序在其后的全部子              // R1.4
     范围内的兄弟按各自 directive 一并处置；范围外的子状态/生命周期不变（隔离）
```

**监督树（R1.5）**：`ActorSystem` 以 `Map[ActorId, SupervisorSpec]` 与 `parent : Map[ActorId, ActorId]`（子→supervisor）表达任意深度监督树。`Escalate` 沿 `parent` 链上抛，由上层 supervisor 按其策略处置；根 supervisor 的 `Escalate` 退化为停止根（确定性收敛）。


### 4. 请求-响应 ask（ask.mbt，R4）

ask 与既有 `send`（tell）正交：`send` 语义零改动（R4.1）。ask 引入一个**关联 id 注册表 `AskBroker[R]`**，把响应类型 `R` 与系统的消息类型 `M` 解耦（R 与 M 不必相同），从而在 MoonBit 类型系统下保持类型整洁。

```moonbit
/// 关联 id：唯一标识一次 ask 交互（R4.2）。
pub(all) struct CorrelationId { value : Int } derive(Eq, Show)

/// 一次 ask 的确定性结果（R4.3 / R4.4）。
pub(all) enum AskResult[R] {
  Replied(R)    // 收到匹配响应
  Timeout       // 预算步数内未收到响应
} derive(Eq, Show)

/// ask 关联注册表：分配唯一 id、登记响应、消费一次。
pub struct AskBroker[R] {
  mut next : Int
  pending : Map[Int, R]      // corr_id -> 响应
  consumed : Map[Int, Bool]  // 已消费标记（至多一次，R4.5）
}

pub fn[R] AskBroker::new() -> AskBroker[R]
pub fn[R] AskBroker::allocate(self : AskBroker[R]) -> CorrelationId       // 单调递增，运行内唯一（R4.2/R4.7）
pub fn[R] AskBroker::fulfill(self : AskBroker[R], id : CorrelationId, resp : R) -> Unit  // 被请求方回填响应
pub fn[R] AskBroker::poll(self : AskBroker[R], id : CorrelationId) -> AskResult[R]       // 消费一次

/// 系统级 ask：分配 id → 以 make_req(id) 投递请求 → 运行至多 budget 步 → poll。
pub fn[S, M, R] ask(
  system : ActorSystem[S, M],
  broker : AskBroker[R],
  target : ActorRef[M],
  make_req : (CorrelationId) -> M,
  budget : Int,
) -> AskResult[R]
```

**语义**：`ask` 先 `broker.allocate()` 得唯一 `id`，把 `make_req(id)`（嵌入 `id` 的请求消息）`send` 给目标，随后驱动系统至多 `budget` 步；被请求 actor 处理请求时调用 `broker.fulfill(id, resp)` 回填响应；最后 `broker.poll(id)`：命中则 `Replied(resp)`（R4.3），否则 `Timeout`（R4.4）。`poll` 标记 `consumed`，保证一个响应至多被消费一次且不串号（R4.5）。同一运行内 `allocate` 的 id 两两不同（R4.7）。

> **三后端确定性注记**：`pending`/`consumed` 以关联 id（`Int`）为键，读写均按 id 精确定位，不依赖 `Map` 的遍历顺序，故无后端差异。


### 5. 消息暂存 stash / unstash（stash.mbt，R6）

```moonbit
/// 暂存缓冲：保序追加、整体回流。每个 actor 一个。
pub struct StashBuffer[M] {
  mut items : Array[M]
}

pub fn[M] StashBuffer::new() -> StashBuffer[M]
pub fn[M] StashBuffer::push(self : StashBuffer[M], msg : M) -> Unit   // stash 当前消息（R6.1）
pub fn[M] StashBuffer::length(self : StashBuffer[M]) -> Int
pub fn[M] StashBuffer::is_empty(self : StashBuffer[M]) -> Bool
pub fn[M] StashBuffer::clear(self : StashBuffer[M]) -> Unit            // 重启/停止清空（R6.4）
/// 将暂存消息按原相对顺序置于邮箱待处理消息之前（R6.2）。
pub fn[M] StashBuffer::drain_to_front(self : StashBuffer[M], mailbox : Mailbox[M]) -> Unit
```

**语义**：`ctx.stash()` 把当前消息追加至该 actor 的 `StashBuffer`，本步不处理它（R6.1）。`ctx.unstash_all()` 在 `step` 末尾把缓冲全部消息**按暂存时相对顺序**插到邮箱队首之前（R6.2），随后清空缓冲。处于暂存缓冲的消息**不计入**「邮箱空即挂起」的就绪判定——仅含暂存消息（邮箱为空）的 actor 不会被错误唤醒去处理这些消息（R6.3）。重启或停止时清空缓冲（R6.4）。

**保序实现要点**：`drain_to_front` 以「先在邮箱前端插入暂存序列、再保留原邮箱消息」的方式拼接，使暂存消息的相对顺序与其入缓冲顺序逐位一致（R6.5）。

### 6. 死亡监视 death watch（deathwatch.mbt，R7）

```moonbit
/// 监视注册表：target -> 监视者及其 Terminated 适配器。
pub struct WatchRegistry[M] {
  // 以数组承载，保证遍历顺序确定（三后端一致）
  entries : Array[WatchEntry[M]]
}

priv struct WatchEntry[M] {
  target : ActorId
  watcher : ActorId
  on_terminated : (ActorId, TerminationReason) -> M   // watchWith 风格适配器
  mut active : Bool
}

pub fn[M] WatchRegistry::new() -> WatchRegistry[M]
pub fn[M] WatchRegistry::watch(self : WatchRegistry[M], watcher : ActorId, target : ActorId, on_terminated : (ActorId, TerminationReason) -> M) -> Unit  // R7.1
pub fn[M] WatchRegistry::unwatch(self : WatchRegistry[M], watcher : ActorId, target : ActorId) -> Unit  // R7.3
```

**语义**：`watch(target)` 登记监视关系（R7.1）。当 `target` 终止（`Stopped` 或 `Failed`）时，系统对每个仍 `active` 的监视者，以其适配器构造一条用户消息 `on_terminated(target_id, reason)` 投递到监视者邮箱（R7.2），随后将该条目置为非 `active`，保证同一监视者×同一终止**至多一条** Terminated（R7.5/R7.6）。`unwatch` 置条目非 `active`，使其后终止不再通知（R7.3）。对**已终止** target 执行 `watch`，系统立即投递一条携带该 target 标识与原因的 Terminated（R7.4）。

> Terminated 经**用户自定义适配器**映射为该监视者的消息类型 `M`（Akka `watchWith` 风格），避免向冻结的 `M`/`ActorOutcome` 注入系统消息变体——这是兼容约束下的关键设计取舍。


### 7. 路由器 router（router.mbt，R8）

```moonbit
/// 路由策略（R8.1）。
pub(all) enum RoutingStrategy {
  RoundRobin       // 轮询：按固定循环顺序（R8.2）
  Broadcast        // 广播：每条发给全部 worker 各一份（R8.3）
  ConsistentHash   // 一致性哈希：按路由键定位 worker（R8.4）
} derive(Eq, Show)

/// 路由器：以一组 worker 与策略构造。
pub struct Router[M] {
  strategy : RoutingStrategy
  workers : Array[ActorRef[M]]
  mut cursor : Int            // RoundRobin 游标
}

pub fn[M] Router::new(strategy : RoutingStrategy, workers : Array[ActorRef[M]]) -> Router[M]
/// 分发一条消息：RoundRobin/Broadcast 用此；ConsistentHash 需提供 key。
pub fn[M] Router::route(self : Router[M], msg : M) -> Unit
/// 携带路由键的分发（ConsistentHash 主入口；其它策略忽略 key）。
pub fn[M] Router::route_keyed(self : Router[M], key : String, msg : M) -> Unit
pub fn[M] Router::worker_for_key(self : Router[M], key : String) -> ActorId   // 可观测：键→worker
```

**语义**：`RoundRobin` 按 `cursor` 循环命中下一 worker（R8.2），长度为 worker 数整数倍时各 worker 收到条数相等（R8.7）。`Broadcast` 把消息复制到全部 worker，每 worker 收到条数等于输入条数（R8.3/R8.6）。`ConsistentHash` 以**确定性整数哈希**（FNV-1a over UTF-8 bytes）把 key 映射到排序后的哈希环节点，worker 集合不变时相同键稳定命中同一 worker（R8.4/R8.5/R8.8）。

> **三后端确定性注记**：哈希仅用整数运算，不用浮点；环节点按 `(hash, worker_index)` 全序排序，消除并列歧义，保证三后端一致。

### 8. 有界邮箱与背压（bounded_mailbox.mbt，R9）

`BoundedMailbox[M]` 是**平行于既有 `Mailbox[M]`** 的新类型（不修改 `Mailbox`）。

```moonbit
/// 背压策略（R9.1）。
pub(all) enum BackpressurePolicy {
  DropNewest   // 满时丢弃新消息（R9.3）
  DropOldest   // 满时移除队首最旧、新消息入队尾（R9.4）
  Reject       // 满时拒绝并返回可观测信号（R9.5）
} derive(Eq, Show)

/// 投递结果：可观测的背压信号（R9.5/R9.6）。
pub(all) enum OfferResult {
  Enqueued     // 已入队
  Dropped      // 被丢弃（DropNewest/DropOldest）
  Rejected     // 被拒绝（Reject）
} derive(Eq, Show)

pub struct BoundedMailbox[M] {
  capacity : Int
  policy : BackpressurePolicy
  mut items : Array[M]
  mut enqueued : Int    // 累计已入队（含被后续 DropOldest 挤出的）
  mut dropped : Int     // 累计已丢弃
  mut rejected : Int    // 累计已拒绝
}

pub fn[M] BoundedMailbox::new(capacity : Int, policy : BackpressurePolicy) -> BoundedMailbox[M]
pub fn[M] BoundedMailbox::offer(self : BoundedMailbox[M], msg : M) -> OfferResult  // 投递一条
pub fn[M] BoundedMailbox::dequeue(self : BoundedMailbox[M]) -> M?                   // FIFO 出队
pub fn[M] BoundedMailbox::length(self : BoundedMailbox[M]) -> Int
pub fn[M] BoundedMailbox::counts(self : BoundedMailbox[M]) -> (Int, Int, Int)       // (enqueued, dropped, rejected)
```

**语义**：未满时按 FIFO 入队，行为与无界 `Mailbox` 一致（R9.2）。满时：`DropNewest` 丢弃新消息、队列不变（R9.3）；`DropOldest` 移除队首、新消息入队尾（R9.4）；`Reject` 不改内容并返回 `Rejected`（R9.5）。任意时刻 `length ≤ capacity`（R9.7）；**计数守恒**：每次 `offer` 恰增加 `enqueued`/`dropped`/`rejected` 之一，故「入队 + 丢弃 + 拒绝 == 投递总数」（R9.8）。


### 9. 旗舰驱动器 ActorSystem（system.mbt，整合 R1~R11）

`ActorSystem[S, M]` 是承载全部新能力的**平行驱动器**，既有 `Scheduler[S, M]` 保持冻结、独立可用。

```moonbit
pub struct ActorSystem[S, M] {
  cells : Array[SupervisedCell[S, M]]   // 各 actor 的完整运行态（私有结构）
  supervisors : Map[Int, SupervisorSpec]
  parents : Map[Int, Int]               // 子 id -> supervisor id
  watches : WatchRegistry[M]
  trace : Array[TraceEvent]
  mut clock : Int                       // 逻辑时钟（step 计数），用于重启强度窗口
  mut rng : Rng?                        // 种子驱动调度；None 时退化为登记顺序
  mut next_id : Int
}

/// 无种子构造：就绪 actor 按登记顺序选取（与既有 Scheduler 行为对齐）。
pub fn[S, M] ActorSystem::new() -> ActorSystem[S, M]
/// 种子构造：以确定性 Rng 选取就绪 actor，支持重放（R10.1）。
pub fn[S, M] ActorSystem::with_seed(seed : UInt64) -> ActorSystem[S, M]

/// 派生 actor：行为 + 初始状态 + 可选钩子/监督者/指令/有界邮箱容量。
pub fn[S, M] ActorSystem::spawn(
  self : ActorSystem[S, M],
  init : S,
  behavior : Behavior[S, M],
  hooks? : LifecycleHooks[S],
  supervisor? : ActorRef[M],
  directive? : Directive,
  bounded? : (Int, BackpressurePolicy),
) -> ActorRef[M]

/// 把一组子置于某监督策略与强度之下（建立监督树节点）。
pub fn[S, M] ActorSystem::supervise(
  self : ActorSystem[S, M],
  supervisor : ActorRef[M],
  spec : SupervisorSpec,
  children : Array[ActorRef[M]],
) -> Unit

pub fn[S, M] ActorSystem::step(self : ActorSystem[S, M]) -> Bool          // 单步（确定性串行）
pub fn[S, M] ActorSystem::run_until_idle(self : ActorSystem[S, M]) -> Unit // 跑至空闲（R10.5）
pub fn[S, M] ActorSystem::trace_of(self : ActorSystem[S, M]) -> Array[TraceEvent]  // 处理序列（R10.3）

// 观测辅助（与既有 Scheduler 同名同义，便于迁移）
pub fn[S, M] ActorSystem::state_of(self : ActorSystem[S, M], r : ActorRef[M]) -> S?
pub fn[S, M] ActorSystem::status_of(self : ActorSystem[S, M], r : ActorRef[M]) -> ActorStatus?
pub fn[S, M] ActorSystem::is_running(self : ActorSystem[S, M], r : ActorRef[M]) -> Bool
pub fn[S, M] ActorSystem::restart_count(self : ActorSystem[S, M], r : ActorRef[M]) -> Int  // 观测重启次数
```

### 10. 确定性调度与重放（deterministic.mbt，R10）

```moonbit
/// 一次处理事件：actor id × 全局序号（可扩展记录消息摘要）。
pub(all) struct TraceEvent {
  actor : ActorId
  seq : Int
} derive(Eq, Show)

/// 重放校验：以同一种子与同一构造函数运行两次，比对 trace 是否逐事件一致。
pub fn[S, M] replay_consistent(
  seed : UInt64,
  build : (UInt64) -> ActorSystem[S, M],
) -> Bool
```

**语义**：`with_seed(seed)` 用 `@infra_pbt.Rng`（`rng_new(seed)` + `next_below`）在「`Running` 且邮箱非空」的就绪集合中确定性选取一个 actor 处理一条消息（R10.1）。每步至多处理一条（串行不变量，R10.4，复用既有 Property）。`trace_of` 暴露处理序列供检视与比对（R10.3）。`replay_consistent` 以同种子两次运行，断言 trace 逐事件一致（R10.2/R10.6）。当无 `Running` 且邮箱非空的 actor 时 `step` 返回 `false`，`run_until_idle` 停机，得有限 trace（R10.5）。


### 11. 端到端示例：受监督的工作池（demo.mbt，R11）

```moonbit
/// 工作池场景：coordinator 监督一组 worker；router 分发任务；
/// 注入失败触发 OneForOne 重启；coordinator watch worker；client 以 ask 取回结果。
pub fn worker_pool_demo(
  worker_count : Int,
  tasks : Array[Task],
  fault_at : Int?,          // 在第 fault_at 个任务注入一次失败（None 表示无失败）
  seed : UInt64,
) -> WorkerPoolReport

/// 可观测报告：完成任务数、各 worker 结果、重启次数、收到的 Terminated、ask 结果。
pub(all) struct WorkerPoolReport {
  completed : Int
  restarts : Int
  terminated_seen : Array[ActorId]
  ask_results : Array[AskResult[Int]]
} derive(Eq, Show)
```

**场景串联**：① `coordinator` 以某 `RoutingStrategy` 派生并监督 `worker_count` 个 worker（R11.1）；② router 把 `tasks` 分发给 worker（R11.2）；③ 某 worker 处理被注入错误的任务而 `Errored`，在 `OneForOne` 下仅该 worker 重启，其它 worker 不受影响继续处理（R11.3）；④ worker 终止时 coordinator 收到 `Terminated`（R11.4）；⑤ client 以 `ask` 取回某任务结果或确定性 `Timeout`（R11.5）。该示例同时作为 `README.mbt.md` 可执行文档块运行（R11.6）。**韧性不变量**：单点注入失败并 `OneForOne` 重启后，工作池最终完成所有可完成任务，且未失败 worker 的结果不丢失（R11.7）。

### 12. 性能基准与回归 guard（benches/actor_bench/，R12）

新增基准包 `benches/actor_bench/`，覆盖五类工作负载（R12.1）：

| 负载 | 度量 | 关联能力 |
|------|------|----------|
| 高频 `send` | 每秒入队/处理消息数 | R10 邮箱/调度 |
| 大量 actor 调度 | N actor × M 消息的 `run_until_idle` 耗时 | R10 |
| ask 往返 | 单次 ask 的 step 预算与吞吐 | R4 |
| 路由分发 | RoundRobin/Broadcast/ConsistentHash 分发耗时 | R8 |
| 监督重启 | 注入失败 → 重启恢复的开销 | R1~R3 |

基准输出含**机器标识、后端目标、负载规模与计时统计**的 JSON/Markdown 工件（R12.2），并与记入的基线中位数比较、超声明容差时给出可审计失败报告（回归 guard，R12.3）。基准文档记录运行命令与负载参数（R12.5）。**native 后端基准前须先执行**：

```bash
export LIBRARY_PATH=/usr/lib64:/usr/lib   # R12.4 / R15.4
```


---

## 数据模型（Data Models）

### 内部 actor 单元（私有，SupervisedCell）

`ActorSystem` 内部为每个 actor 维护一个**私有** `SupervisedCell[S, M]`（不公开、不影响 `.mbti` 兼容面），在既有 `ActorCell` 之外补齐新能力所需运行态：

```moonbit
priv struct SupervisedCell[S, M] {
  id : ActorId
  mailbox : Mailbox[M]                 // 复用既有 FIFO 邮箱原语
  bounded : BoundedMailbox[M]?          // 配置有界时启用（R9）
  mut state : S
  init_state : S                        // 重启基准（R3.5）
  mut behaviors : Array[Behavior[S, M]] // 行为栈（R5）
  stash : StashBuffer[M]                // 暂存缓冲（R6）
  hooks : LifecycleHooks[S]             // 生命周期钩子（R3）
  directive : Directive                 // 失败处置（R2）
  mut status : ActorStatus              // 复用既有生命周期枚举
  mut started : Bool                    // pre_start 是否已调用（R3.1/3.7）
  mut restart_times : Array[Int]        // 逻辑时钟上的重启时刻（强度窗口，R2.5~2.7）
}
```

### 发布元数据模型（复用 @release_meta，R15）

沿用既有 `release.mbt`：`release_info()` 返回 `@release_meta.DirectionRelease`，`release_info_with_gates(gates)` 经 `DirectionRelease::evaluate` 依质量门禁三要素（测试/证明谓词/可执行文档）聚合 `release_ready`（R15.6）。本次旗舰深化把 `actor_version` 自 `0.1.0` 推进（次版本或主版本），并更新 `src/actor/CHANGELOG.md`（R15.5）。

### 关键类型关系图

```
ActorSystem[S,M]
  ├── cells: Array[SupervisedCell[S,M]]
  │        ├── mailbox: Mailbox[M]            (既有，复用)
  │        ├── bounded: BoundedMailbox[M]?    (R9，新增平行类型)
  │        ├── behaviors: Array[Behavior[S,M]](R5)
  │        ├── stash: StashBuffer[M]          (R6)
  │        ├── hooks: LifecycleHooks[S]       (R3)
  │        └── status: ActorStatus            (既有，复用)
  ├── supervisors: Map[Int, SupervisorSpec]   (R1/R2)
  ├── parents: Map[Int, Int]                  (R1.5 监督树)
  ├── watches: WatchRegistry[M]               (R7)
  └── trace: Array[TraceEvent]                (R10.3)

AskBroker[R] (R4，独立于 ActorSystem，按需配合 ask 使用)
Router[M]    (R8，以一组 ActorRef[M] 构造)
```

---

## 错误处理（Error Handling）

本方向严格沿用仓库统一的**显式枚举信号**风格，全程不使用 `raise`/异常跨后端传播，保证三后端逐位一致：

| 失败/边界场景 | 信号载体 | 处置 | 需求 |
|---------------|----------|------|------|
| actor 处理期未捕获错误 | `ActorOutcome::Errored(String)` | 终止该 actor → 触发监督 → 通知监视者 | R2.x R7 |
| 重启强度超限 | 内部判定（`restart_times` × `window`） | 升级（Escalate 上抛）或停止 | R2.6/2.7 |
| ask 超时 | `AskResult::Timeout` | 确定性返回，不阻塞、不抛错 | R4.4 |
| 有界邮箱满 | `OfferResult::Dropped`/`Rejected` | 按背压策略处置并计数 | R9.3~9.5 |
| `unbecome` 弹空 | 空操作（保持当前行为） | 不报错、不弹空初始行为 | R5.4 |
| `watch` 已终止 target | 立即投递一条 Terminated | 不报错 | R7.4 |
| 向已停止 actor `send` | 既有语义：邮箱关闭则丢弃 | 不报错 | R14.3 |

**确定性收敛保证**：根 supervisor 的 `Escalate` 退化为「停止根」而非无限上抛，配合重启强度上界，保证任意失败序列下调度有限步内收敛（R10.5）。


---

## 可解释性：paper-to-code 与开源对标（R13）

### paper-to-code 可追溯

| 语义 | 源文献 / 来源 | 本设计落点 |
|------|---------------|------------|
| 消息传递、私有状态、异步通信 | Hewitt, Bishop & Steiger (1973)《A Universal Modular ACTOR Formalism for Artificial Intelligence》 | `ActorRef::send` + `Mailbox[M]` + 私有 `state` |
| actor 三公理（创建新 actor、发消息、指定下条消息行为）、行为切换 | Agha (1986)《Actors: A Model of Concurrent Computation in Distributed Systems》 | `spawn` / `send` / `become`-`unbecome` 行为栈（R5） |
| 监督树、重启策略、最大重启强度、let-it-crash | Erlang/OTP `supervisor` 原则（Armstrong 等） | `SupervisionStrategy` + `Directive` + `RestartIntensity`（R1/R2） |
| ask、become/unbecome、stash/unstash、router、death watch | Akka 文档对应概念 | `ask`/`AskBroker`、行为栈、`StashBuffer`、`Router`、`WatchRegistry`（R4~R8） |
| 一致性哈希路由 | Karger 等一致性哈希思想 | `Router` 的 `ConsistentHash`（FNV-1a + 排序环，R8.4） |

> 注：以上文献信息为概念溯源，具体表述均经改写以符合授权合规；引用仅用于设计依据说明。

### 与主流 actor 实现对标（R13.4）

| 维度 | Erlang/OTP | Akka (Typed) | Elixir/OTP | Pony | Actix | **本框架** |
|------|-----------|--------------|-----------|------|-------|-----------|
| 并发模型 | BEAM 抢占式轻进程 | JVM 线程池 dispatcher | BEAM（同 Erlang） | 运行时 work-stealing | Tokio 异步 | **同步确定性串行（模型）** |
| 监督策略 | one_for_one/all/rest_for_one | Backoff/Restart/Stop/Escalate | 同 Erlang | actor GC + reference capabilities | Actor 重启有限 | **OneForOne/OneForAll/RestForOne + Restart/Stop/Escalate**（R1/R2） |
| ask | `gen_server:call` | `?`/ask + 超时 | `GenServer.call` | promises | `Addr::send` 返回 Future | **`ask` + 关联 id + Replied/Timeout**（R4） |
| 行为切换 | `gen_statem` | `Behaviors.receive`/`same` | `:gen_statem` | 行为即方法集 | handler 切换有限 | **become/unbecome 行为栈**（R5） |
| stash | 手工缓冲 | `StashBuffer` | 手工缓冲 | — | — | **`StashBuffer` 保序**（R6） |
| death watch | `monitor`/`'DOWN'` | `watch`/`Terminated` | `Process.monitor` | — | — | **`watch`/`Terminated` 适配器**（R7） |
| 有界邮箱 | `max_heap_size` 等 | BoundedMailbox + 溢出策略 | 同 Erlang | 无界 | — | **`BoundedMailbox` + DropNewest/DropOldest/Reject**（R9） |
| 确定性重放 | 否（生产并发） | 否 | 否 | 否 | 否 | **是：种子驱动逐事件重放**（R10，本框架显著差异点） |

### 显式差异声明（R13.6）

1. **不真实并发**：本框架以单线程确定性串行调度模拟 actor 语义，换取可重放与三后端一致；不提供抢占、并行加速或真实隔离的崩溃域。
2. **ask 为同步驱动**：`ask` 通过运行有限步预算 + 轮询关联 id 实现，而非真实异步 Future；`Timeout` 以步数预算判定而非墙钟时间。
3. **Terminated 经适配器**：为不破坏冻结的消息类型 `M`，死亡监视以用户提供的 `on_terminated` 适配器把通知映射为 `M`（Akka `watchWith` 风格），而非内建系统消息变体。
4. **逻辑时钟**：重启强度窗口以 step 计数（逻辑时钟）而非真实时间度量。


---

## 设计权衡（Design Tradeoffs）

| 抉择 | 选项 A | 选项 B | 决定与理由 |
|------|--------|--------|------------|
| 新能力承载方式 | 扩容既有 `Scheduler`/枚举 | **平行新增 `ActorSystem` + 新类型** | 选 B：守住 R14 向后兼容硬约束，旧代码零改动 |
| 处理函数副作用 | handler 直接改全局 | **经 `ActorContext` 记录效果、step 末尾统一应用** | 选 B：可控、可测、无后端差异 |
| 行为返回类型 | 新增结果枚举 | **复用冻结 `ActorOutcome[S]`** | 复用：不新增冗余枚举，效果走 ctx |
| ask 响应类型 | 让 `M` 携带响应 | **独立 `AskBroker[R]` 解耦 R 与 M** | 选 B：类型整洁、不污染消息协议 |
| Terminated 投递 | 内建系统消息变体 | **用户适配器 `on_terminated -> M`** | 选 B：不破坏冻结 `M`，对齐 Akka watchWith |
| 调度顺序 | 固定登记顺序 | **种子 Rng 可选 + 默认登记顺序** | 兼得：默认与既有一致，种子开启探索与重放 |
| 一致性哈希 | 浮点权重环 | **整数 FNV-1a + 排序环** | 选 B：消除浮点后端差异，保证确定性 |
| 失败传播 | `raise`/异常 | **显式枚举信号** | 选 B：三后端一致、可断言、可被证明谓词引用 |

---

## 三后端一致性策略（R15.1）

为保证 `wasm-gc`/`js`/`native` 逐位一致，本设计遵守仓库既定纪律：

1. **不使用浮点**：一致性哈希、计数、强度窗口均为整数运算。
2. **不依赖 `Map`/`Set` 遍历顺序**：需要顺序语义处（监视表、监督子集合、trace）一律以 `Array` 承载并显式排序；以 id 为键的查找按精确键定位，不遍历。
3. **不使用 `raise` 跨后端传播**：失败以枚举信号表达。
4. **确定性随机源**：复用 `@infra_pbt.Rng`（`rng_new`/`next_below`/`next_range`），同种子同序列。
5. **native 前置**：文档与脚本统一要求 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R15.4）。
6. **三后端同套件**：`moon test --target wasm-gc|js|native` 运行同一测试与可执行文档，任意后端分歧判定为构建失败。


---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有有效执行下都应成立的行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。* 下列属性均以全称量化（「对任意 / 对所有」）表达，并标注其验证的需求条款。每条属性以 `@infra_pbt` 的 `holds_for_all`/`round_trip` 实现，默认迭代 ≥100 次，三后端逐位一致、可重放（R15.2）。

### Property 1：OneForOne 兄弟隔离

对任意由生成器产生的子 actor 集合与状态，当某一子在 `OneForOne` 策略下失败被处置时，所有未失败兄弟的状态与生命周期状态保持不变。

**Validates: Requirements 1.2, 1.6**

### Property 2：OneForAll 全体处置

对任意由生成器产生的子 actor 集合，当任一子在 `OneForAll` 策略下失败时，该 supervisor 的全部子（含失败者）均按各自重启指令被处置。

**Validates: Requirements 1.3**

### Property 3：RestForOne 影响范围

对任意由生成器产生的、按已知顺序启动的子序列，当某位置的子在 `RestForOne` 策略下失败时，仅该失败者及按启动顺序在其之后的子被处置，在其之前启动的子状态与生命周期不受影响。

**Validates: Requirements 1.4, 1.7**

### Property 4：监督树升级传递

对任意由生成器产生的两层及以上监督树，当下层子以 `Escalate` 指令失败时，该失败被上抛至其 supervisor，并由上层 supervisor 按其自身策略处置。

**Validates: Requirements 1.5, 2.4**

### Property 5：重启指令语义

对任意由生成器产生的失败场景与后续消息序列：`Restart` 指令使失败 actor 状态重置为初始且生命周期恢复为 `Running`；`Stop` 指令使其生命周期为 `Stopped` 且其后续消息不再被处理。

**Validates: Requirements 2.1, 2.2, 2.3**

### Property 6：重启强度上界

对任意由生成器产生的失败序列与重启强度配置 `(max_restarts, window)`，在任意 `window` 长度的逻辑时钟窗口内，对单个 actor 触发的重启次数不超过 `max_restarts`；超过阈值的失败被升级或停止。

**Validates: Requirements 2.5, 2.6, 2.7**

### Property 7：重启状态重置且按序调用钩子

对任意由生成器产生的初始状态与失败前消息历史，重启后的 actor 状态等于「以初始状态为起点、不重放失败前消息」的状态，且重启过程严格按 `pre_restart → 重置 → post_restart → Running` 顺序进行。

**Validates: Requirements 3.3, 3.5, 3.6**

### Property 8：重启丢弃当前消息

对任意触发失败的当前消息，重启后该消息不被重放，actor 从其邮箱中的下一条消息继续处理。

**Validates: Requirements 3.4**

### Property 9：pre_start 至多一次且先于处理

对任意由生成器产生的生命周期转换序列，每个 actor 的 `pre_start` 钩子至多被调用一次，且其调用严格先于该 actor 的任何消息处理。

**Validates: Requirements 3.1, 3.7**

### Property 10：post_stop 调用一次

对任意因 `stop` 请求或 `Stop` 指令而终止的 actor，其 `post_stop` 钩子在该 actor 停止后恰被调用一次。

**Validates: Requirements 3.2**


### Property 11：ask 关联 id 唯一性

对任意由生成器产生的 ask 交互序列，同一运行内分配的关联 id 两两不同。

**Validates: Requirements 4.2, 4.7**

### Property 12：ask 响应-请求匹配唯一性

对任意由生成器产生的并发 ask 请求集合，每个收到的响应恰好匹配其原始请求的关联 id，且任一响应至多被消费一次、不会被匹配到其它关联 id 的请求。

**Validates: Requirements 4.3, 4.5, 4.6**

### Property 13：ask 超时确定性

对任意由生成器产生的「在步数预算内未收到匹配响应」的 ask 交互，其结果被确定性地判定为 `Timeout`，且以同一输入重复执行得到相同结果。

**Validates: Requirements 4.4**

### Property 14：become 当前行为生效

对任意由生成器产生的消息序列与 `become`/`unbecome` 切换序列，每条消息由其被处理时刻的行为栈栈顶行为处理；初始栈顶为派生时给定行为。

**Validates: Requirements 5.1, 5.2, 5.3, 5.6**

### Property 15：行为栈往返与不弹空

对任意由生成器产生的行为栈操作序列：`become(b)` 紧随 `unbecome()` 后行为栈恢复为操作前状态；当栈仅含初始行为时 `unbecome()` 保持当前行为不变（不弹空初始行为）。

**Validates: Requirements 5.4, 5.7**

### Property 16：重启重置行为栈

对任意由生成器产生的行为切换历史，actor 被重启后其行为栈恢复为仅含初始行为。

**Validates: Requirements 5.5**

### Property 17：stash 保序与就绪判定

对任意由生成器产生的消息序列与 stash/unstash 操作序列，`unstash_all` 后被暂存消息的相对处理顺序与其暂存时的相对顺序一致；且仅含暂存消息（邮箱为空）的 actor 不被错误唤醒处理这些暂存消息。

**Validates: Requirements 6.2, 6.3, 6.5**

### Property 18：重启或停止清空暂存

对任意由生成器产生的暂存内容，当 actor 被重启或停止后，其暂存缓冲为空。

**Validates: Requirements 6.4**

### Property 19：终止通知必达且不重复

对任意由生成器产生的监视关系集合与终止序列，每个在终止时刻仍处于监视状态的监视者，恰好收到一条对应该 target 的、携带其 `ActorId` 与终止原因的 `Terminated` 通知。

**Validates: Requirements 7.1, 7.2, 7.5, 7.6**

### Property 20：unwatch 撤销监视

对任意由生成器产生的「watch 后 unwatch」序列，该 target 在 unwatch 之后的终止不再向该监视者投递 `Terminated`。

**Validates: Requirements 7.3**

### Property 21：watch 已终止目标立即通知

对任意已经终止的 target，对其执行 `watch` 时监视者立即收到一条携带该 target 标识与原因的 `Terminated` 通知。

**Validates: Requirements 7.4**


### Property 22：Broadcast 全达

对任意由生成器产生的消息序列与 worker 数量，经 `Broadcast` 路由后每个 worker 收到的消息条数等于输入消息条数。

**Validates: Requirements 8.3, 8.6**

### Property 23：RoundRobin 均衡

对任意由生成器产生的、长度为 worker 数整数倍的消息序列，经 `RoundRobin` 路由后各 worker 收到的消息条数相等，且分发按固定循环顺序命中。

**Validates: Requirements 8.2, 8.7**

### Property 24：ConsistentHash 分发稳定

对任意由生成器产生的路由键序列，当 worker 集合保持不变时，`ConsistentHash` 对相同键的分发目标始终为同一个 worker。

**Validates: Requirements 8.4, 8.5, 8.8**

### Property 25：有界邮箱容量上界与未满 FIFO

对任意由生成器产生的容量、背压策略与投递序列，有界邮箱在任意时刻排队消息条数不超过其容量上限；且当未满时新消息按 FIFO 入队，顺序与无界邮箱一致。

**Validates: Requirements 9.2, 9.7**

### Property 26：背压计数守恒

对任意由生成器产生的投递序列，「入队条数 + 丢弃条数 + 拒绝条数」等于投递总条数，且每次投递恰使三者之一加一。

**Validates: Requirements 9.3, 9.4, 9.5, 9.8**

### Property 27：重放确定性

对任意由生成器产生的调度种子与初始 actor 系统，以同一种子的两次运行产生逐事件一致的处理序列（actor id 与被处理消息序列完全一致）。

**Validates: Requirements 10.1, 10.2, 10.6**

### Property 28：串行处理与 FIFO 顺序（复用既有 Property）

对任意单一发送者向单一 actor 投递的消息序列，actor 一次仅处理一条消息（串行），且严格按投递顺序处理（FIFO）；处理后状态逐位等于投递顺序。

**Validates: Requirements 10.3, 10.4**

> 该属性已在 `prop_fifo_test.mbt` 落地（既有 Property 22 模板），本次以 `ActorSystem` 路径复测一致。

### Property 29：调度终止性

对任意由生成器产生的有限初始系统，`run_until_idle` 在有限步内停机（无 `Running` 且邮箱非空的 actor 时返回空闲），得到有限长度的处理序列。

**Validates: Requirements 10.5**

### Property 30：工作池韧性

对任意由生成器产生的任务批次与单点注入失败，受监督工作池在 `OneForOne` 重启后最终完成所有可完成任务，且未失败 worker 的处理结果不丢失。

**Validates: Requirements 11.7**

### Property 31：向后兼容

对任意由生成器产生的、仅使用既有 `spawn`/`send`/`stop` 与 `Scheduler` API 的消息序列，其处理结果（FIFO 顺序、串行处理、错误隔离、stop 语义）与 `0.1.0` 骨架逐字段一致。

**Validates: Requirements 14.3, 14.6**


---

## 测试策略（Testing Strategy）

采用**单元测试 + 属性测试**的互补双轨，二者均必要：

### 属性测试（property tests）

- 覆盖上述 31 条正确性属性中的全称量化不变量（监督隔离/范围、重启强度上界与状态重置、ask 匹配与唯一、become 当前行为、stash 保序、watch 通知必达、路由分发、有界邮箱守恒、重放确定性、向后兼容、工作池韧性）。
- 一律复用 `@infra_pbt`：以 `Gen::new(fn(rng) {...})` 构造生成器，以 `holds_for_all(gen, fn(ok) { ok })` 断言；序列化类属性（如 trace/状态）可用 `round_trip` 模板。
- 每条属性 ≥100 次迭代（`holds_for_all` 默认 `default_iters`），三后端逐位一致、可重放。
- 测试命名遵循既有约定：`test "Feature: actor, Property N: <属性标题> (holds_for_all template)"`，文件以 `prop_*_test.mbt` 命名、本地辅助使用独立前缀避免同包冲突。

### 单元测试（unit tests）

- 锁定具体见证与边界/错误场景：监督树两层升级、`unbecome` 弹空空操作、`watch` 已终止 target、有界邮箱三策略满时行为、ask 超时、stop 后丢弃消息等。
- 避免与属性测试重复覆盖输入空间；单元测试聚焦代表性示例、组件衔接点与边界。

### 可执行文档（README.mbt.md，R11.6 / R15.3）

- 追加覆盖监督、ask、become/unbecome、stash、router、death watch、有界邮箱与受监督工作池端到端示例的 ` ```mbt check ` 块，经 `moon test src/actor/README.mbt.md` 编译运行 + 快照校验。

### 分类说明（来自 prework）

- **PROPERTY**：R1.2/1.6、1.4/1.7、1.3、2.2/2.3、2.6/2.7、3.x、4.2~4.7、5.x、6.2~6.5、7.2~7.6、8.2~8.8、9.2~9.8、10.2~10.6、11.7、14.3/14.6。
- **EXAMPLE/EDGE_CASE**：类型构造与配置入口（1.1/2.1/2.5/4.1/5.1/6.1/7.1/8.1/9.1/9.6/10.1/10.3）、监督树升级（1.5/2.4）、弹空边界（5.4）、已终止 watch（7.4）、发布元数据（15.5/15.6）、端到端步骤（11.1~11.5）。
- **INTEGRATION/SMOKE（不做 PBT）**：三后端门禁（15.1）、可执行文档（11.6/15.3）、基准与回归 guard（12.x）、native 前置（12.4/15.4）、`.mbti` 兼容快照（14.1/14.2/14.4/14.5）、paper-to-code 文档（13.x）。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 | 验证 |
|------|----------|------|
| R1 监督策略与监督树 | `supervision.mbt`：`SupervisionStrategy` + `supervise` + `parents` 树 | Property 1~4；单元（升级） |
| R2 重启指令与强度 | `supervision.mbt`：`Directive` + `RestartIntensity` + `on_child_failed` | Property 5~6 |
| R3 生命周期钩子与重启语义 | `lifecycle.mbt`：`LifecycleHooks` + `restart` 步骤 | Property 7~10 |
| R4 ask | `ask.mbt`：`CorrelationId`/`AskResult`/`AskBroker`/`ask` | Property 11~13 |
| R5 become/unbecome | `behavior.mbt`：`Behavior` 行为栈 + `ActorContext` | Property 14~16 |
| R6 stash/unstash | `stash.mbt`：`StashBuffer` + `drain_to_front` | Property 17~18 |
| R7 death watch | `deathwatch.mbt`：`WatchRegistry` + `Terminated` 适配器 | Property 19~21 |
| R8 router | `router.mbt`：`RoutingStrategy` + `Router` | Property 22~24 |
| R9 有界邮箱与背压 | `bounded_mailbox.mbt`：`BoundedMailbox` + `OfferResult` | Property 25~26 |
| R10 确定性调度与重放 | `system.mbt`/`deterministic.mbt`：种子 Rng + `trace` + `replay_consistent` | Property 27~29 |
| R11 受监督工作池示例 | `demo.mbt` + `README.mbt.md` | Property 30；可执行文档 |
| R12 性能基准 | `benches/actor_bench/` + 回归 guard | SMOKE/INTEGRATION |
| R13 paper-to-code 与对标 | §可解释性（溯源表 + 对标表 + 差异声明） | 文档审阅 |
| R14 向后兼容 | §向后兼容契约 + 平行 `ActorSystem` | Property 31；`.mbti` 快照 |
| R15 工程质量门禁 | 三后端 + ≥100 迭代 PBT + 可执行文档 + `release_info_with_gates` | INTEGRATION/门禁 |

---

## 设计完成说明

本设计在不改动既有 `0.1.0` 公开 API 的前提下，以平行新增类型与文件落地方向十的全部旗舰能力，并将每条核心语义映射为全称量化的正确性属性（≥100 迭代、三后端一致、可重放）。下一步进入 **任务清单（tasks）** 阶段，将本设计拆解为增量、可验证的编码任务。
