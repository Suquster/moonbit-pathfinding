// des_sim.mbt —— DST_Framework 旗舰深化：离散事件仿真核心循环（旁路新增，设计 4.6）。
//
// paper-to-code 追溯：FoundationDB 确定性仿真实践——同种子 → 同执行；一切随机
// 决策仅由确定性随机源 `Rng`（xorshift64）驱动，使 wasm-gc / js / native 三后端
// 逐位一致、可重放。离散事件仿真核心：「取全序最小事件 → 处理 → 入队未来事件」。
//
// 确定性两大支柱（沿用既有 `run` 的规范化范式，R12.3）：
//   (1) `Rng`（xorshift64，仅移位 + 异或）三后端逐位一致（见 rng.mbt）；
//   (2) 任务按 id 升序、故障按 `(at_step, task_id)` 升序规范化，使「同种子 → 同
//       调度序列 + 同终态」不依赖输入排列。
//
// 与既有 `sim.mbt` 的「步进式」流水线严格隔离：`World` / `run_des` / `replay_des`
// 全部为旁路新增，既有 `Sim` / `run` / `replay` 一字不改（R12.4）。
//
// 逻辑时间与全序（R1.2 / R1.3）：引擎为每个「处理动作」（一次唤醒或一次投递 /
// 一次故障注入）分配一个**严格递增**的逻辑时间戳（`advance_clock`），同一动作内
// 产生的事件共享该时间戳且归属同一节点，故事件轨迹天然满足全序
// 「(时间戳, 任务 id, 次序键)」——既单调不减，又在同一时间戳内按任务 id / 次序键
// 非降（同一动作内任务 id 恒定）。

///|
/// 离散事件仿真世界状态（DES world）。承载确定性随机源、虚拟时钟、节点、事件
/// 队列与事件轨迹等运行态；含函数值（protocol / invariants）与可变状态，故不派生
/// （与既有 `Sim` 同例）。
///
/// 设计 4.6 列出的核心字段（`rng` / `clock` / `step_no` / `nodes` / `queue` /
/// `trace` / `msg_seq`）之外，本结构额外内联场景上下文（`protocol` / `faults` /
/// `invariants` / `max_steps`）与调度辅助态（`pending` / `status` / `order_seq` /
/// `fault_idx` / `partitions` / `wake_count`），使 `World::step` 无需外部参数即可
/// 自洽推进——`World` 为新增不可被外部构造其字段的 `pub` 结构，新增字段不影响
/// 任何既有调用方（R12.4）。
pub struct World {
  seed : UInt64
  rng : Rng
  mut clock : LogicalTime
  mut step_no : Int
  nodes : Array[Node]
  mut queue : EventQueue
  trace : Array[SimEvent]
  mut msg_seq : Int
  protocol : Protocol
  faults : Array[FaultPolicyEx]
  invariants : Array[Invariant]
  max_steps : Int
  mut pending : Array[Int]
  mut status : SimStatus
  mut order_seq : UInt64
  mut fault_idx : Int
  partitions : Array[FaultPolicyEx]
  mut wake_count : Int
}

///|
/// 以给定种子与场景构造初始世界：任务按 id 升序规范化为节点与待调度集合，故障
/// 按 `(at_step, task_id)` 升序规范化注入顺序，事件队列 / 轨迹初始为空。
pub fn World::new(seed : UInt64, scenario : DesScenario) -> World {
  let tasks = scenario.tasks.copy()
  tasks.sort_by(fn(a, b) { cmp_int(a.id, b.id) })
  let nodes : Array[Node] = []
  let pending : Array[Int] = []
  for tk in tasks {
    nodes.push({
      id: tk.id,
      name: tk.name,
      app: (scenario.protocol.init)(tk.id),
      skew: 0L,
      alive: true,
      reorder: false,
      duplicate: false,
      byzantine: false,
    })
    pending.push(tk.id)
  }
  let faults = scenario.faults.copy()
  faults.sort_by(fn(a, b) { fault_ex_cmp(a, b) })
  {
    seed,
    rng: rng_new(seed),
    clock: 0UL,
    step_no: 0,
    nodes,
    queue: EventQueue::new(),
    trace: [],
    msg_seq: 0,
    protocol: scenario.protocol,
    faults,
    invariants: scenario.invariants,
    max_steps: scenario.max_steps,
    pending,
    status: Completed,
    order_seq: 0UL,
    fault_idx: 0,
    partitions: [],
    wake_count: 0,
  }
}

