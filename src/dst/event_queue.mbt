// event_queue.mbt —— DST_Framework 旗舰深化：全序事件队列（旁路新增，设计 4.3）。
//
// paper-to-code 追溯：离散事件仿真（DES）核心数据结构——按「逻辑时间戳」全序
// 排列的待处理事件优先队列。`World::step` 以「取全序最小事件 → 处理 → 入队未来
// 事件」为核心循环。
//
// 全序约定（R1.3，依赖 clock.mbt 的 `LogicalTime` 与全序定义）：
//
//     （逻辑时间戳升序，任务 id 升序，确定性次序键升序）
//
// 平局打破完全确定：`order_key` 由引擎单调入队序号 / 消息 id 给出，绝不并列。
// 本队列以**不可变 API** 暴露（`push` 返回新队列，`pop_min` 返回 `(最小元素,
// 余下队列)?`），与函数式仿真状态传递风格一致。

///|
/// 待处理事件的种类：投递某消息，或唤醒某任务执行一步。
pub(all) enum Pending {
  /// 把消息 `msg` 从 `from` 投递到 `to`。
  PDeliver(from~ : Int, to~ : Int, msg~ : Message)
  /// 唤醒任务 `task_id` 执行一步。
  PWake(task_id~ : Int)
} derive(Eq, Show)

///|
/// 队列中的待处理事件（内部调度元素），按全序 `(time, task_id, order_key)` 比较。
pub(all) struct QueuedEvent {
  time : LogicalTime
  task_id : Int
  order_key : UInt64
  pending : Pending
} derive(Eq, Show)

///|
/// 全序事件队列：以数组承载待处理事件，按 `(time, task_id, order_key)` 取最小。
pub struct EventQueue {
  events : Array[QueuedEvent]
}

///|
/// 构造空事件队列。
pub fn EventQueue::new() -> EventQueue {
  { events: [] }
}

///|
/// 队列是否为空。
pub fn EventQueue::is_empty(self : EventQueue) -> Bool {
  self.events.length() == 0
}

///|
/// 队列中待处理事件数量。
pub fn EventQueue::size(self : EventQueue) -> Int {
  self.events.length()
}

///|
/// 入队一个事件，返回新队列（不可变 API；不修改 `self`）。
pub fn EventQueue::push(self : EventQueue, ev : QueuedEvent) -> EventQueue {
  let next = self.events.copy()
  next.push(ev)
  { events: next }
}

///|
/// 全序比较：`a < b`（按时间戳、任务 id、次序键依次比较）返回 `true`。
fn qe_less(a : QueuedEvent, b : QueuedEvent) -> Bool {
  if a.time != b.time {
    a.time < b.time
  } else if a.task_id != b.task_id {
    a.task_id < b.task_id
  } else {
    a.order_key < b.order_key
  }
}

///|
/// 取出全序最小事件，返回 `(最小元素, 余下队列)`；空队列返回 `None`。
///
/// 余下队列保持其余元素原有相对顺序（确定性，且不修改 `self`）。
pub fn EventQueue::pop_min(
  self : EventQueue,
) -> (QueuedEvent, EventQueue)? {
  if self.events.length() == 0 {
    return None
  }
  let mut mi = 0
  for i in 1..<self.events.length() {
    if qe_less(self.events[i], self.events[mi]) {
      mi = i
    }
  }
  let chosen = self.events[mi]
  let rest : Array[QueuedEvent] = []
  for i in 0..<self.events.length() {
    if i != mi {
      rest.push(self.events[i])
    }
  }
  Some((chosen, { events: rest }))
}
