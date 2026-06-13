# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 `dst 0.1.0` 骨架之上，做**增量式、严格向后兼容**的旗舰级深化，目标对标 **FoundationDB 确定性仿真、TigerBeetle VOPR、`madsim`/`turmoil` 与 Jepsen/Knossos**。核心原则一句话：**既有公开类型与函数（`Rng`/`Task`/`Event`/`FaultKind`/`FaultPolicy`/`Scenario`/`SimStatus`/`SimResult`/`Sim` 与 `rng_new`/`Rng::next`/`Rng::next_below`/`Sim::new`/`Sim::step`/`Sim::inject_fault`/`run`/`replay`/`release_info`/`release_info_with_gates`）的签名、字段、变体与运行时语义全部冻结，所有新能力以旁路扩展（新增类型、新增文件、新增函数与方法）的方式提供，绝不改写既有枚举形态或既有调度/重放语义。**

骨架阶段已确立并必须无损保持的核心价值：**同种子 → 同执行**——相同种子的两次运行产生逐事件一致的调度序列与相同终态；「`seed` + `trace`」构成可重放凭据，`replay` 复现完全相同的结果。

既有「步进式」流水线保持不变：

```
Rng(xorshift64) → Sim::new → [inject_fault @at_step ; step] 循环 → run(seed, scenario) / replay(seed, trace) → SimResult
```

旗舰深化在其**旁侧**新增一条**离散事件仿真（DES）流水线**，二者通过「遗留场景提升桥」连接以支撑差分一致性验证：

```
DesScenario ─ World::new ─▶ World(虚拟时钟 + 事件队列 + 节点/邮箱 + 轨迹)
   │                              │
   │ DesScenario::of_legacy        │  World::step（取队首事件 → 处理 → 入队未来事件）
   │（提升既有 Scenario）            ▼
   ▼                          run_des(seed, scenario) / replay_des(seed, trace) ─▶ DesResult
既有 Scenario ─ run ─▶ SimResult   │                                                   │
                  （冻结，差分对照） └─ 注入丰富故障 / 校验不变量 / 线性一致性检查 ──┘
                                                    │
              ┌──── shrink（失败收缩，delta debugging）◀── 失败的 DesResult
              ├──── explore_bounded（有界穷尽交错枚举）
              └──── explore_dpor（DPOR 偏序约简）── 与 explore_bounded 差分一致
```

旗舰能力分十条主线落地：**①逻辑时钟/虚拟时间内核**、**②离散事件队列与消息传递**、**③丰富故障模型**、**④失败用例收缩**、**⑤有界穷尽交错探索**、**⑥DPOR 偏序约简**、**⑦运行时不变量与线性一致性检查**、**⑧轨迹持久化与跨会话重放**、**⑨多副本复制端到端 demo**、**⑩性能基准与可解释性**。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、三后端一致性策略、错误处理与正确性属性。

---

## 架构（Architecture）

### 设计原则与向后兼容契约

