// scheduler.mbt —— Actor_Framework 邮箱 FIFO、串行处理与监督错误隔离（任务 16.2）。
//
// 本文件在 16.1 锁定的数据模型（ActorId / Mailbox[M] / ActorRef[M]）与高层接口桩
// （spawn / send / stop）之上，落地以下验收标准：
//   * 10.2 —— send 追加到邮箱队列（复用 16.1 的 `ActorRef::send` / `Mailbox::enqueue`）；
//   * 10.3 —— 单个 actor 一次仅处理一条消息（串行处理不变量）；
//   * 10.5 —— 邮箱为空时该 actor 挂起，不占用执行资源（调度器跳过空邮箱 actor）；
//   * 10.6 —— 处理消息期间的未捕获错误终止该 actor 并通知 supervisor，不影响其他 actor；
//   * 10.7 —— stop 在处理完当前消息后停止该 actor 的消息循环。
//
// 调度模型（scheduling model）—— 确定性内存邮箱 + 显式 run / step 同步驱动：
//   `moonbitlang/async` 在当前构建环境尚未稳定登记到 `moon.mod.json`（详见 16.1
//   的 moon.pkg 说明），为保证「三后端 moon test 全绿」这一硬性质量门禁，本任务
//   不引入异步运行时，而以 `Scheduler[S, M]` 承载确定性串行调度：
//     - 每次 `step` 至多处理「某一个就绪 actor」的「一条」消息（10.3 串行不变量）；
//     - 同一 actor 的消息按邮箱 FIFO 顺序出队处理（10.4 FIFO，由 Mailbox 保证）；
//     - 空邮箱 actor 被直接跳过、不消耗处理步（10.5 挂起语义）；
//     - `run_until_idle` 反复 `step` 直至无就绪 actor，得到确定性的处理序列。
//   待 `moonbitlang/async` 稳定后，可将该同步驱动替换为真实异步消息循环，而对外
//   契约（spawn / send / stop 与 FIFO / 串行 / 隔离不变量）保持不变。
//
// 关于未捕获错误的建模：本仓库各方向（如 serialization / regex_engine）统一以
// **结果/枚举显式信号** 表达失败（而非 MoonBit 的 `raise`），便于测试断言与后续
// 证明谓词引用，且无三后端差异风险。故本调度器要求处理函数返回 `ActorOutcome[S]`：
// `Updated(S)` 表示正常更新状态；`Errored(String)` 表示一次未捕获错误信号，由调度器
// 终止该 actor、通知 supervisor 并隔离其影响。

// ───────────────────────────── 处理结果与状态 ────────────────────────────

///|
/// actor 处理一条消息后的结果（actor outcome）—— 显式建模「正常 / 未捕获错误」。
///
/// 调度器以此判定是否更新状态或触发监督隔离（Requirement 10.6）：
///   * `Updated(S)` —— 正常处理完毕，actor 状态更新为新的 `S`；
///   * `Errored(String)` —— 处理期间发生未捕获错误，附带错误描述，调度器据此
///     终止该 actor 并通知其 supervisor。
pub(all) enum ActorOutcome[S] {
  /// 正常处理：以新状态替换当前状态。
  Updated(S)
  /// 未捕获错误信号：附带错误描述，触发终止与监督通知。
  Errored(String)
}

///|
/// actor 的生命周期状态（actor lifecycle status）—— 供调度与观测。
///
///   * `Running` —— 运行中，可继续处理消息；
///   * `Stopped` —— 因 `stop` 请求而停止消息循环（Requirement 10.7）；
///   * `Failed(String)` —— 因处理期未捕获错误被终止（Requirement 10.6），附带错误描述。
pub(all) enum ActorStatus {
  /// 运行中。
  Running
  /// 被 `stop` 请求停止消息循环。
  Stopped
  /// 因未捕获错误被终止（错误隔离）。
  Failed(String)
} derive(Eq, Debug)

