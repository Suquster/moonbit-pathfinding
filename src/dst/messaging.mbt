// messaging.mbt —— DST_Framework 旗舰深化：消息传递与因果序（旁路新增，设计 4.4）。
//
// 任务间通过 `send`（发出消息）与 `deliver`（投递消息）通信。本文件以同包扩展
// 方法旁路提供 `World::schedule_send` / `World::deliver`（`World` 结构在 des_sim.mbt）。
//
// 因果序保持（R2.2 / R2.3 / R2.4 / R2.6）：
//   * 消息 id 由 `World.msg_seq` 单调分配，使发送—投递配对确定；
//   * 投递时间 = 当前虚拟时间 + max(after, 1)（经时钟偏移调整后仍 >= 1），保证每条
//     `EvDeliver` 的逻辑时间戳严格大于其 `EvSend`（引擎按动作分配严格递增时间戳，
//     而投递动作必晚于其发送动作，故时间戳严格更大）；
//   * 在无丢弃（`Drop`）、无分区（`Partition`）下，每条 `EvSend` 恰对应一条
//     `EvDeliver`（按消息 id 一一配对）。
//
// 网络故障在投递路径上的确定性效果：
//   * `Duplicate`（发送方旗标）—— 为消息额外入队一条 `PDeliver`（不同次序键），
//     产生两条独立 `EvDeliver`（R3.4）；
//   * `Reorder`（发送方旗标）—— 以递减次序键安排投递，调换同时刻同目标消息顺序
//     而不丢失消息（R3.3）；
//   * `ClockSkew`（发送方本地偏移）—— 调整投递延迟，改变投递时刻（R3.5）；
//   * `Byzantine`（发送方旗标）—— 对不同对端发送因 `to` 而异的相互矛盾负载（R3.6）；
//   * `Partition` / `Drop` —— 在 `deliver` 时按 `is_blocked` 阻断跨组 / 非存活端点
//     投递（R3.2），被阻断的消息不产生 `EvDeliver`。

///|
/// 安排一次发送：记录 `EvSend`，按确定规则计算未来投递时间并向事件队列入队
/// `PDeliver`（含重复 / 重排 / 时钟偏移 / 拜占庭的确定性效果）。就地推进世界并返回。
pub fn World::schedule_send(
  self : World,
  from : Int,
  to : Int,
  payload : Int,
  after : LogicalTime,
) -> World {
  let mid = self.msg_seq
  self.msg_seq = self.msg_seq + 1
  let (skew, reorder, duplicate, byzantine) = match self.find_node(from) {
    Some(n) => (n.skew, n.reorder, n.duplicate, n.byzantine)
    None => (0L, false, false, false)
  }
  // 拜占庭：向不同对端发送相互矛盾内容（负载因 `to` 而异），默认关闭。
  let actual_payload = if byzantine { payload + to } else { payload }
  let msg : Message = { id: mid, payload: actual_payload }
  let t = self.clock
  self.trace.push(EvSend(time=t, from~, to~, msg~))
  // 投递时间 = 当前虚拟时间 + max(after, 1)，经时钟偏移调整后仍 >= 1。
  let base = if after < 1UL { 1UL } else { after }
  let adj0 = skewed_time(base, skew)
  let adj = if adj0 < 1UL { 1UL } else { adj0 }
  let dtime = t + adj
  let okey = self.next_order_key(reorder)
  self.queue = self.queue.push({
    time: dtime,
    task_id: to,
    order_key: okey,
    pending: PDeliver(from~, to~, msg~),
  })
  // 重复故障：为受影响消息额外入队一条独立投递（不同次序键）。
  if duplicate {
    let okey2 = self.next_order_key(reorder)
    self.queue = self.queue.push({
      time: dtime,
      task_id: to,
      order_key: okey2,
      pending: PDeliver(from~, to~, msg~),
    })
  }
  self
}

///|
/// 处理一次投递：在不受分区 / 丢弃 / 崩溃阻断时记录 `EvDeliver` 并调用
/// `protocol.on_deliver` 推进目标节点；被阻断则不产生 `EvDeliver`。就地推进并返回。
pub fn World::deliver(
  self : World,
  from : Int,
  to : Int,
  msg : Message,
) -> World {
  if self.is_blocked(from, to) {
    return self
  }
  match self.find_node(to) {
    None => self
    Some(n) => {
      if !n.alive {
        return self
      }
      let t = self.advance_clock()
      self.trace.push(EvDeliver(time=t, from~, to~, msg~))
      let (newapp, acts) = (self.protocol.on_deliver)(n.app, msg)
      n.app = newapp
      self.apply_actions(to, acts)
      self
    }
  }
}
