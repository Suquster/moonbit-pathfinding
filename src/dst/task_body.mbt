// task_body.mbt —— DST_Framework 旗舰深化：可执行任务体 + 确定性执行
// （旁路新增，设计「DST 可执行任务设计」，Requirement 8.1 / 8.2 / 8.4）。
//
// 现状与动机：既有 `Task { id, name }` 仅为占位，不承载任何可执行逻辑（仅供
// 调度选择与轨迹标识）。本文件新增 `ExecutableTask`，以一段「任务体」函数
// `(SimContext) -> TaskResult` 承载真实可执行逻辑，取代占位任务（AC1）。
//
// 与既有确定性执行机制的集成（复用而非另起炉灶）：
//   * 复用既有确定性随机源 `Rng`（rng.mbt，xorshift64：仅移位 + 异或，三后端
//     逐位一致），以 `rng_new(seed)` + `next_below(待调度数)` 做任务选择——与
//     `World::step` / `run_des` 的任务选择完全同源同算法，保证「同种子 → 同
//     调度序列」（AC4 确定性逻辑时钟 + seed 派生顺序）。
//   * 复用既有事件构造子 `SimEvent`（EvScheduled / EvCompleted / EvSend /
//     EvDeliver）与消息类型 `Message` 表达执行轨迹，使本执行循环产出的
//     `Array[SimEvent]` 可直接被既有 `replay_des` / `status_from_des_trace`
//     等轨迹消费者复用。
//   * 复用既有任务规范化范式：入口先按 `id` 升序规范化（与 `World::new` 一致），
//     消除输入排列对执行结果的影响。
//
// 为何自建调度循环而非直接套用 `run_des`：`run_des` 以 `Protocol`
// （`on_start` / `on_deliver`，按节点 id 取激励动作）驱动，而 `ExecutableTask`
// 以「每任务一段独立任务体 + `SimContext` 收集副作用」建模，二者数据流不同；
// 本任务签名亦不接收 `Protocol`。故此处自建一个与 `World` 同源（同 `Rng`、同
// `SimEvent`、同 id 规范化）的轻量确定性调度循环，承载可执行任务体语义。

///|
/// 逻辑时钟单步增量（仅按事件推进，不依赖真实墙钟，AC4）。
///
/// 每次唤醒一个任务体前，逻辑时钟自增该增量，得到严格递增的事件时间戳，使产出
/// 轨迹天然满足时间单调。命名常量化以避免散落的「魔法数字」。
let clock_tick : UInt64 = 1UL

///|
/// 任务体执行上下文（`SimContext`）：在任务体执行期间提供其所属节点 id 与当前
/// 逻辑时钟，并收集任务体产生的副作用——待发送消息与待追加日志。
///
/// `sends` 中每条为 `(to, payload, after)`：目标节点、消息负载、相对当前逻辑
/// 时钟的投递延迟；`appends` 为本节点本地日志的追加值序列。两者均由任务体经
/// `send` / `append` 累积，执行结束后由 `run_executable` 统一物化为事件轨迹。
pub struct SimContext {
  node_id : Int
  clock : UInt64
  sends : Array[(Int, Int, UInt64)]
  appends : Array[Int]
}

///|
/// 以给定节点 id 与逻辑时钟构造一个空副作用的执行上下文。
pub fn SimContext::new(node_id~ : Int, clock~ : UInt64) -> SimContext {
  { node_id, clock, sends: [], appends: [] }
}

///|
/// 记录一条「发送消息」副作用（AC2）：向节点 `to` 发送负载 `payload`，相对当前
/// 逻辑时钟延迟 `after` 后投递。仅追加到上下文缓冲，不在此刻产生事件。
pub fn SimContext::send(
  self : SimContext,
  to~ : Int,
  payload~ : Int,
  after~ : UInt64,
) -> Unit {
  self.sends.push((to, payload, after))
}

///|
/// 记录一条「追加本地日志」副作用（AC2）：向本节点日志追加值 `value`。仅追加到
/// 上下文缓冲，由调用方在执行结束后消费。
pub fn SimContext::append(self : SimContext, value~ : Int) -> Unit {
  self.appends.push(value)
}

///|
/// 任务体执行结果（`TaskResult`）：
///   * `TDone`            —— 任务完成，移出待调度集合，后续不再被选中；
///   * `TYield`           —— 任务让出本次时间片但未完成，保留在待调度集合，
///                           后续步骤仍可能被再次选中（受 `max_steps` 约束）；
///   * `TFailed(reason)`  —— 任务执行失败并附带原因，移出待调度集合。
pub(all) enum TaskResult {
  TDone
  TYield
  TFailed(reason~ : String)
} derive(Eq)

