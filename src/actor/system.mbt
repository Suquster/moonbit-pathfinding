// system.mbt —— 旗舰驱动器 ActorSystem（任务 11.2 / 11.3 / 11.6 / 11.14，整合 R1~R10）。
//
// `ActorSystem[S, M]` 是承载全部新能力的**平行驱动器**，与既有冻结的 `Scheduler[S, M]`
// 平行共存、互不影响。它在确定性串行循环之上接线：
//   行为栈（become/unbecome）、生命周期钩子与重启、监督策略/指令/强度与监督树、
//   消息暂存（stash）、死亡监视（watch/Terminated）、有界邮箱与背压、种子驱动
//   调度与 trace 重放。
//
// 失败一律以显式枚举信号（`ActorOutcome::Errored`）表达，不使用 `raise`；调度顺序
// 由确定性 `Rng`（种子）决定，**同种子 → 同 trace → 可重放**，保证三后端一致。

// ───────────────────────────── 受监督 actor 单元（私有） ─────────────────

///|
/// 受监督 actor 单元（supervised cell）—— `ActorSystem` 内部为每个 actor 维护的
/// 完整运行态。以 `pub(all)` 暴露（仅新增），因含闭包字段故不派生 `Eq` / `Show`。
pub(all) struct SupervisedCell[S, M] {
  id : ActorId
  mailbox : Mailbox[M] // 复用既有 FIFO 邮箱原语（亦作有界邮箱的 staging）
  bounded : BoundedMailbox[M]? // 配置有界时启用（R9）
  mut state : S
  init_state : S // 重启基准（R3.5）
  behaviors : Array[Behavior[S, M]] // 行为栈（R5），栈底恒为初始行为
  stash : StashBuffer[M] // 暂存缓冲（R6）
  hooks : LifecycleHooks[S] // 生命周期钩子（R3）
  mut directive : Directive // 失败处置（R2），可被 supervise / set_directive 覆盖
  mut status : ActorStatus // 复用既有生命周期枚举
  mut started : Bool // pre_start 是否已调用（R3.1 / 3.7）
  restart_times : Array[Int] // 逻辑时钟上的重启时刻（强度窗口，R2.5~2.7；窗口外旧时刻会被修剪）
  mut restart_total : Int // 累计重启次数（观测用，不随窗口修剪变化）
  ctx_cache : ActorContext[S, M] // 常驻处理上下文（每消息复用，免逐消息分配）
}

// ───────────────────────────── 旗舰系统结构 ──────────────────────────────

///|
/// 旗舰驱动器（actor system）—— 整合全部新能力的平行系统。
pub struct ActorSystem[S, M] {
  cells : Array[SupervisedCell[S, M]]
  supervisors : Map[Int, SupervisorSpec] // supervisor id -> 配置
  parents : Map[Int, Int] // 子 id -> supervisor id（监督树，R1.5）
  children : Map[Int, Array[Int]] // supervisor id -> 有序子 id 列表
  watches : WatchRegistry[M] // 死亡监视注册表（R7）
  trace : Array[TraceEvent] // 处理序列（R10.3）
  mut clock : Int // 逻辑时钟（处理一条消息加一）
  mut rng : @infra_pbt.Rng? // 种子驱动调度；None 时退化为登记顺序
  mut next_id : Int
  mut cross_dirty : Bool // 跨单元事件标记（Terminated 投递 / 监督处置），驱动有序快路径回扫
}

///|
/// 无种子构造：就绪 actor 按登记顺序选取（与既有 Scheduler 行为对齐）。
pub fn[S, M] ActorSystem::new() -> ActorSystem[S, M] {
  {
    cells: [],
    supervisors: Map([]),
    parents: Map([]),
    children: Map([]),
    watches: WatchRegistry::new(),
    trace: [],
    clock: 0,
    rng: None,
    next_id: 0,
    cross_dirty: false,
  }
}

///|
/// 种子构造：以确定性 `Rng` 选取就绪 actor，支持重放（R10.1）。
pub fn[S, M] ActorSystem::with_seed(seed : UInt64) -> ActorSystem[S, M] {
  let sys = ActorSystem::new()
  sys.rng = Some(@infra_pbt.rng_new(seed))
  sys
}