1. **冻结即契约**：`types.mbt`/`rng.mbt`/`sim.mbt`/`release.mbt` 中现有的 `pub`/`pub(all)` 声明，其签名、字段、变体与运行时行为一律不改。`pkg.generated.mbti` 现有条目保持稳定，新增条目仅追加（R12.1/12.2）。
2. **既有调度语义不变**：`run` 维持「任务按 id 升序规范化、故障按 `(at_step, task_id)` 升序处理、同种子 → 同调度序列 + 同终态」（R12.3）。既有 `prop_replay` 属性测试继续作为回归守卫。
3. **枚举不扩容（关键取舍）**：既有 `FaultKind`、`Event`、`SimStatus` 均为 `pub(all) enum`——向其追加变体会改变其形态、破坏下游对其做穷尽匹配的调用方。因此**新故障类型与新事件类型不通过修改既有枚举实现**，而是**新增平行枚举** `NetFaultKind`（含 `Crash`/`Delay`/`Drop` 语义等价项 + `Partition`/`Reorder`/`Duplicate`/`ClockSkew`/`Byzantine`）与 `SimEvent`（带逻辑时间戳，含 `Send`/`Deliver`），由 DES 流水线使用。这与既有姊妹方向「拒绝扩容 `pub(all) enum` 以保兼容」的取舍一致（R12.4）。`SimStatus` 直接**复用**（DES 终态同样是 `Completed` / `Failed(reason)`）。
4. **旁路扩展**：虚拟时钟、事件队列、消息传递、丰富故障、收缩、探索、DPOR、不变量、线性一致性、持久化全部为新增类型 / 新增文件 / 新增函数；既有 `Sim`/`run`/`replay` 一字不改（R12.4）。
5. **桥接而非替换**：`DesScenario::of_legacy` 把既有 `Scenario` 提升进 DES 模型（如 `Ast::of_regex` 之于正则方向），使「无消息、仅遗留故障」的场景可在两条流水线间做差分一致性验证（R12.3）。
6. **infra 复用**：全部新增属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`（每条 ≥100 迭代）；发布元数据复用 `@release_meta`，`release_info`/`release_info_with_gates` 语义不变，仅版本号与 CHANGELOG 推进（R12.5/R13.5）。
7. **DES 运行时随机源**：DES 流水线沿用 dst 自有 `Rng`（xorshift64，仅移位 + 异或，三后端逐位一致），不在运行时 import `@infra_pbt`（后者定位为测试期横切约定），与骨架 `moon.pkg` 既定边界一致。

### 模块 / 文件划分

下表为 `src/dst/` 下的文件规划。**既有文件**保持冻结；**新增文件**承载旗舰能力。

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `types.mbt` | 冻结 | 既有 `Task`/`Event`/`FaultKind`/`FaultPolicy`/`Scenario`/`SimStatus`/`SimResult`/`Sim` | R12.1 |
| `rng.mbt` | 冻结 | 既有 `Rng`/`rng_new`/`next`/`next_below` | R1.4/R12.2 |
| `sim.mbt` | 冻结 | 既有 `Sim::step`/`inject_fault`/`run`/`replay`（步进式语义） | R12.2/12.3 |
| `release.mbt` | 冻结 | 既有发布元数据登记 | R12.5 |
| `clock.mbt` | 新增 | 逻辑时钟 / 虚拟时间 `LogicalTime`，时钟偏移施加 `skewed_time` | R1.2/R3.5 |
| `des_types.mbt` | 新增 | DES 数据模型：`SimEvent`/`Message`/`Node`/`NodeApp`/`DesScenario`/`DesResult`/`Protocol`/`Action` | R2/R12.4 |
| `event_queue.mbt` | 新增 | `EventQueue`（按「(时间, 任务 id, 次序键)」全序的优先队列）、`QueuedEvent` | R1.3/R2.1 |
| `messaging.mbt` | 新增 | `send`/`deliver` 语义、消息 id 分配、因果序保持 | R2.2/2.3/2.4 |
| `faults_ext.mbt` | 新增 | `NetFaultKind`/`FaultPolicyEx`、分区分组、重排/重复/时钟偏移/拜占庭应用、注入点定位、`of_legacy` 桥 | R3 |
| `des_sim.mbt` | 新增 | DES 核心循环：`World::new`/`World::step`/`run_des`/`replay_des`、`DesScenario::of_legacy` | R1.1/R2.1/R2.5/R12.4 |
| `shrink.mbt` | 新增 | 失败收缩（delta debugging）：`shrink`、`DesScenario::size`、收缩算子 | R4 |
| `explore.mbt` | 新增 | 有界穷尽交错枚举：`explore_bounded`、`Schedule`、`ExploreReport` | R5 |
| `dpor.mbt` | 新增 | DPOR 偏序约简：`explore_dpor`、依赖关系 `depends`、持久集 | R6 |
| `invariant.mbt` | 新增 | `Invariant`（对可观测全局状态的布尔断言）与每步求值集成 | R7.1/7.2/7.3 |
| `linearizability.mbt` | 新增 | Wing & Gong 线性一致性检查：`History`/`OpEvent`/`is_linearizable`/`RegisterModel` | R7.4/7.5 |
| `trace_codec.mbt` | 新增 | `DesResult`/`trace` 文本序列化与反序列化、`CodecError`、`round_trip` 适配 | R8 |
| `demo.mbt` | 新增 | 多副本日志复制场景、副本一致性不变量、注入分区+崩溃触发失败的端到端闭环数据 | R9 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖虚拟时间/消息/丰富故障/收缩/探索/多副本 demo | R9.6/R13.3 |
| `CHANGELOG.md` | 扩充 | SemVer 推进记录 | R13.5 |
| `prop_*_test.mbt` | 新增/既有 | 属性测试（见「测试策略」「正确性属性」） | R13.2 |

`benches/` 下新增基准包 `benches/dst_bench/`（`dst_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`），结构对齐既有 `benches/astar_bench`，覆盖 `run`/`replay`/穷尽探索/DPOR/收缩五类工作负载，产出 `benches/results/` 工件并接入 guard（R10）。

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt`/`.mbti` 风格：`pub(all)` 暴露可构造、可派生 `Eq`/`Show` 的纯数据；`pub` 暴露承载函数值或可变状态的结构（如 `World`，与既有 `Sim` 同例不派生）。新枚举的变体名与既有枚举刻意区分以避免同包构造子歧义。

### 4.1 逻辑时钟 / 虚拟时间（R1.2/R1.3/R3.5）

虚拟时间是与真实墙钟无关的离散度量。统一以 `UInt64` 表示逻辑时间戳，保证三后端整数语义一致且无溢出风险。

```moonbit
// clock.mbt
pub typealias LogicalTime = UInt64

/// 对基准时间施加确定性时钟偏移（ClockSkew 故障使用）；结果下钳到 0，避免回退。
pub fn skewed_time(base : LogicalTime, offset : Int64) -> LogicalTime
```

全序约定（R1.3）：当同一逻辑时间存在多个待处理事件时，按「**(逻辑时间戳升序, 任务 id 升序, 确定性次序键升序)**」决定处理顺序；次序键由消息 id / 单调入队序号给出，保证平局打破完全确定。虚拟时间沿事件队列出队单调不减（R1.2，由「队首即全序最小」保证）。

### 4.2 DES 数据模型（R2/R12.4）