///|
/// 推进虚拟时钟到一个严格递增的新逻辑时间戳并返回之（保证单调不减且各处理动作
/// 时间戳互异，从而事件轨迹天然满足全序）。
fn World::advance_clock(self : World) -> LogicalTime {
  self.clock = self.clock + 1UL
  self.clock
}

///|
/// 分配下一个确定性次序键（全序第三键）。`reorder` 为真时返回递减键，使重排
/// 节点的同时刻、同目标消息投递顺序被确定性地调换（R3.3）。
fn World::next_order_key(self : World, reorder : Bool) -> UInt64 {
  let s = self.order_seq
  self.order_seq = self.order_seq + 1UL
  if reorder {
    0xFFFF_FFFF_FFFF_FFFFUL - s
  } else {
    s
  }
}

///|
/// 按 id 查找节点（返回可变节点引用；不存在返回 `None`）。
fn World::find_node(self : World, id : Int) -> Node? {
  for n in self.nodes {
    if n.id == id {
      return Some(n)
    }
  }
  None
}

///|
/// 将任务 id 移出待调度集合（其余保持原有相对顺序）。
fn World::remove_pending(self : World, id : Int) -> Unit {
  let np : Array[Int] = []
  for x in self.pending {
    if x != id {
      np.push(x)
    }
  }
  self.pending = np
}

///|
/// 将节点标记为非存活（`Crash` / `Drop` 故障使用；其后涉及该节点的投递被阻断）。
fn World::kill_node(self : World, id : Int) -> Unit {
  match self.find_node(id) {
    Some(n) => n.alive = false
    None => ()
  }
}

///|
/// 注入单条故障：记录 `EvFaulted` 并施加确定性效果（设计 4.5）。
fn World::apply_fault(self : World, f : FaultPolicyEx) -> Unit {
  let t = self.advance_clock()
  self.trace.push(EvFaulted(time=t, task_id=f.task_id, kind=f.kind))
  match f.kind {
    // 崩溃 / 丢弃：移出待调度集合并阻断该节点消息。
    Crash => {
      self.remove_pending(f.task_id)
      self.kill_node(f.task_id)
    }
    Drop => {
      self.remove_pending(f.task_id)
      self.kill_node(f.task_id)
    }
    // 延迟：仅记录事件，任务仍留在待调度集合。
    Delay(..) => ()
    // 分区：登记生效区间内的分组（投递时检查跨组阻断）。
    Partition(..) => self.partitions.push(f)
    // 重排 / 重复 / 拜占庭：置目标节点旗标，影响其后消息调度 / 内容。
    Reorder =>
      match self.find_node(f.task_id) {
        Some(n) => n.reorder = true
        None => ()
      }
    Duplicate =>
      match self.find_node(f.task_id) {
        Some(n) => n.duplicate = true
        None => ()
      }
    Byzantine =>
      match self.find_node(f.task_id) {
        Some(n) => n.byzantine = true
        None => ()
      }
    // 时钟偏移：对目标节点施加本地逻辑时钟偏移。
    ClockSkew(offset~) =>
      match self.find_node(f.task_id) {
        Some(n) => n.skew = offset
        None => ()
      }
  }
}