///|
/// 默认监督者配置：OneForOne + 宽松强度 + Restart（当 spawn 提供 supervisor 但未
/// 经 `supervise` 明确配置时使用）。
fn default_spec() -> SupervisorSpec {
  SupervisorSpec::new(OneForOne, RestartIntensity::new(1000000, 1), Restart)
}

// ───────────────────────────── 内部查找辅助 ─────────────────────────────

///|
/// 按 id 查找内部单元；未找到返回 None。
///
/// id 由 `spawn` 顺次分配（1 起）、单元只增不删，故 `cells[id - 1]` 即目标，
/// O(1) 定位（防御性校验 id 一致，杜绝顺序假设失效时的错配）。
fn[S, M] ActorSystem::cell_by_id(
  self : ActorSystem[S, M],
  id : Int,
) -> SupervisedCell[S, M]? {
  if id >= 1 && id <= self.cells.length() {
    let cell = self.cells[id - 1]
    if cell.id.value == id {
      return Some(cell)
    }
  }
  for cell in self.cells {
    if cell.id.value == id {
      return Some(cell)
    }
  }
  None
}

///|
/// 把子 id 追加到某 supervisor 的有序子列表。
fn[S, M] ActorSystem::add_child(
  self : ActorSystem[S, M],
  sup_id : Int,
  child_id : Int,
) -> Unit {
  match self.children.get(sup_id) {
    Some(kids) => kids.push(child_id)
    None => self.children.set(sup_id, [child_id])
  }
}

// ───────────────────────────── 派生与监督登记 ───────────────────────────

///|
/// 派生 actor（R14.4 / R1.1 / R3.1）—— 行为 + 初始状态 + 可选钩子 / 监督者 /
/// 指令 / 有界邮箱容量。返回的 `ActorRef` 与内部单元共享邮箱，故 `send` 入队的
/// 消息会被 `step` / `run_until_idle` 消费。
pub fn[S, M] ActorSystem::spawn(
  self : ActorSystem[S, M],
  init : S,
  behavior : Behavior[S, M],
  hooks? : LifecycleHooks[S],
  supervisor? : ActorRef[M],
  directive? : Directive,
  bounded? : (Int, BackpressurePolicy),
) -> ActorRef[M] {
  self.next_id = self.next_id + 1
  let id : ActorId = { value: self.next_id }
  let mailbox : Mailbox[M] = Mailbox::new()
  let hk = match hooks {
    Some(h) => h
    None => LifecycleHooks::identity()
  }
  let bnd : BoundedMailbox[M]? = match bounded {
    Some((cap, pol)) => Some(BoundedMailbox::new(cap, pol))
    None => None
  }
  let dir = match directive {
    Some(d) => d
    None => Restart
  }
  self.cells.push({
    id,
    mailbox,
    bounded: bnd,
    state: init,
    init_state: init,
    behaviors: behavior_stack_new(behavior),
    stash: StashBuffer::new(),
    hooks: hk,
    directive: dir,
    status: Running,
    started: false,
    restart_times: [],
    restart_total: 0,
    ctx_cache: ActorContext::new(id),
  })
  match supervisor {
    Some(sup) => {
      self.parents.set(id.value, sup.id.value)
      self.add_child(sup.id.value, id.value)
      if self.supervisors.get(sup.id.value) is None {
        self.supervisors.set(sup.id.value, default_spec())
      }
    }
    None => ()
  }
  { id, mailbox }
}

///|
/// 把一组子置于某监督策略与强度之下（建立 / 覆盖监督树节点，R1.1）。
///
/// 设定该 supervisor 的配置与**有序子列表**，并把每个子的处置指令设为
/// `spec.default_directive`（如需 per-child 覆盖，随后调用 `set_directive`）。
pub fn[S, M] ActorSystem::supervise(
  self : ActorSystem[S, M],
  supervisor : ActorRef[M],
  spec : SupervisorSpec,
  children : Array[ActorRef[M]],
) -> Unit {
  self.supervisors.set(supervisor.id.value, spec)
  let ids : Array[Int] = []
  for c in children {
    ids.push(c.id.value)
    self.parents.set(c.id.value, supervisor.id.value)
    match self.cell_by_id(c.id.value) {
      Some(cell) => cell.directive = spec.default_directive
      None => ()
    }
  }
  self.children.set(supervisor.id.value, ids)
}