```moonbit
// des_types.mbt

/// 任务间传递的消息（纯内存模型）。`id` 为确定性发送序号，用于因果追踪、重排与重复。
pub(all) struct Message {
  id : Int
  payload : Int          // 简化负载（如待复制的日志值）；纯内存确定性模型
} derive(Eq, Show)

/// DES 富事件——既有 `Event` 的旁路扩展：每个事件携带逻辑时间戳，并新增 Send/Deliver。
/// 变体名以 `Ev` 前缀与既有 `Event` 区分，避免同包构造子歧义。
pub(all) enum SimEvent {
  EvScheduled(time~ : LogicalTime, task_id~ : Int)
  EvCompleted(time~ : LogicalTime, task_id~ : Int)
  EvFaulted(time~ : LogicalTime, task_id~ : Int, kind~ : NetFaultKind)
  EvSend(time~ : LogicalTime, from~ : Int, to~ : Int, msg~ : Message)
  EvDeliver(time~ : LogicalTime, from~ : Int, to~ : Int, msg~ : Message)
} derive(Eq, Show)

/// 节点应用层状态（可观测全局状态的组成单元，供不变量 / 一致性检查）。
pub(all) struct NodeApp {
  log : Array[Int]              // 复制日志（多副本 demo 的核心可观测量）
  kv : Array[(String, Int)]     // 通用键值视图（KV demo / 线性一致性历史使用）
} derive(Eq, Show)

/// 节点运行时（承载邮箱与本地时钟偏移），不派生（含运行态）。
pub struct Node {
  id : Int
  name : String
  app : NodeApp
  skew : Int64                  // ClockSkew 故障施加的本地时钟偏移
}

/// 协议动作——节点处理事件后请求引擎执行的副作用（纯描述，不直接修改世界）。
pub(all) enum Action {
  ActSend(to~ : Int, payload~ : Int, after~ : LogicalTime)   // after 个时间单位后投递
  ActAppend(value~ : Int)                                     // 向本节点复制日志追加
} derive(Eq, Show)

/// 协议——以纯转移函数描述节点行为（函数值字段，故 Protocol/DesScenario 不派生）。
pub struct Protocol {
  init : (Int) -> NodeApp                              // 由节点 id 构造初始应用状态
  on_deliver : (NodeApp, Message) -> (NodeApp, Array[Action])  // 收到消息的纯转移
  on_start : (Int) -> Array[Action]                    // 启动激励（如领导者首次广播）
}

/// DES 场景——一次 run_des 的完整输入；含函数值（protocol / invariants），不派生。
pub struct DesScenario {
  tasks : Array[Task]                  // 复用既有 Task
  faults : Array[FaultPolicyEx]
  invariants : Array[Invariant]
  protocol : Protocol
  max_steps : Int
}

/// DES 结果——可重放凭据 + 各节点终态（供副本一致性校验）；纯数据，派生 Eq/Show。
pub(all) struct DesResult {
  seed : UInt64
  trace : Array[SimEvent]
  status : SimStatus                   // 复用既有 SimStatus（Completed / Failed(reason)）
  finals : Array[(Int, NodeApp)]       // (节点 id, 终态)，按 id 升序
} derive(Eq, Show)
```

### 4.3 事件队列（R1.3/R2.1）

```moonbit
// event_queue.mbt

/// 队列中的待处理事件（内部调度元素）。
pub(all) struct QueuedEvent {
  time : LogicalTime
  task_id : Int          // 全序第二键
  order_key : UInt64     // 全序第三键（单调入队序号 / 消息 id）
  pending : Pending
} derive(Eq, Show)

/// 待处理事件种类：投递某消息 / 唤醒某任务执行一步。
pub(all) enum Pending {
  PDeliver(from~ : Int, to~ : Int, msg~ : Message)
  PWake(task_id~ : Int)
} derive(Eq, Show)

pub struct EventQueue { /* 二叉堆或有序数组，按全序 (time, task_id, order_key) */ }

pub fn EventQueue::new() -> EventQueue
pub fn EventQueue::is_empty(self : EventQueue) -> Bool
pub fn EventQueue::push(self : EventQueue, ev : QueuedEvent) -> EventQueue   // 返回新队列（不可变 API）
pub fn EventQueue::pop_min(self : EventQueue) -> (QueuedEvent, EventQueue)?  // 取全序最小；空则 None
```

核心循环（R2.1）：`World::step` 调用 `pop_min` 取出全序最小事件，处理后把新产生事件 `push` 回队列；如此「取队首 → 处理 → 入队未来事件」直至队空或达 `max_steps`（R2.5）。

### 4.4 消息传递与因果序（R2.2/2.3/2.4/2.6）

```moonbit
// messaging.mbt

/// 安排一次发送：记录 EvSend，并按 `after` 计算确定的未来投递时间，向队列入队 PDeliver。
/// 投递时间 = 当前虚拟时间 + max(after, 1)，保证 deliver 时间严格大于 send 时间（R2.4）。
pub fn World::schedule_send(self : World, from : Int, to : Int, payload : Int, after : LogicalTime) -> World

/// 处理一次投递：在不受分区/丢弃阻断时记录 EvDeliver 并调用 protocol.on_deliver 推进目标节点。
pub fn World::deliver(self : World, from : Int, to : Int, msg : Message) -> World
```

因果序（R2.6）：在**无丢弃、无分区**故障下，每条 `EvSend` 恰对应一条 `EvDeliver`（消息按 id 一一配对），且该 `EvDeliver.time > EvSend.time`。消息 id 由 `World.msg_seq` 单调分配，保证发送—投递配对确定。

### 4.5 丰富故障模型（R3）

```moonbit
// faults_ext.mbt

/// 扩展故障类型——既有 FaultKind 的平行旁路扩展（不修改既有枚举）。
/// Crash/Delay/Drop 与既有语义等价；其余为旗舰新增。变体名独立以避免同包歧义。
pub(all) enum NetFaultKind {
  Crash                                  // 任务崩溃（语义同既有 Crash）
  Delay(by~ : LogicalTime)               // 延迟（语义同既有 Delay，附确定延迟量）
  Drop                                   // 丢弃（语义同既有 Drop）
  Partition(group~ : Int, until_step~ : Int)  // 网络分区：task 属于 group，区间 [at_step, until_step) 内阻断跨组投递
  Reorder                                // 消息重排：确定性改变受影响消息投递顺序
  Duplicate                              // 消息重复：受影响消息被投递两次
  ClockSkew(offset~ : Int64)             // 时钟偏移：对目标任务本地逻辑时钟施加偏移
  Byzantine                              // 可选：任务向不同对端发送相互矛盾内容
} derive(Eq, Show)

/// 扩展故障策略——注入点由「(步序号, 目标任务)」精确定位（R3.7 确定且可重放）。
pub(all) struct FaultPolicyEx {
  at_step : Int
  task_id : Int
  kind : NetFaultKind
} derive(Eq, Show)
pub fn FaultPolicyEx::new(at_step : Int, task_id : Int, kind : NetFaultKind) -> FaultPolicyEx

/// 向后兼容桥：把既有 FaultKind / FaultPolicy 提升为扩展形态（语义等价）。
pub fn NetFaultKind::of_legacy(k : FaultKind) -> NetFaultKind          // Crash→Crash, Delay→Delay(by=1), Drop→Drop
pub fn FaultPolicyEx::of_legacy(p : FaultPolicy) -> FaultPolicyEx
```