///|
/// 施加全部命中当前步序号 `s` 的故障（按 `(at_step, task_id)` 升序，规范化注入点）。
fn World::apply_faults_at(self : World, s : Int) -> Unit {
  while self.fault_idx < self.faults.length() &&
        self.faults[self.fault_idx].at_step <= s {
    let f = self.faults[self.fault_idx]
    if f.at_step == s {
      self.apply_fault(f)
    }
    self.fault_idx = self.fault_idx + 1
  }
}

///|
/// 执行协议动作序列（`actor_id` 为执行节点）：`ActAppend` 直接追加本节点日志，
/// `ActSend` 经 `schedule_send` 记录发送并安排未来投递。
fn World::apply_actions(
  self : World,
  actor_id : Int,
  acts : Array[Action],
) -> Unit {
  for act in acts {
    match act {
      ActAppend(value~) =>
        match self.find_node(actor_id) {
          Some(n) => if n.alive { n.app.log.push(value) }
          None => ()
        }
      ActSend(to~, payload~, after~) => {
        let _ = self.schedule_send(actor_id, to, payload, after)
      }
    }
  }
}

///|
/// 唤醒待调度集合中下标 `idx` 的任务执行一步：记录 `EvScheduled` / `EvCompleted`
/// （同一逻辑时间戳，归属该任务），并执行其 `on_start` 激励动作。
fn World::do_wake(self : World, idx : Int) -> Unit {
  let i = if idx < 0 || idx >= self.pending.length() { 0 } else { idx }
  let tid = self.pending[i]
  let np : Array[Int] = []
  for j in 0..<self.pending.length() {
    if j != i {
      np.push(self.pending[j])
    }
  }
  self.pending = np
  self.wake_count = self.wake_count + 1
  let t = self.advance_clock()
  self.trace.push(EvScheduled(time=t, task_id=tid))
  match self.find_node(tid) {
    Some(n) =>
      if n.alive {
        let acts = (self.protocol.on_start)(tid)
        self.apply_actions(tid, acts)
      }
    None => ()
  }
  self.trace.push(EvCompleted(time=t, task_id=tid))
}

///|
/// 处理事件队列中的全序最小事件一步（取队首 → 投递 / 唤醒）。
fn World::do_deliver_step(self : World) -> Unit {
  match self.queue.pop_min() {
    None => ()
    Some((qe, rest)) => {
      self.queue = rest
      match qe.pending {
        PDeliver(from~, to~, msg~) => {
          let _ = self.deliver(from, to, msg)
        }
        PWake(task_id~) => {
          let t = self.advance_clock()
          self.trace.push(EvScheduled(time=t, task_id~))
          self.trace.push(EvCompleted(time=t, task_id~))
        }
      }
    }
  }
}

///|
/// 返回任务 `tid` 在当前步序号下的活跃分区分组；无活跃分区返回 `None`。
fn World::active_group(self : World, tid : Int) -> Int? {
  let mut res : Int? = None
  for p in self.partitions {
    if p.task_id == tid {
      match p.kind {
        Partition(group~, until_step~) =>
          if self.step_no >= p.at_step && self.step_no < until_step {
            res = Some(group)
          }
        _ => ()
      }
    }
  }
  res
}

///|
/// 判定从 `from` 到 `to` 的投递是否被阻断：端点非存活（崩溃 / 丢弃），或二者被
/// 活跃分区划分到不同分组（跨组投递阻断，R3.2）。
fn World::is_blocked(self : World, from : Int, to : Int) -> Bool {
  match self.find_node(from) {
    Some(n) => if !n.alive { return true }
    None => return true
  }
  match self.find_node(to) {
    Some(n) => if !n.alive { return true }
    None => return true
  }
  match (self.active_group(from), self.active_group(to)) {
    (Some(a), Some(b)) => a != b
    _ => false
  }
}

