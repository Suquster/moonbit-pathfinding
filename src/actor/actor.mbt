// actor.mbt —— Actor_Framework 高层接口桩（任务 16.1）。
//
// 本文件在数据模型（types.mbt）之上提供 design 锁定的三个高层接口的**骨架桩**：
//   spawn / send / stop
//
// 本任务（16.1）覆盖的验收标准：
//   * 10.1 —— spawn 返回一个可用于向该 actor 投递消息的引用句柄；
//   * 10.2 —— send 将消息追加到该 actor 的邮箱队列。
//
// 以下语义属任务 16.2，本文件不实现（仅以桩占位 + 注释说明）：
//   * 10.3 —— 单 actor 一次仅处理一条消息（串行处理不变量）；
//   * 10.4 —— 单发送者消息序列按投递顺序处理（FIFO 顺序不变量）；
//   * 10.5 —— 空邮箱时挂起不占执行资源；
//   * 10.6 —— 处理期未捕获错误终止该 actor 并通知 supervisor，不影响其他 actor；
//   * 10.7 —— stop 在处理完当前消息后停止消息循环并释放资源。
//
// 关于 moonbitlang/async：本骨架不引入 async 运行时，以确定性内存邮箱表达
// 消息投递；真实异步消息循环待 16.2 以同步 run/step 模型模拟（详见 moon.pkg）。

// ───────────────────────────── 运行时（id 分配源） ───────────────────────

///|
/// actor 运行时的可变状态。骨架阶段仅承载单调递增的 actor id 分配源；
/// 任务 16.2 将在此基础上扩展确定性调度所需的运行时状态（就绪队列等）。
priv struct ActorRuntime {
  mut next_id : Int
}

///|
/// 进程级 actor 运行时单例。`next_id` 从 0 起，每次 `spawn` 自增后分配。
let runtime : ActorRuntime = { next_id: 0 }

///|
/// 分配一个进程内唯一、单调递增的 actor id。
fn alloc_actor_id() -> ActorId {
  runtime.next_id = runtime.next_id + 1
  { value: runtime.next_id }
}

///|
/// 将 actor 运行时重置为初始状态（id 分配源归零）。
///
/// 主要供测试在用例之间隔离全局状态，使 id 分配可预期。
pub fn reset_runtime() -> Unit {
  runtime.next_id = 0
}

// ───────────────────────────── 核心接口桩 ───────────────────────────────

///|
/// 派生（spawn）一个 actor，返回其引用句柄（Requirement 10.1）。
///
/// 骨架行为：分配唯一 actor id，创建空邮箱，返回 `ActorRef`。`init`（初始
/// 状态）与 `handle`（消息处理函数 `(S, M) -> S`）的**串行调度执行**属任务
/// 16.2，本桩暂不绑定二者（以 `ignore` 显式标注其在骨架阶段未被消费），从而
/// 保持 design 锁定的 `ActorRef[M] = { id; mailbox }` 公开形状不变。
pub fn[S, M] spawn(init : S, handle : (S, M) -> S) -> ActorRef[M] {
  ignore(init)
  ignore(handle)
  { id: alloc_actor_id(), mailbox: Mailbox::new() }
}

///|
/// 向某个 actor 投递一条消息（Requirement 10.2）。
///
/// 骨架行为：将消息追加到该 actor 的邮箱队列（FIFO 入队）。若该 actor 已被
/// `stop` 请求停止（邮箱关闭），则丢弃该消息不再入队。实际由消息循环串行
/// 消费这些消息（Requirement 10.3/10.4）属任务 16.2。
pub fn[M] ActorRef::send(self : ActorRef[M], msg : M) -> Unit {
  if self.mailbox.is_closed() {
    return
  }
  self.mailbox.enqueue(msg)
}

///|
/// 请求停止某个 actor（Requirement 10.7 的桩）。
///
/// 骨架行为：关闭其邮箱（不再接收新消息）。完整语义——「在处理完当前消息后
/// 停止消息循环并释放相关资源」——属任务 16.2。
pub fn[M] ActorRef::stop(self : ActorRef[M]) -> Unit {
  self.mailbox.close()
}

///|
/// 返回该 actor 邮箱中当前排队的消息条数（便于观测与测试）。
pub fn[M] ActorRef::pending(self : ActorRef[M]) -> Int {
  self.mailbox.length()
}