各故障在 DES 引擎中的确定性效果：
- **Partition（R3.2，状态型）**：在生效区间 `[at_step, until_step)` 内，`deliver` 前检查源/目标任务所属分组，跨组投递被阻断（不产生 `EvDeliver`，消息丢弃或滞留依策略）。分组由命中的 `Partition` 策略的 `group` 字段决定。
- **Reorder（R3.3）**：命中注入点时，对当前同时刻、同目标的待投递消息按确定规则（如反转 `order_key` 比较或交换相邻两条）调换投递顺序——改变顺序而非丢失消息。
- **Duplicate（R3.4）**：命中时为受影响消息额外入队一条 `PDeliver`（不同 `order_key`），使其产生**两条独立 `EvDeliver` 事件**。
- **ClockSkew（R3.5）**：对目标任务设置 `Node.skew`，其后该节点产生的事件时间戳经 `skewed_time(base, skew)` 偏移。
- **Byzantine（R3.6，可选 `WHERE`）**：受影响任务在 `on_deliver`/`on_start` 产生 `ActSend` 时，对不同 `to` 发送由 `Rng` 确定但相互矛盾的 `payload`；该能力默认关闭，经场景显式启用。
- **注入点确定性（R3.7）**：故障按 `(at_step, task_id)` 升序规范化处理（沿用既有 `run` 的���范化范式），同种子下故障在同一注入点触发，含故障运行可被 `replay_des` 精确重放。

### 4.6 DES 核心循环（R1.1/R2.1/R2.5/R12.4）

```moonbit
// des_sim.mbt
pub struct World {
  rng : Rng                       // dst 自有确定性随机源
  clock : LogicalTime             // 全局虚拟时间（单调不减）
  step_no : Int                   // 已执行步数（故障注入点的步序号维度）
  nodes : Array[Node]
  queue : EventQueue
  trace : Array[SimEvent]
  msg_seq : Int                   // 下一条消息 id（确定性递增）
}

pub fn World::new(seed : UInt64, scenario : DesScenario) -> World   // 任务按 id 升序规范化 + 灌入 on_start 激励
pub fn World::step(self : World) -> World                            // 取队首事件 → 注入命中故障 → 处理 → 入队 + 求值不变量

pub fn run_des(seed : UInt64, scenario : DesScenario) -> DesResult   // 同种子 → 同执行（R1.1）
pub fn replay_des(seed : UInt64, trace : Array[SimEvent]) -> DesResult  // 由种子 + 轨迹复现（R8.4）

/// 向后兼容桥：把既有 Scenario 提升为 DesScenario（提供协议与不变量后纳入 DES 流水线）。
/// 对「无消息、仅遗留故障」的提升场景，DES 调度的任务选择复用与既有 step 相同的
/// `rng.next_below(待调度数)`（over id 升序待调度集），使两条流水线可做差分一致性验证。
pub fn DesScenario::of_legacy(scenario : Scenario, protocol~ : Protocol, invariants~ : Array[Invariant] = []) -> DesScenario
```

确定性两大支柱沿用骨架：(1) `Rng`（xorshift64）三后端逐位一致；(2) 任务按 id 升序、故障按 `(at_step, task_id)` 升序规范化，使「同种子 → 同调度序列 + 同终态」不依赖输入排列。`replay_des` 以轨迹为权威记录派生终态，复现与 `run_des` 逐字段一致的 `DesResult`。

### 4.7 失败用例收缩（R4）

```moonbit
// shrink.mbt

/// 场景规模度量：任务数 + 故障数 + max_steps（收缩单调性以此严格递减）。
pub fn DesScenario::size(self : DesScenario) -> Int

/// 收缩结果：仍失败的最小反例，或「输入并不失败」。
pub enum ShrinkOutcome {
  Minimal(DesScenario)     // 在所采用算子下不可再小、仍复现失败的反例（R4.4）
  NotFailing               // 输入场景并不失败，无可收缩反例（R4.5，不返回任意场景）
}

/// 对失败场景做 delta-debugging 收缩；`fails` 默认判定 status==Failed，可定制（如锁定同一不变量违反）。
pub fn shrink(seed : UInt64, scenario : DesScenario, fails~ : (DesResult) -> Bool = default_fails) -> ShrinkOutcome
```

算子（R4.2）：①移除一个任务；②移除一条故障策略；③缩减 `max_steps`。贪婪 ddmin 式流程：反复对每个算子生成候选，**仅接受仍复现原失败的候选**（R4.3，丢弃任何转为 `Completed` 者），无更小失败候选时停止并返回当前最小反例（R4.4）。终止性（R4.7）：每次接受使 `size` 严格递减且有下界（≥0），故有限步终止；单调性：结果 `size` 不大于输入。若输入本不失败则返回 `NotFailing`（R4.5）。

### 4.8 有界穷尽交错探索（R5）

```moonbit
// explore.mbt
pub typealias Schedule = Array[Int]    // 各调度点的选择下标序列（一个具体交错）

pub(all) struct ExploreReport {
  explored : Int                              // 已探索交错计数（覆盖可审计，R5.4）
  failing : (UInt64, Array[SimEvent])?        // 首个失败交错的可重放种子 + 轨迹（R5.3）
} derive(Eq, Show)

/// 在深度上界内枚举全部可达交错，对每个交错执行一次仿真；不修改既有 run/run_des 语义（R5.2）。
pub fn explore_bounded(seed : UInt64, scenario : DesScenario, depth : Int) -> ExploreReport
```