///|
/// 覆盖某个子 actor 的失败处置指令（per-child override，R2.1）。
pub fn[S, M] ActorSystem::set_directive(
  self : ActorSystem[S, M],
  child : ActorRef[M],
  directive : Directive,
) -> Unit {
  match self.cell_by_id(child.id.value) {
    Some(cell) => cell.directive = directive
    None => ()
  }
}

// ───────────────────────────── 邮箱 / 有界邮箱接线 ───────────────────────

///|
/// 把 staging 邮箱中的消息按 FIFO 转移进有界邮箱（应用背压计数），无界则空操作。
fn[S, M] ActorSystem::sync_bounded(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
) -> Unit {
  ignore(self)
  match cell.bounded {
    Some(b) =>
      while true {
        match cell.mailbox.dequeue() {
          Some(m) => {
            let _ = b.offer(m)
          }
          None => break
        }
      }
    None => ()
  }
}

///|
/// 单元当前可处理消息条数（有界则取有界队列长度）。
fn[S, M] ActorSystem::cell_pending(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
) -> Int {
  ignore(self)
  match cell.bounded {
    Some(b) => b.length()
    None => cell.mailbox.length()
  }
}

///|
/// 从单元 FIFO 取一条消息（有界则从有界队列取）。
fn[S, M] ActorSystem::cell_dequeue(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
) -> M? {
  ignore(self)
  match cell.bounded {
    Some(b) => b.dequeue()
    None => cell.mailbox.dequeue()
  }
}

///|
/// 向某 actor 投递一条系统构造的消息（用于 Terminated 通知投递）；仅当目标
/// Running 且邮箱未关闭时入队（staging，有界由后续 sync_bounded 转移）。
fn[S, M] ActorSystem::enqueue_msg(
  self : ActorSystem[S, M],
  target_id : Int,
  msg : M,
) -> Unit {
  match self.cell_by_id(target_id) {
    Some(c) =>
      if c.status is Running && !c.mailbox.is_closed() {
        c.mailbox.enqueue(msg)
        self.cross_dirty = true
      }
    None => ()
  }
}

// ───────────────────────────── 终止与监视投递（R7） ─────────────────────

///|
/// 某 target 的终止原因（用于 watch 已终止目标的立即投递，R7.4）；Running / 未知返回 None。
fn[S, M] ActorSystem::reason_of_terminated(
  self : ActorSystem[S, M],
  target_id : Int,
) -> TerminationReason? {
  match self.cell_by_id(target_id) {
    Some(c) =>
      match c.status {
        Stopped => Some(StoppedNormally)
        Failed(e) => Some(FailedWith(e))
        Running => None
      }
    None => None
  }
}

///|
/// 向监视 `target` 的全部 active 监视者投递一条 Terminated（经适配器映射为 M），
/// 同一监视者×同一终止至多一条（R7.2 / 7.5 / 7.6）。
fn[S, M] ActorSystem::deliver_terminated(
  self : ActorSystem[S, M],
  target_id : Int,
  reason : TerminationReason,
) -> Unit {
  let deliveries = self.watches.collect_terminations(
    { value: target_id },
    reason,
  )
  for d in deliveries {
    self.enqueue_msg(d.0.value, d.1)
  }
}

///|
/// 登记一次 watch 效果；若 target 已终止则立即投递一条 Terminated（R7.1 / 7.4）。
fn[S, M] ActorSystem::do_watch(
  self : ActorSystem[S, M],
  watcher : ActorId,
  target : ActorId,
  on_terminated : (ActorId, TerminationReason) -> M,
) -> Unit {
  match self.reason_of_terminated(target.value) {
    Some(reason) =>
      self.enqueue_msg(watcher.value, on_terminated(target, reason))
    None => self.watches.watch(watcher, target, on_terminated)
  }
}

// ───────────────────────────── 重启 / 停止处置（R2 / R3） ────────────────

