// stash.mbt —— 消息暂存与保序回流（任务 6.1，Requirement 6）。
//
// `StashBuffer[M]` 为每个 actor 承载暂存消息：保序追加、整体回流到邮箱队首之前。
//
//   * `push`           —— stash 当前消息（追加，不立即处理，Requirement 6.1）；
//   * `drain_to_front` —— unstash_all：把暂存消息按原相对顺序置于邮箱待处理消息
//                          之前（Requirement 6.2），随后清空缓冲；
//   * `clear`          —— 重启 / 停止时清空缓冲（Requirement 6.4）。

///|
/// 暂存缓冲（stash buffer）—— 单个 actor 的暂存消息队列（保序）。
pub struct StashBuffer[M] {
  items : Array[M]
}

///|
/// 创建一个空暂存缓冲。
pub fn[M] StashBuffer::new() -> StashBuffer[M] {
  { items: [] }
}

///|
/// 把当前消息追加到暂存缓冲（不立即处理，Requirement 6.1）。
pub fn[M] StashBuffer::push(self : StashBuffer[M], msg : M) -> Unit {
  self.items.push(msg)
}

///|
/// 暂存缓冲当前条数。
pub fn[M] StashBuffer::length(self : StashBuffer[M]) -> Int {
  self.items.length()
}

///|
/// 暂存缓冲是否为空。
pub fn[M] StashBuffer::is_empty(self : StashBuffer[M]) -> Bool {
  self.items.is_empty()
}

///|
/// 清空暂存缓冲（重启 / 停止时调用，Requirement 6.4）。
pub fn[M] StashBuffer::clear(self : StashBuffer[M]) -> Unit {
  self.items.clear()
}

///|
/// 把暂存消息按原相对顺序置于邮箱**待处理消息之前**（unstash_all，Requirement 6.2），
/// 随后清空缓冲。
///
/// 保序实现要点：先取出邮箱现有全部消息（FIFO），清空邮箱，再依次入队「暂存序列 +
/// 原邮箱序列」，使暂存消息的相对顺序与其入缓冲顺序逐位一致，且整体位于原邮箱
/// 消息之前（Requirement 6.5）。
pub fn[M] StashBuffer::drain_to_front(
  self : StashBuffer[M],
  mailbox : Mailbox[M],
) -> Unit {
  if self.items.is_empty() {
    return
  }
  // 取出邮箱原有消息（按 FIFO 顺序）。
  let original : Array[M] = []
  while true {
    match mailbox.dequeue() {
      Some(m) => original.push(m)
      None => break
    }
  }
  // 先入队暂存序列（保持其相对顺序），再入队原邮箱序列。
  for m in self.items {
    mailbox.enqueue(m)
  }
  for m in original {
    mailbox.enqueue(m)
  }
  // 清空暂存缓冲。
  self.items.clear()
}