交错模型：每个调度点的「可运行集合」为当前队列中全序最小时间层内的若干可选事件；`Schedule` 记录每点选择下标。`explore_bounded` 以 DFS 枚举深度 ≤ `depth` 的全部 `Schedule`（R5.1），每条执行一次 DES 并对终态/不变量求值；任一交错失败即记录其可重放凭据（R5.3）。与确定性随机搜索（`run_des`）互补。

### 4.9 DPOR 偏序约简（R6）

```moonbit
// dpor.mbt

/// 依赖关系（R6.2）：作用于同一任务、或存在消息因果关联（同一 msg.id 的 send/deliver、
/// 或读写同一节点状态）的两事件为「依赖」；作用于不同任务且无因果关联者为「独立」（可交换）。
pub fn depends(a : SimEvent, b : SimEvent) -> Bool

/// DPOR 探索：基于依赖关系与持久集剪枝等价交错，对每个 Mazurkiewicz 迹等价类至少探索一个代表。
pub fn explore_dpor(seed : UInt64, scenario : DesScenario, depth : Int) -> ExploreReport
```

算法：Flanagan & Godefroid 2005 动态偏序约简。沿单条执行前进，对每个转移维护回溯集（backtracking set）；遇到与已执行转移**依赖**的可交换事件时，向最近的相关调度点添加回溯点，从而仅枚举每个等价类的代表交错（R6.3）。独立事件不产生额外分支，故所探索交错数不超过有界穷尽（R6.6），且任一失败交错必被某代表覆盖（R6.4，不漏报）。`ExploreReport` 结构与 `explore_bounded` 一致，便于差分对照。

### 4.10 运行时不变量与线性一致性（R7）

```moonbit
// invariant.mbt
pub struct Invariant {
  name : String
  check : (World) -> Bool        // 对可观测全局状态的布尔断言（函数值，故不派生）
}
pub fn Invariant::new(name : String, check : (World) -> Bool) -> Invariant
```

集成（R7.1/7.2/7.3）：`World::step` 在每个可观测状态求值场景附带的全部不变量；任一为假即令运行以 `Failed(reason="不变量 <name> 于逻辑时间 <t> 被违反")` 终止，原因标识被违反不变量与发生的逻辑时间戳。

```moonbit
// linearizability.mbt
pub(all) enum OpKind { Invoke ; Return } derive(Eq, Show)
pub(all) struct OpEvent {
  proc : Int                     // 客户端 / 进程
  kind : OpKind
  op : String                    // "put" / "get"
  arg : Int
  ret : Int
  time : LogicalTime
} derive(Eq, Show)
pub typealias History = Array[OpEvent]

pub(all) struct RegisterModel { init : Int } derive(Eq, Show)   // 顺序规约：读写寄存器 / 单键 KV

pub enum LinResult {
  Linearizable
  NotLinearizable(conflict~ : Array[OpEvent])   // 给出导致冲突的操作（R7.5）
}

/// Wing & Gong 线性化点检查：搜索一个保持实时先后序（return 早于 invoke 则定序）
/// 且满足顺序规约的合法线性顺序；存在则线性一致，否则报告冲突操作。
pub fn is_linearizable(history : History, model : RegisterModel) -> LinResult
```

线性一致性为**可选能力（`WHERE` 启用，R7.4）**：在小规模历史上以回溯搜索逐步「选取一个其调用区间可线性化的已完成操作」直至清空历史；无法清空即非线性一致并报告冲突（R7.5）。这是 Jepsen/Knossos 思路在纯内存模型下的对应实现。

### 4.11 轨迹持久化与跨会话重放（R8）

```moonbit
// trace_codec.mbt
pub(all) enum CodecError {
  Malformed(reason~ : String, pos~ : Int)    // 格式非法 / 损坏，携带原因与偏移（R8.5）
} derive(Eq, Show)

pub fn serialize_result(r : DesResult) -> String                       // 文本表示（R8.1）
pub fn deserialize_result(s : String) -> Result[DesResult, CodecError] // 失败携带原因，不产部分构造值（R8.2/8.5）

// round_trip 适配（对接 @infra_pbt.round_trip 的 (T)->Bytes 与 (Bytes)->T? 签名）
pub fn result_to_bytes(r : DesResult) -> Bytes
pub fn result_of_bytes(b : Bytes) -> DesResult?
```

序列化采用确定性、自描述的行式文本（字段名 + 值，事件逐行编码），保证 `deserialize(serialize(r))` 与 `r` 逐字段一致（R8.3/8.6）。跨会话重放（R8.4/8.7）：以反序列化得到的 `seed` 与 `trace` 调用 `replay_des`，复现与原运行逐字段一致的终态。解析任一字段非法即返回 `Malformed`，不返回半构造结果（R8.5）。

### 4.12 多副本复制端到端 demo（R9）

```moonbit
// demo.mbt
pub fn replication_protocol(replicas : Int) -> Protocol      // 简化的领导者广播 + 副本追加日志协议
pub fn demo_replication_scenario(replicas : Int) -> DesScenario          // 正常达成日志同步
pub fn demo_partition_crash_scenario() -> DesScenario                    // 注入分区+崩溃，必然违反一致性（R9.2）
pub fn replica_consistency_invariant() -> Invariant                      // 已提交前缀在各副本一致（R9.5）
```

端到端闭环（R9.1–9.6）：`demo_partition_crash_scenario` 经 `run_des` 产生违反 `replica_consistency_invariant` 的失败运行（R9.2）→ `shrink` 收缩到仍触发同一不变量违反的最小反例（R9.3）→ 以最小反例的 `seed`+`trace` 经 `replay_des` 复现同一失败终态（R9.4）→ 每步校验副本一致性并在违反时报告不变量名与逻辑时间戳（R9.5）。该 demo 同时作为 `README.mbt.md` 可执行文档与 `benches/dst_bench` 基准工作负载出现，使「发现—收缩—重放—校验」闭环可复现（R9.6）。

