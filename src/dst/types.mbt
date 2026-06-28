// types.mbt —— DST_Framework 的核心数据模型。
//
// 设计依据（design.md §「方向八：DST_Framework」核心类型与流水线）：
//
//   pub struct Sim { rng : Rng; tasks : Array[Task]; trace : Array[Event] }
//   pub fn step(self : Sim) -> Sim
//   pub fn inject_fault(self : Sim, policy : FaultPolicy) -> Sim
//   pub fn run(seed : UInt64, scenario : Scenario) -> SimResult
//   pub fn replay(seed : UInt64, trace : Array[Event]) -> SimResult
//
// 本文件锁定模块边界与数据模型：仿真由「任务 `Task`」组成，调度过程产生
// 「事件 `Event`」轨迹（trace）；故障由「故障策略 `FaultPolicy`」在指示注入
// 点触发；一次完整运行由「场景 `Scenario`」描述输入、由「仿真结果 `SimResult`」
// 承载（含可重放种子 + 事件轨迹 + 终态）。各接口的完整算法实现属任务 13.2。

///|
/// 故障类型（fault kind）—— 故障注入时施加于目标任务的扰动种类。
///
///   * `Crash` —— 任务崩溃（不再产出结果）；
///   * `Delay` —— 任务被延迟调度；
///   * `Drop`  —— 任务被丢弃（从调度集中移除）。
///
/// 任务 13.2 将依此在指示注入点触发对应故障行为。
pub(all) enum FaultKind {
  Crash
  Delay
  Drop
} derive(Eq, Debug)

///|
/// 仿真任务（simulation task）—— 确定性调度的最小单元。
///
///   * `id`   —— 任务唯一标识（调度与事件轨迹据此引用任务）；
///   * `name` —— 人类可读名称，便于诊断与可执行文档阅读。
pub(all) struct Task {
  id : Int
  name : String
} derive(Eq, Debug)

///|
/// 由标识与名称构造仿真任务。
pub fn Task::new(id : Int, name : String) -> Task {
  { id, name }
}

///|
/// 仿真事件（simulation event）—— 调度过程的可观测、可重放轨迹元素。
///
/// 每个事件携带其发生的步序号 `step` 与关联任务 `task_id`，使得「种子 +
/// 事件轨迹」足以完全复现一次运行（design.md「失败时输出可重放种子与事件
/// 轨迹」）。事件派生 `Eq + Show` 以支撑轨迹比对与往返/重放属性测试。
pub(all) enum Event {
  /// 任务在第 `step` 步被确定性调度器选中执行。
  Scheduled(step~ : Int, task_id~ : Int)
  /// 任务在第 `step` 步被注入故障 `kind`。
  Faulted(step~ : Int, task_id~ : Int, kind~ : FaultKind)
  /// 任务在第 `step` 步执行完成。
  Completed(step~ : Int, task_id~ : Int)
} derive(Eq, Debug)

///|
/// 故障策略（fault policy）—— 描述「在何处对何任务注入何种故障」。
///
///   * `at_step` —— 触发注入的步序号（确定性注入点）；
///   * `task_id` —— 受影响的任务标识；
///   * `kind`    —— 注入的故障类型。
pub(all) struct FaultPolicy {
  at_step : Int
  task_id : Int
  kind : FaultKind
} derive(Eq, Debug)

///|
/// 由注入点、目标任务与故障类型构造故障策略。
pub fn FaultPolicy::new(
  at_step : Int,
  task_id : Int,
  kind : FaultKind,
) -> FaultPolicy {
  { at_step, task_id, kind }
}

///|
/// 仿真场景（scenario）—— 一次 `run` 的完整输入描述。
///
///   * `tasks`     —— 参与调度的任务集合；
///   * `faults`    —— 本次运行中按注入点触发的故障策略；
///   * `max_steps` —— 调度步数上限（防止非终止场景无限运行）。
pub(all) struct Scenario {
  tasks : Array[Task]
  faults : Array[FaultPolicy]
  max_steps : Int
} derive(Eq, Debug)

///|
/// 由任务集、故障策略集与步数上限构造仿真场景。
pub fn Scenario::new(
  tasks : Array[Task],
  faults : Array[FaultPolicy],
  max_steps : Int,
) -> Scenario {
  { tasks, faults, max_steps }
}

///|
/// 仿真终态（simulation status）—— 一次运行结束时的结果分类。
///
///   * `Completed`     —— 所有任务在步数上限内正常完成；
///   * `Failed(reason)`—— 运行因故障或约束违反而失败，`reason` 给出可读原因。
///
/// 失败终态与 `SimResult` 中的可重放种子 + 事件轨迹共同支撑 `replay` 精确
/// 复现同一失败（Requirement 8.6）。
pub(all) enum SimStatus {
  Completed
  Failed(reason~ : String)
} derive(Eq, Debug)

///|
/// 公开状态类型的 `Show` 委托其 `Debug` 表示（与历史 `derive` 输出一致）。
pub impl Show for SimStatus with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// 仿真结果（simulation result）—— 一次 `run` / `replay` 的完整产出。
///
///   * `seed`   —— 驱动本次运行的种子（同种子 → 同调度序列 + 同终态）；
///   * `trace`  —— 调度过程的事件轨迹（可重放）；
///   * `status` —— 运行终态。
///
/// 「`seed` + `trace`」构成可重放凭据：`replay(seed, trace)` 应复现完全相同的
/// 失败（design.md 核心性质）。
pub(all) struct SimResult {
  seed : UInt64
  trace : Array[Event]
  status : SimStatus
} derive(Eq, Debug)

///|
/// 仿真状态机（simulator）—— 承载随机源、待调度任务与已产生事件轨迹。
///
/// 严格对应 design.md 签名 `Sim { rng : Rng; tasks : Array[Task];
/// trace : Array[Event] }`：
///   * `rng`   —— 确定性随机源，驱动 `step` 的任务选择；
///   * `tasks` —— 当前参与调度的任务集合；
///   * `trace` —— 截至当前已产生的事件轨迹。
pub struct Sim {
  rng : Rng
  tasks : Array[Task]
  trace : Array[Event]
}

///|
/// 以给定种子与任务集构造初始仿真状态（事件轨迹初始为空）。
pub fn Sim::new(seed : UInt64, tasks : Array[Task]) -> Sim {
  { rng: rng_new(seed), tasks, trace: [] }
}
