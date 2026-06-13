// dpor.mbt —— DST_Framework 旗舰深化：DPOR 偏序约简（旁路新增，设计 4.9）。
//
// paper-to-code 追溯：Flanagan & Godefroid 2005《Dynamic Partial-Order Reduction》。
// 以事件依赖关系与睡眠集（sleep set）剪枝相互等价的交错，对每个 Mazurkiewicz 迹
// 等价类至少探索一个代表交错（R6.3），从而所探索交错数不超过有界穷尽探索（R6.6），
// 且任一失败交错必被某代表覆盖（R6.4，不漏报）。
//
// 依赖关系（R6.2，`depends`）：作用于**同一节点**、或存在**消息因果关联**（同一
// 消息 id 的 send/deliver、或读写同一节点状态）的两事件为「依赖」；作用于不同节点
// 且无因果关联者为「独立」（可交换）。
//
// 任务级独立关系（供睡眠集约简）：由一次探针运行（`run_des`）的事件轨迹推导——两
// 任务若在轨迹中存在直接消息往来（`EvSend` 的 `from`/`to`）则依赖，否则独立。对
// 「发送仅源自 `on_start`」的协议（其通信结构与唤醒顺序无关），该探针完整捕获全部
// 潜在通信，故约简对此类场景可靠（不漏报）。

///|
/// 返回事件涉及的节点 id 集合：发送 / 投递涉及 `from` 与 `to`，其余事件涉及其
/// `task_id`。
fn event_nodes(e : SimEvent) -> Array[Int] {
  match e {
    EvSend(from~, to~, ..) => [from, to]
    EvDeliver(from~, to~, ..) => [from, to]
    EvScheduled(task_id~, ..) => [task_id]
    EvCompleted(task_id~, ..) => [task_id]
    EvFaulted(task_id~, ..) => [task_id]
  }
}

///|
/// 返回事件携带的消息 id（`EvSend` / `EvDeliver`），其余事件返回 `None`。
fn event_msg_id(e : SimEvent) -> Int? {
  match e {
    EvSend(msg~, ..) => Some(msg.id)
    EvDeliver(msg~, ..) => Some(msg.id)
    _ => None
  }
}

///|
/// 事件依赖关系（R6.2）：同一节点参与、或同一消息 id 关联的两事件为依赖（不可
/// 交换）；作用于不同节点且无消息因果关联者为独立（可交换）。
pub fn depends(a : SimEvent, b : SimEvent) -> Bool {
  let na = event_nodes(a)
  let nb = event_nodes(b)
  for x in na {
    for y in nb {
      if x == y {
        return true
      }
    }
  }
  match (event_msg_id(a), event_msg_id(b)) {
    (Some(i), Some(j)) => if i == j { return true }
    _ => ()
  }
  false
}

///|
/// 由探针运行推导任务级依赖矩阵（按 `ids` 中位置索引）：两任务若存在直接消息往来
/// 则依赖。对角线（同一任务）恒为依赖。
fn build_task_dep(
  seed : UInt64,
  scenario : DesScenario,
  ids : Array[Int],
) -> Array[Array[Bool]] {
  let n = ids.length()
  let dep : Array[Array[Bool]] = []
  for _i in 0..<n {
    let row : Array[Bool] = []
    for _j in 0..<n {
      row.push(false)
    }
    dep.push(row)
  }
  for i in 0..<n {
    dep[i][i] = true
  }
  let probe = run_des(seed, scenario)
  for e in probe.trace {
    match e {
      EvSend(from~, to~, ..) => {
        let fi = index_of_id(ids, from)
        let ti = index_of_id(ids, to)
        if fi >= 0 && ti >= 0 {
          dep[fi][ti] = true
          dep[ti][fi] = true
        }
      }
      _ => ()
    }
  }
  dep
}

///|
/// 返回 id 在 `ids` 中的下标，不存在返回 -1。
fn index_of_id(ids : Array[Int], id : Int) -> Int {
  for i in 0..<ids.length() {
    if ids[i] == id {
      return i
    }
  }
  -1
}

///|
/// 任务 `a` 与 `b` 是否独立（可交换）。
fn task_indep(dep : Array[Array[Bool]], ids : Array[Int], a : Int, b : Int) -> Bool {
  let ia = index_of_id(ids, a)
  let ib = index_of_id(ids, b)
  if ia < 0 || ib < 0 {
    false
  } else {
    !dep[ia][ib]
  }
}

///|
/// 数组是否包含某 id。
fn contains_id(xs : Array[Int], id : Int) -> Bool {
  for x in xs {
    if x == id {
      return true
    }
  }
  false
}

///|
/// 睡眠集 DPOR 递归：`remaining` 为待调度任务 id，`sleep` 为已睡眠（独立且已探索）
/// 任务 id，`order` 为已选择前缀。到达深度上界或 `remaining` 为空即在该代表交错上
/// 执行一次仿真；否则对每个非睡眠任务展开，展开后将其加入兄弟分支睡眠集（独立者
/// 传递睡眠，依赖者唤醒）。
fn dpor_rec(
  seed : UInt64,
  scenario : DesScenario,
  ids : Array[Int],
  dep : Array[Array[Bool]],
  remaining : Array[Int],
  sleep : Array[Int],
  order : Array[Int],
  limit : Int,
  acc : ExploreAcc,
) -> Unit {
  if order.length() >= limit || remaining.length() == 0 {
    acc.visit(seed, scenario, order)
    return
  }
  let local_sleep = sleep.copy()
  let mut any_explored = false
  for i in 0..<remaining.length() {
    let t = remaining[i]
    if contains_id(local_sleep, t) {
      continue
    }
    any_explored = true
    let next_remaining : Array[Int] = []
    for j in 0..<remaining.length() {
      if j != i {
        next_remaining.push(remaining[j])
      }
    }
    let child_sleep : Array[Int] = []
    for s in local_sleep {
      if task_indep(dep, ids, s, t) {
        child_sleep.push(s)
      }
    }
    let next_order = order.copy()
    next_order.push(t)
    dpor_rec(
      seed, scenario, ids, dep, next_remaining, child_sleep, next_order, limit,
      acc,
    )
    local_sleep.push(t)
  }
  // 若全部待调度任务均已睡眠（此交错类已被代表覆盖），不计入新交错。
  ignore(any_explored)
}

///|
/// DPOR 探索：基于事件依赖关系与睡眠集剪枝等价交错，对每个 Mazurkiewicz 迹等价类
/// 至少探索一个代表交错（R6.1 / R6.3）。`ExploreReport` 结构与 `explore_bounded`
/// 一致，便于差分对照（P10 / P11）。
pub fn explore_dpor(
  seed : UInt64,
  scenario : DesScenario,
  depth : Int,
) -> ExploreReport {
  let ids : Array[Int] = []
  for tk in scenario.tasks {
    ids.push(tk.id)
  }
  ids.sort_by(fn(a, b) { cmp_int(a, b) })
  let n = ids.length()
  let limit = if depth < n { depth } else { n }
  let dep = build_task_dep(seed, scenario, ids)
  let acc : ExploreAcc = { explored: 0, failing: None }
  dpor_rec(seed, scenario, ids, dep, ids, [], [], limit, acc)
  { explored: acc.explored, failing: acc.failing }
}