// ───────────────────────────── actor 单元（内部） ────────────────────────

///|
/// actor 单元（actor cell）—— 调度器内部为每个 actor 维护的完整运行态。
///
/// 在 16.1 的 `ActorRef`（仅 `id` + `mailbox`）之外补齐串行调度所需的可变状态：
/// 当前状态 `state`、处理函数 `handle`、可选的监督回调 `supervisor` 与生命周期
/// 状态 `status`。`mailbox` 与对外的 `ActorRef` 共享同一对象，因而 `send` 经由
/// 引用句柄入队的消息会被调度器在此消费。
struct ActorCell[S, M] {
  id : ActorId
  mailbox : Mailbox[M]
  mut state : S
  handle : (S, M) -> ActorOutcome[S]
  supervisor : ((ActorId, String) -> Unit)?
  mut status : ActorStatus
}

// ───────────────────────────── 邮箱资源释放（内部） ──────────────────────

///|
/// 丢弃邮箱中全部排队消息（释放资源）。供 actor 因 `stop` 停止或因未捕获错误
/// 终止时清空其残留消息——这些消息按语义不再被处理（Requirement 10.6 / 10.7）。
fn[M] Mailbox::discard_all(self : Mailbox[M]) -> Unit {
  self.items = []
}

// ───────────────────────────── 调度器 ────────────────────────────────────

///|
/// actor 调度器（scheduler）—— 确定性串行驱动一组 actor 的消息循环。
///
/// 持有若干 `ActorCell`，以单调递增的 `next_id` 为派生的 actor 分配进程内唯一 id。
/// 通过 `step` / `run_until_idle` 串行消费各 actor 邮箱中的消息，保证：单 actor
/// 一次仅处理一条消息、同一 actor 的消息按 FIFO 顺序处理、空邮箱 actor 挂起不占步、
/// 单个 actor 的未捕获错误被隔离而不影响其他 actor。
pub struct Scheduler[S, M] {
  cells : Array[ActorCell[S, M]]
  mut next_id : Int
}

///|
/// 创建一个空调度器（id 分配源从 0 起）。
pub fn[S, M] Scheduler::new() -> Scheduler[S, M] {
  { cells: [], next_id: 0 }
}

///|
/// 在调度器中派生一个 actor，返回其引用句柄（Requirement 10.1 / 10.2）。
///
/// 分配唯一 id、创建空邮箱并登记 actor 单元（初始 `Running`）。`init` 为初始状态，
/// `handle : (S, M) -> ActorOutcome[S]` 为消息处理函数；可选的 `supervisor` 在该
/// actor 因未捕获错误终止时被调用（接收 `(ActorId, 错误描述)`，Requirement 10.6）。
/// 返回的 `ActorRef` 与内部单元共享同一邮箱，故 `ActorRef::send` 入队的消息会被
/// 后续 `step` / `run_until_idle` 消费。
pub fn[S, M] Scheduler::spawn(
  self : Scheduler[S, M],
  init : S,
  handle : (S, M) -> ActorOutcome[S],
  supervisor? : (ActorId, String) -> Unit,
) -> ActorRef[M] {
  self.next_id = self.next_id + 1
  let id : ActorId = { value: self.next_id }
  let mailbox : Mailbox[M] = Mailbox::new()
  self.cells.push({
    id,
    mailbox,
    state: init,
    handle,
    supervisor,
    status: Running,
  })
  { id, mailbox }
}

///|
/// 按 id 查找内部 actor 单元；未找到返回 None。
fn[S, M] Scheduler::cell_of(
  self : Scheduler[S, M],
  actor_ref : ActorRef[M],
) -> ActorCell[S, M]? {
  for cell in self.cells {
    if cell.id == actor_ref.id {
      return Some(cell)
    }
  }
  None
}