///|
/// 重启某单元（R2.2 / R3.3 / R3.5 / R5.5 / R6.4）：记录重启时刻、以初始状态重置、
/// 行为栈重置为仅含初始行为、清空暂存、恢复 Running。若该单元是 supervisor，
/// 级联重启其全部子（监督树重启语义，配合 R1.5 升级）。
fn[S, M] ActorSystem::do_restart(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
  reason : String,
) -> Unit {
  cell.restart_times.push(self.clock)
  cell.restart_total = cell.restart_total + 1
  cell.state = restart_state(cell.init_state, cell.hooks, cell.state, reason)
  while cell.behaviors.length() > 1 {
    let _ = cell.behaviors.pop()
  }
  cell.stash.clear()
  cell.status = Running
  cell.started = true
  // 级联重启子（若为 supervisor）。
  match self.children.get(cell.id.value) {
    Some(kids) =>
      for k in kids {
        match self.cell_by_id(k) {
          Some(child) => self.do_restart(child, reason)
          None => ()
        }
      }
    None => ()
  }
}

///|
/// 因失败按 Stop 指令永久停止某单元（R2.3）：Stopped、清空、调用 post_stop
/// （Stop 指令语义，R3.2）、投递 Terminated(FailedWith)。
fn[S, M] ActorSystem::do_stop_failed(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
  reason : String,
) -> Unit {
  cell.status = Stopped
  cell.mailbox.close()
  cell.mailbox.discard_all()
  cell.stash.clear()
  (cell.hooks.post_stop)(cell.state)
  self.deliver_terminated(cell.id.value, FailedWith(reason))
}

///|
/// 无 supervisor 的 actor 失败 → 终态 Failed（错误隔离，R14.3）：不调用 post_stop
/// （崩溃），投递 Terminated(FailedWith)。
fn[S, M] ActorSystem::terminate_failed(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
  reason : String,
) -> Unit {
  cell.status = Failed(reason)
  cell.mailbox.close()
  cell.mailbox.discard_all()
  cell.stash.clear()
  self.deliver_terminated(cell.id.value, FailedWith(reason))
}

// ───────────────────────────── 监督决策（R1 / R2） ──────────────────────

///|
/// 在某 supervisor 的策略范围内对受影响子施加指令（OneForOne / OneForAll /
/// RestForOne 扩展处置范围，R1.2~1.4）；范围外子状态 / 生命周期不变（隔离）。
fn[S, M] ActorSystem::apply_scope(
  self : ActorSystem[S, M],
  sup_id : Int,
  failed_cell : SupervisedCell[S, M],
  spec : SupervisorSpec,
  directive : Directive,
  reason : String,
) -> Unit {
  let kids = match self.children.get(sup_id) {
    Some(k) => k
    None => []
  }
  let mut failed_index = -1
  for i in 0..<kids.length() {
    if kids[i] == failed_cell.id.value {
      failed_index = i
    }
  }
  let affected = affected_children(spec.strategy, kids.length(), failed_index)
  for idx in affected {
    match self.cell_by_id(kids[idx]) {
      Some(child) =>
        match directive {
          Restart => self.do_restart(child, reason)
          Stop => self.do_stop_failed(child, reason)
          Escalate => ()
        }
      None => ()
    }
  }
}

///|
/// 失败升级（R1.5 / R2.4）：把失败上抛给 supervisor 的 supervisor，由上层按其策略
/// 处置；根 supervisor 的升级退化为停止失败子（确定性收敛）。
fn[S, M] ActorSystem::escalate(
  self : ActorSystem[S, M],
  sup_id : Int,
  failed_cell : SupervisedCell[S, M],
  reason : String,
) -> Unit {
  match self.parents.get(sup_id) {
    Some(_) =>
      match self.cell_by_id(sup_id) {
        Some(sup_cell) => self.on_child_failed(sup_cell, reason)
        None => self.do_stop_failed(failed_cell, reason)
      }
    None => self.do_stop_failed(failed_cell, reason)
  }
}

///|
/// 子失败时的监督决策入口（R2.6 强度判定 → 指令处置 → 范围扩展）。
fn[S, M] ActorSystem::on_child_failed(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
  reason : String,
) -> Unit {
  self.cross_dirty = true
  match self.parents.get(cell.id.value) {
    None =>
      // 无 supervisor：终态 Failed（错误隔离）。
      self.terminate_failed(cell, reason)
    Some(sup_id) => {
      let spec = match self.supervisors.get(sup_id) {
        Some(s) => s
        None => default_spec()
      }
      match cell.directive {
        Escalate => self.escalate(sup_id, cell, reason)
        Stop => self.apply_scope(sup_id, cell, spec, Stop, reason)
        Restart => {
          prune_restart_times(
            cell.restart_times,
            self.clock,
            spec.intensity.window,
          )
          if within_intensity(
              cell.restart_times,
              self.clock,
              spec.intensity.window,
              spec.intensity.max_restarts,
            ) {
            self.apply_scope(sup_id, cell, spec, Restart, reason)
          } else {
            // 强度超限：升级或停止（R2.6 / 2.7）。
            self.escalate(sup_id, cell, reason)
          }
        }
      }
    }
  }
}

