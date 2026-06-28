// ask.mbt —— 请求-响应（ask）与关联 id 注册表（任务 5.1，Requirement 4）。
//
// ask 与既有 `send`（tell）正交：`send` 语义零改动（Requirement 4.1）。本文件引入
// 一个**关联 id 注册表 `AskBroker[R]`**，把响应类型 `R` 与系统消息类型 `M` 解耦：
//
//   * `CorrelationId{value}` —— 唯一标识一次 ask 交互（Requirement 4.2）；
//   * `AskResult[R]` —— Replied(R) / Timeout 的确定性结果（Requirement 4.3 / 4.4）；
//   * `AskBroker[R]` —— 分配唯一 id、登记响应、消费一次（按 id 精确定位，无后端差异）。
//
// 系统级 `ask()` 函数在任务 12.1 追加（依赖 ActorSystem）。

// ───────────────────────────── 关联 id 与结果 ────────────────────────────

///|
/// 关联 id（correlation id）—— 唯一标识一次 ask 交互（Requirement 4.2）。
pub(all) struct CorrelationId {
  value : Int
} derive(Eq, Show)

///|
/// 一次 ask 的确定性结果（Requirement 4.3 / 4.4）。
///
///   * `Replied(R)` —— 收到匹配关联 id 的响应；
///   * `Timeout`    —— 在给定步数预算内未收到匹配响应。
pub(all) enum AskResult[R] {
  Replied(R)
  Timeout
} derive(Eq, Show)

// ───────────────────────────── ask 注册表 ────────────────────────────────

///|
/// ask 关联注册表（ask broker）—— 分配唯一 id、登记响应、消费一次。
///
/// `pending` 与 `consumed` 均以关联 id（`Int`）为键、按 id 精确定位读写，不依赖
/// `Map` 遍历顺序，故三后端逐位一致。`next` 单调递增保证运行内 id 两两不同
/// （Requirement 4.2 / 4.7）。
pub struct AskBroker[R] {
  mut next : Int
  pending : Map[Int, R]
  consumed : Map[Int, Bool]
}

///|
/// 创建一个空 ask 注册表（id 分配从 1 起）。
pub fn[R] AskBroker::new() -> AskBroker[R] {
  { next: 0, pending: {}, consumed: {} }
}

///|
/// 分配一个运行内唯一、单调递增的关联 id（Requirement 4.2 / 4.7）。
pub fn[R] AskBroker::allocate(self : AskBroker[R]) -> CorrelationId {
  self.next = self.next + 1
  { value: self.next }
}

///|
/// 被请求方回填某关联 id 的响应（Requirement 4.3）。
///
/// 已消费的 id 不再接受回填（保证响应至多被消费一次的语义边界，Requirement 4.5）。
pub fn[R] AskBroker::fulfill(
  self : AskBroker[R],
  id : CorrelationId,
  resp : R,
) -> Unit {
  match self.consumed.get(id.value) {
    Some(true) => return
    _ => ()
  }
  self.pending.set(id.value, resp)
}

///|
/// 轮询某关联 id 的结果并**消费一次**（Requirement 4.4 / 4.5）：
///
///   * 命中 `pending` 且未消费 —— 标记 `consumed`、移除 pending、返回 `Replied(resp)`；
///   * 未命中或已消费 —— 返回 `Timeout`（不二次消费、不串号）。
pub fn[R] AskBroker::poll(
  self : AskBroker[R],
  id : CorrelationId,
) -> AskResult[R] {
  match self.consumed.get(id.value) {
    Some(true) => return Timeout
    _ => ()
  }
  match self.pending.get(id.value) {
    Some(resp) => {
      self.consumed.set(id.value, true)
      self.pending.remove(id.value)
      Replied(resp)
    }
    None => Timeout
  }
}

///|
/// 某关联 id 是否已收到（尚未消费的）响应（观测用）。
pub fn[R] AskBroker::has_reply(self : AskBroker[R], id : CorrelationId) -> Bool {
  match self.consumed.get(id.value) {
    Some(true) => false
    _ => !(self.pending.get(id.value) is None)
  }
}

// ───────────────────────────── 系统级 ask（任务 12.1，R4） ───────────────

///|
/// 系统级请求-响应（ask，R4.1 / R4.3 / R4.4）—— 在 `ActorSystem` 上发起一次 ask：
///
///   1. `broker.allocate()` 得到唯一关联 id；
///   2. 以 `make_req(id)`（嵌入关联 id 的请求消息）`send` 给 `target`；
///   3. 驱动 `system` 至多 `budget` 步（每步处理一条消息）；
///   4. `broker.poll(id)`：命中匹配响应返回 `Replied(resp)`，否则返回 `Timeout`。
///
/// 被请求 actor 处理请求时应调用 `broker.fulfill(id, resp)` 回填响应。既有 `send`
/// （tell）语义保持不变（R4.1）。在 `budget` 内若被请求方提前回填且系统已空闲，
/// 提前结束驱动（确定性，不依赖墙钟）。
pub fn[S, M, R] ask(
  system : ActorSystem[S, M],
  broker : AskBroker[R],
  target : ActorRef[M],
  make_req : (CorrelationId) -> M,
  budget : Int,
) -> AskResult[R] {
  let id = broker.allocate()
  target.send(make_req(id))
  let mut steps = 0
  while steps < budget {
    // 已收到匹配响应即可提前结束驱动。
    if broker.has_reply(id) {
      break
    }
    if !(system.step()) {
      break
    }
    steps = steps + 1
  }
  broker.poll(id)
}