///|
/// 推进一步仿真（内部，选择器 `chooser` 决定唤醒哪个待调度任务）：施加命中故障 →
/// 求值不变量 → 唤醒任务或投递消息 → 再求值不变量 → 步序号自增。返回是否有进展
/// （`false` 表示应终止：达步数上限 / 已失败 / 队空且无待调度）。
fn World::step_with(self : World, chooser : (World) -> Int) -> Bool {
  if self.step_no >= self.max_steps {
    return false
  }
  match self.status {
    Failed(..) => return false
    _ => ()
  }
  // 无待调度任务且事件队列为空：无事可做，终止（与既有 `run` 的循环守卫一致）。
  if self.pending.length() == 0 && self.queue.is_empty() {
    return false
  }
  self.apply_faults_at(self.step_no)
  match eval_invariants(self) {
    Some(r) => {
      self.status = Failed(reason=r)
      return false
    }
    None => ()
  }
  if self.pending.length() > 0 {
    self.do_wake(chooser(self))
  } else if !self.queue.is_empty() {
    self.do_deliver_step()
  } else {
    return false
  }
  match eval_invariants(self) {
    Some(r) => {
      self.status = Failed(reason=r)
      return false
    }
    None => ()
  }
  self.step_no = self.step_no + 1
  true
}

///|
/// 反复推进直至终止（内部驱动循环）。
fn World::drive(self : World, chooser : (World) -> Int) -> Unit {
  while self.step_with(chooser) {

  }
}

///|
/// 推进一步仿真（公开接口，设计 4.6）：以确定性随机源选择待调度任务，取队首事件
/// 处理并入队未来事件、每步求值不变量。返回推进后的世界（就地推进并返回自身）。
pub fn World::step(self : World) -> World {
  let _ = self.step_with(fn(w) { w.rng.next_below(w.pending.length()) })
  self
}

///|
/// 只读视图：返回当前已产生的事件轨迹（供调用方 / 测试观测推进进度）。
pub fn World::trace_view(self : World) -> Array[SimEvent] {
  self.trace
}

///|
/// 只读视图：返回当前虚拟时钟。
pub fn World::clock_now(self : World) -> LogicalTime {
  self.clock
}

///|
/// 由事件轨迹确定性派生 DES 终态：轨迹含崩溃故障（`EvFaulted` 且 `Crash`）即判
/// `Failed`，否则 `Completed`。`run_des` 与 `replay_des` 共用，保证重放复现同一终态。
pub fn status_from_des_trace(trace : Array[SimEvent]) -> SimStatus {
  for e in trace {
    match e {
      EvFaulted(time~, task_id~, kind~) =>
        match kind {
          Crash =>
            return Failed(
              reason="确定性注入的崩溃故障：任务 \{task_id} 于逻辑时间 \{time} 崩溃",
            )
          _ => ()
        }
      _ => ()
    }
  }
  Completed
}

///|
/// 由世界状态产出仿真结果：终态优先取运行期判定（不变量违反），否则由轨迹派生
/// （崩溃 / 正常完成）；`finals` 取各节点存活终态，按 id 升序。
fn World::to_result(self : World) -> DesResult {
  let status = match self.status {
    Failed(..) => self.status
    _ => status_from_des_trace(self.trace)
  }
  let finals : Array[(Int, NodeApp)] = []
  for n in self.nodes {
    finals.push((n.id, n.app))
  }
  { seed: self.seed, trace: self.trace, status, finals }
}

///|
/// 以种子与场景运行一次离散事件仿真，返回含可重放凭据 + 终态 + 各节点终态的结果
/// （同种子 → 同执行，R1.1）。
pub fn run_des(seed : UInt64, scenario : DesScenario) -> DesResult {
  let w = World::new(seed, scenario)
  w.drive(fn(ww) { ww.rng.next_below(ww.pending.length()) })
  w.to_result()
}