// ───────────────────────────── step 流水线（R10） ───────────────────────

///|
/// 结算显式停止：把 Running 且邮箱已关闭（经 `ActorRef::stop`）的 actor 停止为
/// Stopped，调用 post_stop（R3.2），投递 Terminated(StoppedNormally)（R7.2）。
/// 返回是否发生了停止。
fn[S, M] ActorSystem::settle_stops(self : ActorSystem[S, M]) -> Bool {
  let mut any = false
  for cell in self.cells {
    if cell.status is Running && cell.mailbox.is_closed() {
      cell.status = Stopped
      cell.mailbox.discard_all()
      cell.stash.clear()
      (cell.hooks.post_stop)(cell.state)
      self.deliver_terminated(cell.id.value, StoppedNormally)
      any = true
    }
  }
  any
}

///|
/// 选取一个就绪 actor（Running、未关闭、有待处理消息）。以种子 Rng 在就绪集合中
/// 确定性选取；无种子退化为登记顺序（R10.1 / 10.4）。
fn[S, M] ActorSystem::pick_ready(
  self : ActorSystem[S, M],
) -> SupervisedCell[S, M]? {
  let ready : Array[Int] = []
  for i in 0..<self.cells.length() {
    let cell = self.cells[i]
    if cell.status is Running && !cell.mailbox.is_closed() {
      self.sync_bounded(cell)
      if self.cell_pending(cell) > 0 {
        ready.push(i)
      }
    }
  }
  if ready.is_empty() {
    return None
  }
  let choice = match self.rng {
    Some(r) => ready[r.next_below(ready.length())]
    None => ready[0]
  }
  Some(self.cells[choice])
}

///|
/// 应用一次处理记录的上下文效果（become/unbecome/stash/unstash/watch/unwatch），
/// 按记录顺序确定性应用（R5.2 / 5.3 / 6.1 / 6.2 / 7.1 / 7.3）。
fn[S, M] ActorSystem::apply_effects(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
  ctx : ActorContext[S, M],
  current_msg : M,
) -> Unit {
  for effect in ctx.effects {
    match effect {
      PushBehavior(b) => behavior_stack_push(cell.behaviors, b)
      PopBehavior => behavior_stack_pop(cell.behaviors)
      StashCurrent => cell.stash.push(current_msg)
      UnstashAll => cell.stash.drain_to_front(cell.mailbox)
      Watch(target, adapter) => self.do_watch(cell.id, target, adapter)
      Unwatch(target) => self.watches.unwatch(cell.id, target)
    }
  }
}

///|
/// 处理某就绪单元的一条消息（串行不变量：本步仅一条，R10.4）。
fn[S, M] ActorSystem::process_one(
  self : ActorSystem[S, M],
  cell : SupervisedCell[S, M],
) -> Unit {
  // 懒启动：处理首条消息前调用一次 pre_start（R3.1 / 3.7）。
  if !cell.started {
    cell.state = start_state(cell.init_state, cell.hooks)
    cell.started = true
  }
  self.sync_bounded(cell)
  match self.cell_dequeue(cell) {
    None => return
    Some(msg) => {
      // 复用单元常驻上下文（效果列表清空后重用），消除逐消息分配。
      let ctx = cell.ctx_cache
      ctx.effects.clear()
      let top = match behavior_stack_top(cell.behaviors) {
        Some(b) => b
        None => return
      }
      let outcome = top.apply(ctx, cell.state, msg)
      // 记录一条 trace 事件（逻辑时钟加一，R10.3）。
      self.clock = self.clock + 1
      self.trace.push({ actor: cell.id, seq: self.clock })
      match outcome {
        Updated(s) => {
          cell.state = s
          self.apply_effects(cell, ctx, msg)
        }
        Errored(e) =>
          // 触发监督（丢弃触发失败的当前消息，R3.4；效果忽略）。
          self.on_child_failed(cell, e)
      }
    }
  }
}

