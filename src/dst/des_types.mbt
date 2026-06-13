// des_types.mbt —— DST_Framework 旗舰深化：离散事件仿真（DES）数据模型（设计 4.2）。
//
// 「枚举不扩容、旁路平行扩展」取舍（R12.4）：既有 `Event` / `SimStatus` 为
// `pub(all) enum`，向其追加变体会破坏下游穷尽匹配。故本文件新增**带逻辑时间戳**
// 的富事件枚举 `SimEvent`（变体以 `Ev` 前缀与既有 `Event` 的 `Scheduled` /
// `Completed` / `Faulted` 区分，避免同包构造子歧义），并新增消息 / 节点 / 协议 /
// 场景 / 结果等 DES 专属类型；既有 `SimStatus`（`Completed` / `Failed(reason)`）
// 直接复用为 DES 终态，既有 `Task` 直接复用为节点标识。
//
// 纯数据（可派生 `Eq` / `Show`）以 `pub(all)` 暴露；承载函数值或可变运行态的
// 结构（`Node` / `Protocol` / `DesScenario`）以 `pub` 暴露且不派生，与既有 `Sim`
// 同例。

///|
/// 任务间传递的消息（纯内存模型，design.md「实现边界：纯内存确定性模型」）。
///
///   * `id`      —— 确定性发送序号（由引擎 `msg_seq` 单调分配），用于因果追踪、
///                  发送—投递配对、重排与重复；
///   * `payload` —— 简化负载（如待复制的日志值）。
pub(all) struct Message {
  id : Int
  payload : Int
} derive(Eq, Show)

///|
/// DES 富事件——既有 `Event` 的旁路扩展：每个事件携带其发生的逻辑时间戳 `time`，
/// 并在 `Scheduled` / `Completed` / `Faulted` 之外新增消息事件 `EvSend` / `EvDeliver`。
///
/// 变体名以 `Ev` 前缀与既有 `Event` 区分，避免同包构造子歧义（R12.4）。派生
/// `Eq` / `Show` 以支撑轨迹比对、序列化往返与重放属性测试。
pub(all) enum SimEvent {
  /// 任务在逻辑时间 `time` 被确定性调度器选中执行。
  EvScheduled(time~ : LogicalTime, task_id~ : Int)
  /// 任务在逻辑时间 `time` 执行完成。
  EvCompleted(time~ : LogicalTime, task_id~ : Int)
  /// 任务在逻辑时间 `time` 被注入故障 `kind`（扩展故障类型 `NetFaultKind`）。
  EvFaulted(time~ : LogicalTime, task_id~ : Int, kind~ : NetFaultKind)
  /// 任务 `from` 在逻辑时间 `time` 向 `to` 发出消息 `msg`。
  EvSend(time~ : LogicalTime, from~ : Int, to~ : Int, msg~ : Message)
  /// 消息 `msg`（源 `from`、目标 `to`）在逻辑时间 `time` 被投递。
  EvDeliver(time~ : LogicalTime, from~ : Int, to~ : Int, msg~ : Message)
} derive(Eq, Show)

///|
/// 返回事件的逻辑时间戳（全序第一键）。
pub fn SimEvent::time_of(self : SimEvent) -> LogicalTime {
  match self {
    EvScheduled(time~, ..) => time
    EvCompleted(time~, ..) => time
    EvFaulted(time~, ..) => time
    EvSend(time~, ..) => time
    EvDeliver(time~, ..) => time
  }
}

///|
/// 返回事件的「主任务 id」（全序第二键）：调度 / 完成 / 故障取其 `task_id`，
/// 发送取源 `from`，投递取目标 `to`（与引擎「每个处理动作归属单一节点」一致）。
pub fn SimEvent::actor_of(self : SimEvent) -> Int {
  match self {
    EvScheduled(task_id~, ..) => task_id
    EvCompleted(task_id~, ..) => task_id
    EvFaulted(task_id~, ..) => task_id
    EvSend(from~, ..) => from
    EvDeliver(to~, ..) => to
  }
}

///|
/// 节点应用层状态（可观测全局状态的组成单元，供不变量 / 一致性检查）。
///
///   * `log` —— 复制日志（多副本 demo 的核心可观测量）；
///   * `kv`  —— 通用键值视图（KV demo / 线性一致性历史使用）。
pub(all) struct NodeApp {
  log : Array[Int]
  kv : Array[(String, Int)]
} derive(Eq, Show)