///|
/// 以固定任务唤醒顺序 `order`（任务 id 的一个排列 / 前缀）运行一次仿真，供有界
/// 穷尽探索 / DPOR 以脚本化交错复现执行（不消耗随机源做任务选择）。
///
/// 每次唤醒按 `order` 的下一个仍待调度的任务 id 选择；`order` 用尽或目标已不可调度
/// 时退化为选择当前待调度集合的首个（下标 0），保证总能产出确定性结果。
pub fn run_des_with_order(
  seed : UInt64,
  scenario : DesScenario,
  order : Array[Int],
) -> DesResult {
  let w = World::new(seed, scenario)
  w.drive(fn(ww) {
    let oi = ww.wake_count
    if oi < order.length() {
      let want = order[oi]
      let mut found = -1
      for i in 0..<ww.pending.length() {
        if ww.pending[i] == want {
          found = i
          break
        }
      }
      if found >= 0 {
        found
      } else {
        0
      }
    } else {
      0
    }
  })
  w.to_result()
}

///|
/// 依「种子 + 事件轨迹」重放一次仿真，复现逐字段一致的终态（R8.4）。
///
/// 轨迹是一次运行的权威记录：终态由 `status_from_des_trace` 确定性派生，`finals`
/// 由轨迹中投递事件重建（投递负载即各节点观察到的日志条目）。故以某次运行输出的
/// `seed` + `trace` 重放，必复现与原运行一致的 `status` 与 `trace`（P15）。
pub fn replay_des(seed : UInt64, trace : Array[SimEvent]) -> DesResult {
  let owned = trace.copy()
  let status = status_from_des_trace(owned)
  let finals = reconstruct_finals(owned)
  { seed, trace: owned, status, finals }
}

///|
/// 确保 `(ids, logs)` 中存在节点 `id` 的槽位，返回其下标（不存在则追加空日志槽）。
fn ensure_node_slot(
  ids : Array[Int],
  logs : Array[Array[Int]],
  id : Int,
) -> Int {
  for i in 0..<ids.length() {
    if ids[i] == id {
      return i
    }
  }
  ids.push(id)
  logs.push([])
  ids.length() - 1
}

///|
/// 由事件轨迹重建各节点终态（best-effort）：节点日志 = 投递到该节点的消息负载
/// 序列；按 id 升序。供 `replay_des` 重建 `finals`。
fn reconstruct_finals(trace : Array[SimEvent]) -> Array[(Int, NodeApp)] {
  let ids : Array[Int] = []
  let logs : Array[Array[Int]] = []
  for e in trace {
    match e {
      EvScheduled(task_id~, ..) => ignore(ensure_node_slot(ids, logs, task_id))
      EvCompleted(task_id~, ..) => ignore(ensure_node_slot(ids, logs, task_id))
      EvSend(from~, ..) => ignore(ensure_node_slot(ids, logs, from))
      EvDeliver(to~, msg~, ..) => {
        let k = ensure_node_slot(ids, logs, to)
        logs[k].push(msg.payload)
      }
      EvFaulted(..) => ()
    }
  }
  let pairs : Array[(Int, NodeApp)] = []
  for i in 0..<ids.length() {
    pairs.push((ids[i], { log: logs[i], kv: [] }))
  }
  pairs.sort_by(fn(a, b) { cmp_int(a.0, b.0) })
  pairs
}

///|
/// 向后兼容桥：把既有 `Scenario` 提升为 DES 场景（提供协议与不变量后纳入 DES
/// 流水线）。对「无消息、仅遗留故障」的提升场景，DES 调度的任务选择复用与既有
/// `step` 相同的 `rng.next_below(待调度数)`（over id 升序待调度集），使两条流水线
/// 可做差分一致性验证（P1）。
pub fn DesScenario::of_legacy(
  scenario : Scenario,
  protocol~ : Protocol,
  invariants? : Array[Invariant] = [],
) -> DesScenario {
  let faults : Array[FaultPolicyEx] = []
  for p in scenario.faults {
    faults.push(FaultPolicyEx::of_legacy(p))
  }
  {
    tasks: scenario.tasks,
    faults,
    invariants,
    protocol,
    max_steps: scenario.max_steps,
  }
}