### 4.13 性能基准设计（R10）

`benches/dst_bench/` 对五类工作负载在大规模场景计时：`run_des`、`replay_des`、`explore_bounded`、`explore_dpor`、`shrink`（R10.1）。输出含机器标识、后端目标、场景规模与计时统计的 JSON/Markdown 工件（R10.2），写入 `benches/results/`；并记录 **DPOR 相对有界穷尽的交错数量约简比**以呈现偏序约简有效性（R10.3）。新运行与基线中位数比较，超声明容差给出可审计失败报告（R10.4，复用既有 guard 模式）。文档记录运行命令，要求 native 后端先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R10.5）。

---

## 数据模型（Data Models）

新增类型一览（既有 `Task`/`Event`/`FaultKind`/`FaultPolicy`/`Scenario`/`SimStatus`/`SimResult`/`Sim`/`Rng` 全部不变）：

| 类型 | 文件 | 派生 | 说明 |
|---|---|---|---|
| `LogicalTime`（别名 `UInt64`） | `clock.mbt` | — | 虚拟时间 |
| `Message` | `des_types.mbt` | Eq, Show | 任务间消息 |
| `SimEvent` | `des_types.mbt` | Eq, Show | 富事件（带时间戳 + Send/Deliver） |
| `NodeApp` | `des_types.mbt` | Eq, Show | 节点应用层可观测状态 |
| `Node` | `des_types.mbt` | — | 节点运行时（邮箱 + 偏移） |
| `Action` | `des_types.mbt` | Eq, Show | 协议动作 |
| `Protocol` / `DesScenario` | `des_types.mbt` | —（含函数值） | 协议与场景 |
| `DesResult` | `des_types.mbt` | Eq, Show | 可重放结果 + 节点终态 |
| `QueuedEvent` / `Pending` | `event_queue.mbt` | Eq, Show | 队列元素 |
| `EventQueue` | `event_queue.mbt` | — | 全序优先队列 |
| `NetFaultKind` / `FaultPolicyEx` | `faults_ext.mbt` | Eq, Show | 扩展故障 |
| `World` | `des_sim.mbt` | — | DES 世界状态 |
| `ShrinkOutcome` | `shrink.mbt` | — | 收缩结果 |
| `Schedule`（别名）/ `ExploreReport` | `explore.mbt` | Eq, Show（Report） | 交错与探索报告 |
| `Invariant` | `invariant.mbt` | —（含函数值） | 运行时不变量 |
| `OpKind`/`OpEvent`/`History`/`RegisterModel`/`LinResult` | `linearizability.mbt` | Eq, Show（数据项） | 一致性检查 |
| `CodecError` | `trace_codec.mbt` | Eq, Show | 持久化错误 |

**发布元数据**：版本自 `0.1.0` 起按旗舰深化做次/主版本推进（R13.5），`release_info`/`release_info_with_gates` 语义不变，仅版本号字符串与 CHANGELOG 更新（R12.5）。

---

## 错误处理（Error Handling）

- **反序列化错误（R8.5）**：`deserialize_result` 返回 `Result[DesResult, CodecError]`；格式非法 / 损坏映射为 `Malformed(reason, pos)`，携带人类可读原因与字符偏移，**绝不返回部分构造的 `DesResult`**。`result_of_bytes` 适配为 `DesResult?`（失败即 `None`）供 `round_trip` 使用。
- **收缩前置（R4.5）**：`shrink` 在输入场景并不失败时返回 `NotFailing`，而非任意场景。
- **无失败交错**：`explore_bounded`/`explore_dpor` 的 `ExploreReport.failing` 为 `None` 表示该深度内无失败交错，不抛异常。
- **不变量违反（R7.3）**：以 `SimStatus::Failed(reason)` 表达，原因含被违反不变量名与逻辑时间戳；非异常路径。
- **非线性一致（R7.5）**：以 `LinResult::NotLinearizable(conflict)` 表达并携带冲突操作；非异常路径。
- **故障作用于不存在/已移除任务**：沿用既有 `inject_fault` 的保守语义——不注入、原样推进（不抛异常）。
- **纯内存边界**：不接入真实网络/时间/线程，故无 I/O 异常面（R11.6）。

---

## 算法说明与 paper-to-code 可追溯（R11）

| 算法 / 方法 | 论文 / 系统 | 本库落点 |
|---|---|---|
| 确定性仿真测试（DST） | FoundationDB 确定性仿真实践 | `run_des`/`replay_des`（同种子 → 同执行，`Rng` 驱动一切随机） |
| 离散事件仿真 | 标准 DES「事件按时间出队、处理生未来事件入队」 | `event_queue.mbt` + `World::step` |
| 动态偏序约简 | Flanagan & Godefroid 2005《Dynamic Partial-Order Reduction》 | `dpor.mbt`（`depends` + 持久集 + 回溯集） |
| 线性一致性 | Herlihy & Wing 1990；Wing & Gong 线性化点 | `linearizability.mbt`（`is_linearizable`） |
| 失败收缩 | Zeller delta debugging；QuickCheck shrinking | `shrink.mbt`（ddmin 式算子，单调 + 终止） |
| 随机源 | xorshift64（Marsaglia） | 既有 `rng.mbt`（仅移位 + 异或，三后端一致） |

每个新增文件头部以注释标注其对应论文与本设计章节（沿用既有 `sim.mbt`/`rng.mbt` 注释风格），实现 paper-to-code 可追溯（R11.1–11.4）。

### 开源对标与实现边界（R11.5/R11.6）