///|
/// 执行一步调度：先结算显式停止，再选取一个就绪 actor 处理一条消息（R10.4）。
/// 返回是否有进展（处理了一条消息或结算了停止）。
pub fn[S, M] ActorSystem::step(self : ActorSystem[S, M]) -> Bool {
  let settled = self.settle_stops()
  match self.pick_ready() {
    Some(cell) => {
      self.process_one(cell)
      true
    }
    None => settled
  }
}

///|
/// 反复 `step` 直至空闲（无 Running 且有待处理消息者，R10.5）。
///
/// 无种子时就绪选取恒为「登记序最小的就绪 actor」，且纯 `Updated` 处理不会向
/// 其它 actor 注入消息，故最小就绪下标单调不减——用推进游标把每步的全表扫描
/// 摊销为 O(1)；任何跨单元事件（Terminated 投递、监督处置）置 `cross_dirty`，
/// 游标回零并重新结算停止，保证与逐 `step` 完全一致的处理序列。
pub fn[S, M] ActorSystem::run_until_idle(self : ActorSystem[S, M]) -> Unit {
  match self.rng {
    Some(_) =>
      while self.step() {

      }
    None => self.run_until_idle_ordered()
  }
}

///|
/// 无种子（登记序）快路径：游标扫描代替逐步全表扫描，处理序列与逐 `step`
/// 一致（见 `run_until_idle` 注释）。
fn[S, M] ActorSystem::run_until_idle_ordered(self : ActorSystem[S, M]) -> Unit {
  ignore(self.settle_stops())
  self.cross_dirty = false
  let mut i = 0
  while i < self.cells.length() {
    let cell = self.cells[i]
    if cell.status is Running && !cell.mailbox.is_closed() {
      self.sync_bounded(cell)
      if self.cell_pending(cell) > 0 {
        self.process_one(cell)
        if self.cross_dirty {
          ignore(self.settle_stops())
          self.cross_dirty = false
          i = 0
        }
        continue
      }
    }
    i = i + 1
  }
}

// ───────────────────────────── 观测辅助 ──────────────────────────────────

///|
/// 处理序列（trace）—— 一次运行中按发生顺序记录的处理事件（R10.3）。
pub fn[S, M] ActorSystem::trace_of(
  self : ActorSystem[S, M],
) -> Array[TraceEvent] {
  self.trace
}

///|
/// 读取某 actor 当前状态；未登记返回 None。
pub fn[S, M] ActorSystem::state_of(
  self : ActorSystem[S, M],
  r : ActorRef[M],
) -> S? {
  match self.cell_by_id(r.id.value) {
    Some(cell) => Some(cell.state)
    None => None
  }
}

///|
/// 读取某 actor 生命周期状态；未登记返回 None。
pub fn[S, M] ActorSystem::status_of(
  self : ActorSystem[S, M],
  r : ActorRef[M],
) -> ActorStatus? {
  match self.cell_by_id(r.id.value) {
    Some(cell) => Some(cell.status)
    None => None
  }
}

///|
/// 某 actor 是否仍在运行（Running）。未登记视为 false。
pub fn[S, M] ActorSystem::is_running(
  self : ActorSystem[S, M],
  r : ActorRef[M],
) -> Bool {
  match self.status_of(r) {
    Some(Running) => true
    _ => false
  }
}

///|
/// 某 actor 被重启的次数（观测，R2 / R3）。
pub fn[S, M] ActorSystem::restart_count(
  self : ActorSystem[S, M],
  r : ActorRef[M],
) -> Int {
  match self.cell_by_id(r.id.value) {
    Some(cell) => cell.restart_total
    None => 0
  }
}

///|
/// 某 actor 当前待处理消息条数（含有界队列）；未登记返回 0。
pub fn[S, M] ActorSystem::pending(
  self : ActorSystem[S, M],
  r : ActorRef[M],
) -> Int {
  match self.cell_by_id(r.id.value) {
    Some(cell) => {
      self.sync_bounded(cell)
      self.cell_pending(cell)
    }
    None => 0
  }
}
