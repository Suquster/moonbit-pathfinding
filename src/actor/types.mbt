// types.mbt —— Actor_Framework 的核心数据模型（任务 16.1）。
//
// 设计依据（design.md §「方向十：Actor_Framework」核心类型与流水线）：
//
//   pub struct ActorRef[M] { id : ActorId; mailbox : Mailbox[M] }
//   pub fn spawn[S, M](init : S, handle : (S, M) -> S) -> ActorRef[M]
//   pub fn send[M](self : ActorRef[M], msg : M) -> Unit
//   pub fn stop[M](self : ActorRef[M]) -> Unit
//
// 本文件锁定数据模型骨架（ActorId / Mailbox[M] / ActorRef[M] 及邮箱原语）；
// spawn / send / stop 接口桩位于 actor.mbt。`Mailbox[M]` 以纯数据的确定性
// 内存 FIFO 队列实现，刻意不耦合 `moonbitlang/async`（依赖处理详见 moon.pkg）。

// ───────────────────────────── actor 标识 ────────────────────────────────

///|
/// actor 标识（actor identifier）—— 进程内 actor 的唯一标识。
///
/// 以单调递增的 `Int` 承载，由 `spawn` 在派生时分配，保证进程内唯一
/// （见 actor.mbt 的 `spawn` / `reset_runtime`）。
pub(all) struct ActorId {
  value : Int
} derive(Eq, Debug)

// ───────────────────────────── 邮箱 ──────────────────────────────────────

///|
/// 邮箱（mailbox）—— 单个 actor 的消息队列。
///
/// 对应 design 的模块边界「mailbox（FIFO 队列 + 空闲挂起）」。本骨架以纯数据
/// 的确定性内存队列承载消息投递语义（Requirement 10.2）：`enqueue` 追加到队尾，
/// `dequeue` 从队首取出，从而保证 FIFO 顺序。`closed` 标记该邮箱是否已被
/// `stop` 请求关闭（停止后不再接收新消息）。
///
/// 注意：单 actor 一次仅处理一条消息的**串行处理**与**空邮箱挂起**等调度
/// 语义（Requirement 10.3 / 10.5）属任务 16.2，本类型仅提供其所需的队列原语。
pub(all) struct Mailbox[M] {
  mut items : Array[M]
  mut closed : Bool
  /// 队首游标：`items[head..]` 为待处理消息。出队 O(1) 推进游标，
  /// 已消费前缀过半时一次性压缩，避免数组头删 O(n) 的平方级退化。
  mut head : Int
}

///|
/// 创建一个空邮箱（未关闭）。
pub fn[M] Mailbox::new() -> Mailbox[M] {
  { items: [], closed: false, head: 0 }
}

///|
/// 将一条消息追加到邮箱队尾（FIFO 入队，Requirement 10.2）。
pub fn[M] Mailbox::enqueue(self : Mailbox[M], msg : M) -> Unit {
  self.items.push(msg)
}

///|
/// 从邮箱队首取出一条消息（FIFO 出队）；邮箱为空时返回 None。
///
/// 该原语供任务 16.2 的串行消息循环消费消息时复用。
pub fn[M] Mailbox::dequeue(self : Mailbox[M]) -> M? {
  if self.head >= self.items.length() {
    return None
  }
  let msg = self.items[self.head]
  self.head = self.head + 1
  let n = self.items.length()
  if self.head == n {
    self.items.clear()
    self.head = 0
  } else if self.head >= 64 && self.head * 2 >= n {
    // 压缩：把存活区间前移到数组头部，释放已消费空间。
    let live = n - self.head
    for i in 0..<live {
      self.items[i] = self.items[self.head + i]
    }
    while self.items.length() > live {
      ignore(self.items.pop())
    }
    self.head = 0
  }
  Some(msg)
}

///|
/// 查看邮箱队首消息但不取出；邮箱为空时返回 None。
pub fn[M] Mailbox::peek(self : Mailbox[M]) -> M? {
  if self.head >= self.items.length() {
    None
  } else {
    Some(self.items[self.head])
  }
}

///|
/// 邮箱是否为空（Requirement 10.5「空邮箱挂起」的判定原语）。
pub fn[M] Mailbox::is_empty(self : Mailbox[M]) -> Bool {
  self.head >= self.items.length()
}

///|
/// 邮箱当前排队的消息条数。
pub fn[M] Mailbox::length(self : Mailbox[M]) -> Int {
  self.items.length() - self.head
}

///|
/// 关闭邮箱（标记停止）。关闭后 `send` 不再接收新消息。
pub fn[M] Mailbox::close(self : Mailbox[M]) -> Unit {
  self.closed = true
}

///|
/// 邮箱是否已被关闭。
pub fn[M] Mailbox::is_closed(self : Mailbox[M]) -> Bool {
  self.closed
}

// ───────────────────────────── actor 引用句柄 ────────────────────────────

///|
/// actor 引用句柄（actor reference）—— `spawn` 返回的、可向 actor 投递消息的
/// 句柄（Requirement 10.1）。
///
/// 严格遵循 design 的类型签名 `{ id : ActorId; mailbox : Mailbox[M] }`：
/// `id` 唯一标识该 actor；`mailbox` 为其 FIFO 邮箱，`send` 经由它投递消息。
/// actor 内部的状态 `S` 与处理函数 `(S, M) -> S` 的串行调度执行属任务 16.2，
/// 故本骨架的句柄仅承载 design 锁定的这两个字段。
pub(all) struct ActorRef[M] {
  id : ActorId
  mailbox : Mailbox[M]
}