| 维度 | 本库 dst | FoundationDB sim | TigerBeetle VOPR | `madsim`/`turmoil` | Jepsen/Knossos |
|---|---|---|---|---|---|
| 确定性重放 | ✔（seed+trace） | ✔ | ✔ | ✔ | 部分（录制历史） |
| 故障模型 | 崩溃/延迟/丢弃/分区/重排/重复/时钟偏移/(拜占庭) | 丰富 | 丰富 | 网络为主 | 注入 + 观测 |
| 失败收缩 | ✔（delta debugging） | 有限 | 有限 | — | — |
| 穷尽 + DPOR 探索 | ✔ | — | — | — | — |
| 线性一致性检查 | ✔（Wing & Gong，可选） | — | — | — | ✔（Knossos） |
| 运行边界 | **纯内存确定性模型** | 真实代码 + 模拟网络 | 真实代码 | 真实 async 运行时 | 真实集群 |

**实现边界显式声明（R11.6）**：本实现为**纯内存确定性模型**，不接入真实网络、真实时间与操作系统线程；「任务/节点/消息」均为内存对象，故障是对内存事件流的确定性扰动。该边界换取完全可重放与可穷尽探索的优势，但不替代针对真实二进制的端到端验证。

---

## 三后端一致性与可移植性（R13.1/R13.4）

- **确定性随机源**：DES 运行时与全部属性测试经种子驱动 `Rng`（xorshift64）保证 `wasm-gc`/`js`/`native` 三后端逐位一致、可重放，任一后端输出分歧即判构建失败（R13.1/R1.4）。
- **可移植实现约束**：算法仅依赖整数（`Int`/`UInt64`/`Int64`）、数组、元组与 `String`，逻辑时间用 `UInt64` 避免浮点与平台差异；不使用后端特定 API。
- **native 前置**：文档与脚本要求 native 后端运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R10.5/R13.4）。
- **门禁聚合**：三后端测试、属性测试、可执行文档任一未过，`release_info_with_gates` 经 `@release_meta` 聚合阻止本方向进入 release-ready（R13.6）。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 |
|---|---|
| R1 确定性内核 + 逻辑时钟 | 4.1 虚拟时间/全序；4.6 `run_des` 同种子确定；P1/P2 |
| R2 事件队列 + 消息传递 | 4.3 `EventQueue`；4.4 `send`/`deliver` 因果序；P3/P4 |
| R3 丰富故障模型 | 4.5 `NetFaultKind`/`FaultPolicyEx` 与各故障语义；P5/P6 |
| R4 失败收缩 | 4.7 `shrink`/算子/`size`；P7/P8 |
| R5 有界穷尽探索 | 4.8 `explore_bounded`/`Schedule`；P9 |
| R6 DPOR | 4.9 `depends`/`explore_dpor`；P10/P11 |
| R7 不变量 + 线性一致性 | 4.10 `Invariant`/`is_linearizable`；P12/P13 |
| R8 轨迹持久化 + 跨会话重放 | 4.11 `serialize`/`deserialize`/`replay_des`；P14/P15 |
| R9 多副本 demo | 4.12 `demo.mbt` 端到端闭环 |
| R10 性能基准 | 4.13 `benches/dst_bench` + guard |
| R11 可解释性 + 边界 | 「算法说明」「开源对标与实现边界」 |
| R12 向后兼容 | 「设计原则与兼容契约」冻结列；4.5/4.6 `of_legacy` 桥；P1 |
| R13 质量门禁 | 「三后端一致性」+ 测试策略 + 正确性属性 |

---

## 测试策略（Testing Strategy）

**双轨测试**：单元测试锁定具体见证与边界/错误条件；属性测试以 `@infra_pbt` 覆盖通用不变量（每条 ≥100 迭代，R13.2）。