///|
/// 手写 `Show`（当前 MoonBit 版本 `derive(Show)` 已弃用，按规格要求手写以保持
/// 新文件零警告）：以与派生实现一致的形态输出构造子名称与字段。
pub impl Show for TaskResult with fn output(self : TaskResult, logger : &Logger) -> Unit {
  match self {
    TDone => logger.write_string("TDone")
    TYield => logger.write_string("TYield")
    TFailed(reason~) => {
      logger.write_string("TFailed(reason=")
      Show::output(reason, logger)
      logger.write_string(")")
    }
  }
}

///|
/// 可执行任务（`ExecutableTask`）：取代仅含 `{id, name}` 的占位 `Task`，以 `body`
/// 承载可执行逻辑（AC1）。`body` 签名为 `(SimContext) -> TaskResult`，执行时收到
/// 一个携带节点 id 与逻辑时钟的上下文，通过 `send` / `append` 产生副作用并返回
/// 执行结果。
pub struct ExecutableTask {
  id : Int
  name : String
  body : (SimContext) -> TaskResult
}

///|
/// 构造一个可执行任务。
pub fn ExecutableTask::new(
  id : Int,
  name : String,
  body : (SimContext) -> TaskResult,
) -> ExecutableTask {
  { id, name, body }
}

///|
/// 从待调度下标集合中移除位置 `pos` 的元素，其余保持原有相对顺序。
fn remove_at(pending : Array[Int], pos : Int) -> Array[Int] {
  let next : Array[Int] = []
  for i in 0..<pending.length() {
    if i != pos {
      next.push(pending[i])
    }
  }
  next
}

///|
/// 以确定性顺序依次执行可执行任务体，收集其副作用，产出执行轨迹
/// `Array[SimEvent]`（AC2 / AC4）。
///
/// 确定性保证（关键不变量，9.3 属性验证）：相同 `seed` + 相同任务集 → 逐事件
/// 相同的 `Array[SimEvent]`。三个支柱：
///   1. 入口按任务 `id` 升序规范化，消除输入排列差异；
///   2. 任务选择仅由 `rng_new(seed)` 的 `next_below` 驱动（与 `World::step`
///      同源同算法，三后端逐位一致）；
///   3. 逻辑时钟仅按事件推进（每次唤醒自增 `clock_tick`），不依赖真实墙钟。
///
/// 执行循环（步数上限 `max_steps`，达到上限或待调度集合空即终止）：
///   取确定性选中的任务 → 推进逻辑时钟并记录 `EvScheduled` → 执行任务体收集
///   副作用 → 把每条发送物化为 `EvSend` + `EvDeliver` → 记录 `EvCompleted` →
///   依据 `TaskResult` 更新待调度集合（`TDone` / `TFailed` 移出，`TYield` 保留）。
pub fn run_executable(
  seed : UInt64,
  tasks : Array[ExecutableTask],
  max_steps~ : Int,
) -> Array[SimEvent] {
  let trace : Array[SimEvent] = []
  // 规范化：按 id 升序，消除输入排列对执行结果的影响（与 World::new 一致）。
  let ordered = tasks.copy()
  ordered.sort_by(fn(a, b) { cmp_int(a.id, b.id) })
  // 待调度集合：仍需执行的任务在 `ordered` 中的下标，初始为全部。
  let mut pending : Array[Int] = []
  for i in 0..<ordered.length() {
    pending.push(i)
  }
  let rng = rng_new(seed)
  let mut clock = 0UL
  let mut msg_id = 0
  let mut steps = 0
  while steps < max_steps && pending.length() > 0 {
    // 确定性任务选择：复用 rng.next_below（与 World::step 的任务选择同源）。
    let pick = rng.next_below(pending.length())
    let task = ordered[pending[pick]]
    // 推进逻辑时钟到严格递增的新时间戳（AC4：仅按事件推进）。
    clock = clock + clock_tick
    let sched_time = clock
    trace.push(EvScheduled(time=sched_time, task_id=task.id))
    // 执行任务体，收集副作用（发送 / 追加）。
    let ctx = SimContext::new(node_id=task.id, clock=sched_time)
    let result = (task.body)(ctx)
    // 把发送副作用物化为 EvSend + EvDeliver（AC2）。
    for s in ctx.sends {
      let (to, payload, after) = s
      let msg = { id: msg_id, payload }
      msg_id = msg_id + 1
      trace.push(EvSend(time=sched_time, from=task.id, to~, msg~))
      trace.push(EvDeliver(time=sched_time + after, from=task.id, to~, msg~))
    }
    trace.push(EvCompleted(time=sched_time, task_id=task.id))
    // 依据任务结果更新待调度集合。
    match result {
      TDone => pending = remove_at(pending, pick)
      TFailed(_) => pending = remove_at(pending, pick)
      TYield => ()
    }
    steps = steps + 1
  }
  trace
}
