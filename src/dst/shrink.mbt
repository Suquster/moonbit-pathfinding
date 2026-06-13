// shrink.mbt —— DST_Framework 旗舰深化：失败用例收缩（旁路新增，设计 4.7）。
//
// paper-to-code 追溯：Zeller delta debugging 与 QuickCheck shrinking——在保持失败
// 可复现的前提下，将反例（场景 / 故障序列）缩减到更小规模，产出最小反例。
//
// 收缩算子（R4.2）：①移除一个任务；②移除一条故障策略；③缩减 `max_steps`。
// 贪婪流程（R4.3 / R4.4）：反复对每个算子生成候选，**仅接受仍复现原失败的候选**
// （丢弃任何转为 `Completed` 者），无更小失败候选时停止并返回当前最小反例。
//   * 终止性（R4.7）：每次接受使规模 `size` 严格递减且有下界（≥0），故有限步终止；
//   * 单调性：结果 `size` 不大于输入。
// 输入本不失败则返回 `NotFailing`（R4.5，不返回任意场景）。

///|
/// 场景规模度量：任务数 + 故障数 + `max_steps`（收缩单调性以此严格递减）。
pub fn DesScenario::size(self : DesScenario) -> Int {
  self.tasks.length() + self.faults.length() + self.max_steps
}

///|
/// 收缩结果：仍失败的最小反例 `Minimal`，或「输入并不失败」`NotFailing`。
///
/// 含 `DesScenario`（带函数值，不可派生），故 `pub enum` 不派生。
pub enum ShrinkOutcome {
  Minimal(DesScenario)
  NotFailing
}

///|
/// 判定一次运行是否失败（终态为 `Failed`）。
fn des_is_failed(r : DesResult) -> Bool {
  match r.status {
    Failed(..) => true
    _ => false
  }
}

///|
/// 默认失败判据：终态为 `Failed`（R4.1）。可被调用方定制（如锁定同一不变量违反）。
pub fn default_fails(r : DesResult) -> Bool {
  des_is_failed(r)
}

///|
/// 移除下标 `i` 的任务，返回新场景。
fn remove_task_at(s : DesScenario, i : Int) -> DesScenario {
  let tasks : Array[Task] = []
  for j in 0..<s.tasks.length() {
    if j != i {
      tasks.push(s.tasks[j])
    }
  }
  DesScenario::new(tasks, s.faults, s.invariants, s.protocol, s.max_steps)
}

///|
/// 移除下标 `i` 的故障策略，返回新场景。
fn remove_fault_at(s : DesScenario, i : Int) -> DesScenario {
  let faults : Array[FaultPolicyEx] = []
  for j in 0..<s.faults.length() {
    if j != i {
      faults.push(s.faults[j])
    }
  }
  DesScenario::new(s.tasks, faults, s.invariants, s.protocol, s.max_steps)
}

///|
/// 以新的步数上限 `m` 构造场景。
fn with_max_steps(s : DesScenario, m : Int) -> DesScenario {
  DesScenario::new(s.tasks, s.faults, s.invariants, s.protocol, m)
}

///|
/// 尝试一轮收缩：依次尝试「移除任务 / 移除故障 / 缩减 max_steps」算子，返回首个仍
/// 复现失败的更小候选；无更小失败候选返回 `None`。每个候选 `size` 严格小于输入。
fn try_shrink_once(
  seed : UInt64,
  current : DesScenario,
  fails : (DesResult) -> Bool,
) -> DesScenario? {
  for i in 0..<current.tasks.length() {
    let cand = remove_task_at(current, i)
    if fails(run_des(seed, cand)) {
      return Some(cand)
    }
  }
  for i in 0..<current.faults.length() {
    let cand = remove_fault_at(current, i)
    if fails(run_des(seed, cand)) {
      return Some(cand)
    }
  }
  if current.max_steps > 0 {
    let cand = with_max_steps(current, current.max_steps - 1)
    if fails(run_des(seed, cand)) {
      return Some(cand)
    }
  }
  None
}

///|
/// 对失败场景做 delta-debugging 收缩；`fails` 默认判定 `status == Failed`，可定制
/// （如锁定同一不变量违反）。输入不失败返回 `NotFailing`（R4.5）；否则反复接受更小
/// 的仍失败候选直至不可再小，返回最小反例 `Minimal`（R4.4）。
pub fn shrink(
  seed : UInt64,
  scenario : DesScenario,
  fails? : (DesResult) -> Bool = default_fails,
) -> ShrinkOutcome {
  if !fails(run_des(seed, scenario)) {
    return NotFailing
  }
  let mut current = scenario
  let mut go = true
  while go {
    match try_shrink_once(seed, current, fails) {
      Some(c) => current = c
      None => go = false
    }
  }
  Minimal(current)
}

///|
/// 收缩结果是否为最小反例（`Minimal`）。
pub fn ShrinkOutcome::is_minimal(self : ShrinkOutcome) -> Bool {
  match self {
    Minimal(_) => true
    NotFailing => false
  }
}

///|
/// 取出收缩得到的最小反例场景；`NotFailing` 返回 `None`。
pub fn ShrinkOutcome::scenario(self : ShrinkOutcome) -> DesScenario? {
  match self {
    Minimal(s) => Some(s)
    NotFailing => None
  }
}
