// sim.mbt —— DST_Framework 的调度 / 故障注入 / 运行 / 重放实现（任务 13.2）。
//
// 设计依据（design.md §「方向八：DST_Framework」流水线签名）：
//
//   pub fn step(self : Sim) -> Sim                 // 依确定性随机源选择下一任务
//   pub fn inject_fault(self : Sim, policy : FaultPolicy) -> Sim
//   pub fn run(seed : UInt64, scenario : Scenario) -> SimResult  // 同种子→同执行
//   pub fn replay(seed : UInt64, trace : Array[Event]) -> SimResult
//
// 在任务 13.1 锁定的核心类型与接口形态之上，本文件落地确定性调度、故障注入
// 触发与失败重放的完整逻辑（design.md「同种子 → 同执行」为核心价值）：
//   * `step`         —— 依确定性随机源 `Rng` 从待调度任务中选择下一任务，并向
//                       事件轨迹追加 `Scheduled` + `Completed` 事件；
//   * `inject_fault` —— 在 `policy.at_step` 命中当前步序号时对 `policy.task_id`
//                       触发 `policy.kind` 故障并追加 `Faulted` 事件；
//   * `run`          —— 由 `Sim::new(seed, tasks)` 起反复 step / inject_fault 直至
//                       所有任务完成或命中 `max_steps`，保证「同种子 → 同调度
//                       序列 + 同终态」，并在 `SimResult` 中输出可重放的种子与
//                       事件轨迹；
//   * `replay`       —— 依「种子 + 事件轨迹」复现完全相同的失败（Requirement 8.6）。
//
// 确定性的两大支柱：
//   (1) 随机源 `Rng`（xorshift64，仅移位 + 异或）三后端逐位一致（见 rng.mbt）；
//   (2) `run` 以「任务 id 升序」作为待调度集合的**规范顺序**，使「同种子 → 同
//       调度序列」不依赖输入任务的排列，从而 `replay` 可由轨迹无歧义地复现。

///|
/// 整数三路比较（用于 `sort_by` 比较器：a<b → -1，a>b → 1，相等 → 0）。
fn cmp_int(a : Int, b : Int) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// 统计事件轨迹中已发生的 `Scheduled` 事件数，即「当前步序号」。
///
/// 每次 `step` 恰好追加一个 `Scheduled` 事件，故已调度计数即为下一步将占用的
/// 步序号；`inject_fault` 据此判断 `policy.at_step` 是否命中当前注入点。
fn count_scheduled(trace : Array[Event]) -> Int {
  let mut n = 0
  for e in trace {
    match e {
      Scheduled(..) => n += 1
      _ => ()
    }
  }
  n
}

///|
/// 返回任务集合中 `id` 等于 `task_id` 的任务下标；不存在返回 `-1`。
fn task_index(tasks : Array[Task], task_id : Int) -> Int {
  for i in 0..<tasks.length() {
    if tasks[i].id == task_id {
      return i
    }
  }
  -1
}

///|
/// 由事件轨迹确定性地派生仿真终态。
///
/// 轨迹是一次运行的权威记录：只要其中包含**崩溃故障**（`Faulted` 且 `kind` 为
/// `Crash`），整体即判定为失败 `Failed`，原因引用首个崩溃的任务与步序号；否则
/// 为正常完成 `Completed`。`run` 与 `replay` 共用本函数，从而保证
/// `replay(result.seed, result.trace)` 复现与原 `run` 完全一致的终态。
fn status_from_trace(trace : Array[Event]) -> SimStatus {
  for e in trace {
    match e {
      Faulted(step~, task_id~, kind~) =>
        match kind {
          Crash =>
            return SimStatus::Failed(
              reason="确定性注入的崩溃故障：任务 \{task_id} 于第 \{step} 步崩溃",
            )
          _ => ()
        }
      _ => ()
    }
  }
  SimStatus::Completed
}

///|
/// 推进一步仿真：依确定性随机源从待调度任务中选择下一任务并执行。
///
/// 以当前 `Scheduled` 计数作为步序号 `step`，用 `rng.next_below(待调度任务数)`
/// 选出本步执行的任务，向轨迹追加该任务的 `Scheduled` 与 `Completed` 事件，并
/// 将其移出待调度集合（其余任务保持原有相对顺序）。待调度集合为空时原样返回。
///
/// 随机源在选择中就地推进，并随返回的 `Sim` 继续向后传递，从而连续 `step` 形成
/// 确定性序列；对同一初始种子，调度序列逐事件一致（Requirement 8.3）。
pub fn Sim::step(self : Sim) -> Sim {
  if self.tasks.length() == 0 {
    return self
  }
  let step_no = count_scheduled(self.trace)
  let idx = self.rng.next_below(self.tasks.length())
  let selected = self.tasks[idx]
  // 复制并移除被选中任务，保持其余任务原有相对顺序。
  let rest : Array[Task] = []
  for i in 0..<self.tasks.length() {
    if i != idx {
      rest.push(self.tasks[i])
    }
  }
  let next_trace = self.trace.copy()
  next_trace.push(Scheduled(step=step_no, task_id=selected.id))
  next_trace.push(Completed(step=step_no, task_id=selected.id))
  { rng: self.rng, tasks: rest, trace: next_trace }
}

