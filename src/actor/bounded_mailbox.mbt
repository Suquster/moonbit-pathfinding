// bounded_mailbox.mbt —— 有界邮箱与背压（任务 9.1，Requirement 9）。
//
// `BoundedMailbox[M]` 是**平行于既有 `Mailbox[M]`** 的新类型（不修改 `Mailbox`）：
//
//   * 未满时按 FIFO 入队，行为与无界邮箱一致（Requirement 9.2）；
//   * 满时按背压策略处置：DropNewest / DropOldest / Reject（Requirement 9.3~9.5）；
//   * 暴露可观测计数 (enqueued, dropped, rejected)（Requirement 9.6）；
//   * 计数守恒：每次 offer 恰增加三者之一（Requirement 9.8）。

// ───────────────────────────── 背压策略与结果 ───────────────────────────

///|
/// 背压策略（backpressure policy）（Requirement 9.1）。
///
///   * `DropNewest` —— 满时丢弃新消息，队列不变（Requirement 9.3）；
///   * `DropOldest` —— 满时移除队首最旧、新消息入队尾（Requirement 9.4）；
///   * `Reject`     —— 满时拒绝并返回可观测信号，内容不变（Requirement 9.5）。
pub(all) enum BackpressurePolicy {
  DropNewest
  DropOldest
  Reject
} derive(Eq, Debug)

///|
/// 投递结果（offer result）—— 可观测的背压信号（Requirement 9.5 / 9.6）。
pub(all) enum OfferResult {
  Enqueued
  Dropped
  Rejected
} derive(Eq, Debug)

// ───────────────────────────── 有界邮箱 ──────────────────────────────────

///|
/// 有界邮箱（bounded mailbox）—— 带容量上限与背压策略的 FIFO 队列。
pub struct BoundedMailbox[M] {
  capacity : Int
  policy : BackpressurePolicy
  items : Array[M]
  mut enqueued : Int
  mut dropped : Int
  mut rejected : Int
}

///|
/// 以容量上限与背压策略构造有界邮箱。容量 `< 0` 视为 0（恒满）。
pub fn[M] BoundedMailbox::new(
  capacity : Int,
  policy : BackpressurePolicy,
) -> BoundedMailbox[M] {
  let cap = if capacity < 0 { 0 } else { capacity }
  { capacity: cap, policy, items: [], enqueued: 0, dropped: 0, rejected: 0 }
}

///|
/// 投递一条消息，返回可观测结果（Requirement 9.2~9.6）。
///
/// 任意时刻 `length <= capacity`（Requirement 9.7）；每次 offer 恰增加
/// enqueued / dropped / rejected 之一（计数守恒，Requirement 9.8）。
pub fn[M] BoundedMailbox::offer(
  self : BoundedMailbox[M],
  msg : M,
) -> OfferResult {
  if self.items.length() < self.capacity {
    // 未满：FIFO 入队。
    self.items.push(msg)
    self.enqueued = self.enqueued + 1
    return Enqueued
  }
  // 已满：按策略处置。
  match self.policy {
    DropNewest => {
      self.dropped = self.dropped + 1
      Dropped
    }
    DropOldest => {
      // 容量为 0：无处可放，等价于丢弃新消息（保持 length <= capacity）。
      if self.capacity <= 0 {
        self.dropped = self.dropped + 1
        return Dropped
      }
      // 移除队首最旧，新消息入队尾；计一次丢弃（被挤出者）。
      if self.items.length() > 0 {
        let _ = self.items.remove(0)
      }
      self.items.push(msg)
      self.dropped = self.dropped + 1
      Dropped
    }
    Reject => {
      self.rejected = self.rejected + 1
      Rejected
    }
  }
}

///|
/// FIFO 出队一条消息；空队列返回 None。
pub fn[M] BoundedMailbox::dequeue(self : BoundedMailbox[M]) -> M? {
  if self.items.is_empty() {
    None
  } else {
    Some(self.items.remove(0))
  }
}

///|
/// 当前排队消息条数（恒 <= capacity，Requirement 9.7）。
pub fn[M] BoundedMailbox::length(self : BoundedMailbox[M]) -> Int {
  self.items.length()
}

///|
/// 容量上限。
pub fn[M] BoundedMailbox::capacity(self : BoundedMailbox[M]) -> Int {
  self.capacity
}

///|
/// 队列是否为空。
pub fn[M] BoundedMailbox::is_empty(self : BoundedMailbox[M]) -> Bool {
  self.items.is_empty()
}

///|
/// 可观测计数 (enqueued, dropped, rejected)（Requirement 9.6）。
pub fn[M] BoundedMailbox::counts(self : BoundedMailbox[M]) -> (Int, Int, Int) {
  (self.enqueued, self.dropped, self.rejected)
}