///|
/// 执行一步调度：至多处理「某一个就绪 actor」的「一条」消息（Requirement 10.3 串行
/// 不变量）。返回是否确实处理了一条消息（`true` 表示有进展，`false` 表示已空闲）。
///
/// 就绪判定按登记顺序遍历：
///   * 非 `Running`（已停止 / 已失败）的 actor 跳过；
///   * 邮箱已被 `stop` 关闭的 `Running` actor —— 标记为 `Stopped` 并跳过，从而在
///     「处理完当前消息后」停止其消息循环（Requirement 10.7），其残留消息不再处理；
///   * 邮箱为空的 actor 跳过（挂起，不占处理步，Requirement 10.5）；
///   * 否则从邮箱队首取出**一条**消息交给 `handle` 处理：
///       - `Updated(s)` 更新该 actor 状态；
///       - `Errored(e)` 终止该 actor（`Failed`）、关闭其邮箱并通知 supervisor
///         （Requirement 10.6），随即返回——其余 actor 不受影响，将在后续 `step`
///         中继续被处理。
pub fn[S, M] Scheduler::step(self : Scheduler[S, M]) -> Bool {
  for cell in self.cells {
    match cell.status {
      Running => ()
      _ => continue
    }
    // stop 请求：处理完先前消息后，此处停止消息循环（10.7）。
    if cell.mailbox.is_closed() {
      cell.mailbox.discard_all()
      cell.status = Stopped
      continue
    }
    // 空邮箱：挂起，不消耗处理步（10.5）。
    match cell.mailbox.dequeue() {
      None => continue
      Some(msg) => {
        // 串行处理：本步仅处理这一条消息（10.3）。
        match (cell.handle)(cell.state, msg) {
          Updated(next) => cell.state = next
          Errored(reason) => {
            // 错误隔离：终止该 actor 并通知 supervisor，不影响其他 actor（10.6）。
            cell.status = Failed(reason)
            cell.mailbox.close()
            cell.mailbox.discard_all()
            match cell.supervisor {
              Some(notify) => notify(cell.id, reason)
              None => ()
            }
          }
        }
        return true
      }
    }
  }
  false
}

///|
/// 反复 `step` 直至没有就绪 actor（所有邮箱已清空或所有 actor 已停止 / 失败）。
///
/// 由于处理函数为纯函数 `(S, M) -> ActorOutcome[S]`、无法再向邮箱投递新消息，
/// 待处理消息数单调递减，循环必然终止，得到确定性的整体处理序列。
pub fn[S, M] Scheduler::run_until_idle(self : Scheduler[S, M]) -> Unit {
  while self.step() {

  }
}

// ───────────────────────────── 观测辅助 ──────────────────────────────────

///|
/// 读取某 actor 的当前状态；未登记于本调度器时返回 None。
pub fn[S, M] Scheduler::state_of(
  self : Scheduler[S, M],
  actor_ref : ActorRef[M],
) -> S? {
  match self.cell_of(actor_ref) {
    Some(cell) => Some(cell.state)
    None => None
  }
}

///|
/// 读取某 actor 的生命周期状态；未登记于本调度器时返回 None。
pub fn[S, M] Scheduler::status_of(
  self : Scheduler[S, M],
  actor_ref : ActorRef[M],
) -> ActorStatus? {
  match self.cell_of(actor_ref) {
    Some(cell) => Some(cell.status)
    None => None
  }
}

///|
/// 某 actor 是否仍在运行（`Running`）。未登记时视为 false。
pub fn[S, M] Scheduler::is_running(
  self : Scheduler[S, M],
  actor_ref : ActorRef[M],
) -> Bool {
  match self.status_of(actor_ref) {
    Some(Running) => true
    _ => false
  }
}

///|
/// 某 actor 邮箱中当前排队的消息条数；未登记时返回 0。
pub fn[S, M] Scheduler::pending(
  self : Scheduler[S, M],
  actor_ref : ActorRef[M],
) -> Int {
  match self.cell_of(actor_ref) {
    Some(cell) => cell.mailbox.length()
    None => 0
  }
}