///|
/// 按故障策略注入故障：在 `policy.at_step` 命中当前步序号时触发。
///
/// 仅当 `policy.at_step` 等于当前步序号（已调度计数）且目标任务仍在待调度集合
/// 中时注入；否则原样返回（不重复注入、不作用于已完成/已移除任务）。注入后向
/// 轨迹追加 `Faulted` 事件，并依故障类型施加效果：
///   * `Delay` —— 仅记录事件，任务仍留在待调度集合，后续步骤照常被选中；
///   * `Drop`  —— 将目标任务移出待调度集合（被丢弃，永不调度）；
///   * `Crash` —— 将目标任务移出待调度集合，并令整体终态判定为 `Failed`
///                （由 `status_from_trace` 据 `Faulted(Crash)` 推导）。
///
/// 注入点由确定性步序号给定（Requirement 8.4），故同种子下故障触发可重放。
pub fn Sim::inject_fault(self : Sim, policy : FaultPolicy) -> Sim {
  let step_no = count_scheduled(self.trace)
  if policy.at_step != step_no {
    return self
  }
  let idx = task_index(self.tasks, policy.task_id)
  if idx < 0 {
    // 目标任务不在待调度集合（已完成 / 已丢弃 / 已崩溃）→ 不注入。
    return self
  }
  let next_trace = self.trace.copy()
  next_trace.push(
    Faulted(step=step_no, task_id=policy.task_id, kind=policy.kind),
  )
  match policy.kind {
    // 延迟：任务保留在待调度集合，仅记录事件。
    Delay => { rng: self.rng, tasks: self.tasks, trace: next_trace }
    // 崩溃 / 丢弃：将目标任务移出待调度集合。
    Crash | Drop => {
      let rest : Array[Task] = []
      for i in 0..<self.tasks.length() {
        if i != idx {
          rest.push(self.tasks[i])
        }
      }
      { rng: self.rng, tasks: rest, trace: next_trace }
    }
  }
}

///|
/// 以种子与场景运行一次仿真，返回含可重放种子 + 事件轨迹 + 终态的结果。
///
/// 「同种子 → 同调度序列 + 同终态」（Requirement 8.2）由两点保证：
///   (1) 待调度集合以**任务 id 升序**规范化，调度结果不依赖输入任务排列；
///   (2) 故障策略以 `(at_step, task_id)` 升序规范化，注入顺序确定。
///
/// 主循环：自步序号 0 起，先施加命中本步的全部故障（可能丢弃 / 崩溃任务），再
/// 经 `step` 调度一个任务，直至所有任务完成或命中 `scenario.max_steps`。终态由
/// `status_from_trace` 据事件轨迹派生（含崩溃故障 → `Failed`）。失败时
/// `SimResult` 携带的 `seed` + `trace` 即为可重放凭据（Requirement 8.5）。
pub fn run(seed : UInt64, scenario : Scenario) -> SimResult {
  // (1) 待调度集合按任务 id 升序规范化（不修改调用方的 scenario）。
  let pending = scenario.tasks.copy()
  pending.sort_by(fn(a, b) { cmp_int(a.id, b.id) })
  // (2) 故障策略按 (at_step, task_id) 升序规范化，确定注入顺序。
  let faults = scenario.faults.copy()
  faults.sort_by(fn(a, b) {
    if a.at_step != b.at_step {
      cmp_int(a.at_step, b.at_step)
    } else {
      cmp_int(a.task_id, b.task_id)
    }
  })
  let mut sim = Sim::new(seed, pending)
  let mut s = 0
  while sim.tasks.length() > 0 && s < scenario.max_steps {
    // 先施加命中本步序号的全部故障（inject_fault 内部再校验 at_step）。
    for f in faults {
      if f.at_step == s {
        sim = sim.inject_fault(f)
      }
    }
    // 故障可能已清空待调度集合（全部被丢弃 / 崩溃）。
    if sim.tasks.length() == 0 {
      break
    }
    sim = sim.step()
    s += 1
  }
  { seed, trace: sim.trace, status: status_from_trace(sim.trace) }
}

///|
/// 依「种子 + 事件轨迹」重放一次仿真，复现完全相同的结果（Requirement 8.6）。
///
/// 事件轨迹是一次运行的权威记录，终态由其确定性派生（`status_from_trace`），故
/// `replay(result.seed, result.trace)` 必复现与原 `run` 完全一致的 `SimResult`
/// （相同种子、逐事件一致的轨迹、相同终态）。返回结果持有轨迹的独立副本，避免
/// 与调用方共享可变状态。
pub fn replay(seed : UInt64, trace : Array[Event]) -> SimResult {
  let owned = trace.copy()
  { seed, trace: owned, status: status_from_trace(owned) }
}