- **单元测试**：DES 入口与核心循环（R2.1）、各故障类型的代表性效果（分区阻断、重复双投递、时钟偏移、重排，R3.2–3.5）、收缩对非失败输入返回 `NotFailing`（R4.5）、`explore_bounded` 计数报告（R5.4）、`depends` 分类样例（R6.2）、不变量违反原因含名与时间戳（R7.3）、线性一致与非一致历史各一例（R7.4/7.5）、反序列化损坏输入报 `Malformed`（R8.5）、多副本 demo 闭环（R9.2–9.5）、既有 `run`/`replay`/`prop_replay` 回归（R12.1/12.2/12.3）。
- **属性测试**：见下「正确性属性」P1–P15，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`；新增场景生成器（任务集、故障序列、协议、深度上界、`DesResult`）以小规模、深度受限参数保证穷尽/ DPOR 可比对。
- **可执行文档**：`README.mbt.md` 覆盖虚拟时间与消息传递、丰富故障注入、收缩、探索与多副本 demo，全部经 `moon test *.mbt.md` 验证（R13.3）。
- **属性测试标注**：统一 `Feature: dst, Property {n}: {text}`，并以 `**Validates: Requirements X.Y**` 链接验收标准。


---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有合法执行下应恒成立行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。下列属性均以全称量化表述，复用 `@infra_pbt` 的 `holds_for_all`/`round_trip`（每条 ≥100 迭代，R13.2），统一标注 `Feature: dst, Property {n}`。*

### Property 1：同种子确定性（同种子 → 同执行）

*对任意*由生成器产出的种子 `seed` 与场景 `scenario`，`run_des(seed, scenario)` 两次调用产出的 `DesResult` 逐字段一致（`trace`、`status`、`finals` 完全相等）；且对「无消息、仅遗留故障」的场景，`DesScenario::of_legacy` 提升后的 DES 调度任务投影（`trace` 中 `EvScheduled` 的 `task_id` 序列）与既有 `run` 在同种子下的 `Scheduled` 任务序列一致。

**Validates: Requirements 1.1, 1.4, 1.5, 12.3**

### Property 2：虚拟时间单调性与事件全序

*对任意*由生成器产出的场景，`run_des` 产出的 `trace` 中相邻事件的逻辑时间戳单调不减；且同一逻辑时间戳内的相邻事件按「(任务 id 升序, 确定性次序键升序)」非降排列，即处理顺序严格遵循「(时间戳, 任务 id, 次序键)」全序。

**Validates: Requirements 1.2, 1.3, 1.6**

### Property 3：因果序保持（恰投递一次且不早于发送）

*对任意*由生成器产出的、不含丢弃（`Drop`）与分区（`Partition`）故障的消息收发场景，`trace` 中每条 `EvSend` 恰与一条 `EvDeliver`（按消息 `id` 配对）一一对应，反之亦然；且每对中 `EvDeliver` 的逻辑时间戳严格大于其 `EvSend` 的逻辑时间戳。

**Validates: Requirements 2.2, 2.4, 2.6**

### Property 4：仿真循环终止性

*对任意*由生成器产出的场景，`run_des` 在有限步内终止：其执行步数不超过 `scenario.max_steps`，且终止时事件队列为空或已达步数上限，不存在无限循环。

**Validates: Requirements 2.5**

### Property 5：故障注入点确定性与可重放

*对任意*由生成器产出的含故障场景与种子，两次 `run_des` 产出的 `EvFaulted` 事件序列在「(逻辑时间戳所对应的步序号, 目标任务 id, 故障类型)」上完全一致（故障在同一注入点触发）；且以该运行的 `seed` 与 `trace` 调用 `replay_des` 复现逐字段一致的 `DesResult`。

**Validates: Requirements 3.1, 3.7**

### Property 6：网络故障语义（分区隔离与消息重复）

*对任意*由生成器产出的场景：当某 `Partition` 故障在其生效区间 `[at_step, until_step)` 内有效时，`trace` 中不存在任何源任务与目标任务被划分到不同分组的 `EvDeliver` 事件（跨组投递被阻断）；当某消息命中 `Duplicate` 故障时，该消息（同一 `id`）在 `trace` 中恰对应两条独立的 `EvDeliver` 事件。

**Validates: Requirements 3.2, 3.4**

### Property 7：收缩保真（shrink fidelity）

*对任意*由生成器产出的使运行失败的场景 `scenario`，`shrink(seed, scenario)` 返回 `Minimal(s')`，且 `run_des(seed, s')` 仍以 `Failed` 终止（收缩过程仅接受仍复现原失败的候选，丢弃任何转为 `Completed` 者）。

**Validates: Requirements 4.1, 4.3, 4.6**

### Property 8：收缩终止与单调

*对任意*由生成器产出的失败场景 `scenario`，`shrink` 在有限步内终止，且返回的最小反例 `s'` 满足 `DesScenario::size(s') <= DesScenario::size(scenario)`；收缩过程每次接受的候选规模严格递减且有下界（≥0），最终结果在所采用算子下无法进一步缩小。

**Validates: Requirements 4.2, 4.4, 4.7**

### Property 9：有界穷尽探索完整性

*对任意*由生成器产出的小规模场景与深度上界 `depth`，`explore_bounded(seed, scenario, depth)` 枚举的交错集合恰等于参考枚举器在该深度内产出的全部可达交错集合（不遗漏、不重复计数），且 `ExploreReport.explored` 等于该集合大小；若存在失败交错，则 `failing` 携带的 `seed` 与 `trace` 经 `replay_des` 复现该失败。

**Validates: Requirements 5.1, 5.3, 5.5**

### Property 10：DPOR 可靠性（与穷尽同失败结论）

*对任意*由生成器产出的小规模场景，`explore_dpor` 与 `explore_bounded` 报告相同的「是否存在失败交错」结论（`failing.is_some()` 一致）；即 DPOR 在剪枝等价交错后仍对每个 Mazurkiewicz 迹等价类至少探索一个代表，绝不漏报任一可被穷尽探索发现的失败。

**Validates: Requirements 6.2, 6.3, 6.4, 6.5**

### Property 11：DPOR 约简有效性

*对任意*由生成器产出的小规模场景，`explore_dpor(seed, scenario, depth).explored` 不超过 `explore_bounded(seed, scenario, depth).explored`，即偏序约简所探索的交错数量不多于有界穷尽探索。

**Validates: Requirements 6.6**

### Property 12：不变量违反必检出

*对任意*由生成器产出的、必然违反某附加运行时不变量的场景，`run_des` 以 `Failed(reason)` 终止，且 `reason` 标识被违反的不变量名称与违反发生的逻辑时间戳（每个可观测状态上全部不变量均被求值，违反在发生当步被捕获）。

**Validates: Requirements 7.1, 7.2, 7.3, 7.6**

### Property 13：线性一致性判定可靠性

*对任意*由生成器在寄存器/单键 KV 顺序规约下**按构造生成的可线性化历史**，`is_linearizable` 返回 `Linearizable`；*对任意*按构造注入了违反实时先后序或顺序规约的历史，`is_linearizable` 返回 `NotLinearizable(conflict)` 且 `conflict` 非空（给出导致冲突的操作）。

**Validates: Requirements 7.4, 7.5**

### Property 14：序列化往返（round-trip）

*对任意*由生成器产出的 `DesResult` `r`，`deserialize_result(serialize_result(r))` 返回 `Ok(r')` 且 `r'` 与 `r` 逐字段一致（`seed`、`trace`、`status`、`finals` 完全相等）；等价地，经 `result_to_bytes`/`result_of_bytes` 适配的 `@infra_pbt.round_trip` 对 `r` 成立。

**Validates: Requirements 8.3, 8.6**

### Property 15：跨会话重放保真

*对任意*由生成器产出的运行结果 `r = run_des(seed, scenario)`，将其经 `serialize_result` 持久化再 `deserialize_result` 还原得到 `r'`，以 `r'.seed` 与 `r'.trace` 调用 `replay_des` 复现的 `DesResult` 其 `status` 与 `trace` 与原运行 `r` 逐字段一致（持久化—还原—重放闭环保真）。

**Validates: Requirements 8.4, 8.7**