///|
/// 构造一个初始应用状态（空日志、空键值）。
pub fn NodeApp::empty() -> NodeApp {
  { log: [], kv: [] }
}

///|
/// 节点运行时（承载应用状态、本地时钟偏移与故障旗标），不派生（含运行态）。
///
///   * `app`       —— 节点应用层状态；
///   * `skew`      —— `ClockSkew` 故障施加的本地逻辑时钟偏移；
///   * `alive`     —— 是否存活（`Crash` / `Drop` 故障将其置否，阻断其消息）；
///   * `reorder` / `duplicate` / `byzantine` —— 对应网络 / 拜占庭故障旗标，
///     默认关闭，由故障注入显式开启。
pub struct Node {
  id : Int
  name : String
  mut app : NodeApp
  mut skew : Int64
  mut alive : Bool
  mut reorder : Bool
  mut duplicate : Bool
  mut byzantine : Bool
}

///|
/// 协议动作——节点处理事件后请求引擎执行的副作用（纯描述，不直接修改世界）。
pub(all) enum Action {
  /// `after` 个逻辑时间单位后向 `to` 投递负载 `payload`。
  ActSend(to~ : Int, payload~ : Int, after~ : LogicalTime)
  /// 向本节点复制日志追加 `value`。
  ActAppend(value~ : Int)
} derive(Eq, Show)

///|
/// 协议——以纯转移函数描述节点行为（函数值字段，故不派生）。
///
///   * `init`       —— 由节点 id 构造初始应用状态；
///   * `on_deliver` —— 收到消息的纯转移：返回新应用状态与待执行动作序列；
///   * `on_start`   —— 启动激励（如领导者首次广播），由节点 id 产生动作序列。
pub struct Protocol {
  init : (Int) -> NodeApp
  on_deliver : (NodeApp, Message) -> (NodeApp, Array[Action])
  on_start : (Int) -> Array[Action]
}

///|
/// 由三个转移函数构造协议。
pub fn Protocol::new(
  init : (Int) -> NodeApp,
  on_deliver : (NodeApp, Message) -> (NodeApp, Array[Action]),
  on_start : (Int) -> Array[Action],
) -> Protocol {
  { init, on_deliver, on_start }
}

///|
/// 空协议（null protocol）：节点无应用状态、不发送、不响应。
///
/// 用于「无消息、仅遗留故障」的 `DesScenario::of_legacy` 提升场景，使 DES 调度
/// 退化为与既有 `run` 等价的纯任务调度，支撑两条流水线的差分一致性验证（P1）。
pub fn null_protocol() -> Protocol {
  Protocol::new(fn(_id) { NodeApp::empty() }, fn(app, _msg) { (app, []) }, fn(
    _id,
  ) {
    []
  })
}

///|
/// DES 场景——一次 `run_des` 的完整输入；含函数值（protocol / invariants），不派生。
///
///   * `tasks`      —— 参与调度的任务集合（复用既有 `Task`）；
///   * `faults`     —— 扩展故障策略集（`FaultPolicyEx`）；
///   * `invariants` —— 运行时不变量集（每个可观测状态求值）；
///   * `protocol`   —— 节点行为协议；
///   * `max_steps`  —— 仿真步数上限。
pub struct DesScenario {
  tasks : Array[Task]
  faults : Array[FaultPolicyEx]
  invariants : Array[Invariant]
  protocol : Protocol
  max_steps : Int
}

///|
/// 构造一个 DES 场景。
pub fn DesScenario::new(
  tasks : Array[Task],
  faults : Array[FaultPolicyEx],
  invariants : Array[Invariant],
  protocol : Protocol,
  max_steps : Int,
) -> DesScenario {
  { tasks, faults, invariants, protocol, max_steps }
}

///|
/// DES 结果——可重放凭据（`seed` + `trace`）+ 终态 + 各节点终态；纯数据，派生
/// `Eq` / `Show`。
///
///   * `seed`   —— 驱动本次运行的种子（同种子 → 同执行）；
///   * `trace`  —— 富事件轨迹（可重放、可序列化）；
///   * `status` —— 运行终态（复用既有 `SimStatus`）；
///   * `finals` —— `(节点 id, 终态应用状态)`，按 id 升序（供副本一致性校验）。
pub(all) struct DesResult {
  seed : UInt64
  trace : Array[SimEvent]
  status : SimStatus
  finals : Array[(Int, NodeApp)]
} derive(Eq, Show)
