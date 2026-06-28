// explore.mbt —— DST_Framework 旗舰深化：有界穷尽交错探索（旁路新增，设计 4.8）。
//
// 在深度上界内枚举任务唤醒顺序（交错）的全部可达排列，对每个交错执行一次 DES 并
// 对终态 / 不变量求值；与确定性随机搜索（`run_des`）互补。不修改既有 `run` /
// `run_des` 语义（R5.2）。
//
// 交错模型：调度的非确定性来源是「下一个唤醒哪个待调度任务」。一个 `Schedule`
// 记录任务 id 的唤醒顺序（排列 / 前缀）。`explore_bounded` 以 DFS 枚举深度 ≤
// `depth` 的全部排列（R5.1），每条经 `run_des_with_order` 执行；任一交错失败即记录
// 其可重放凭据（种子 + 轨迹，R5.3）；并报告已探索交错计数（覆盖可审计，R5.4）。

///|
/// 一个交错：各唤醒点选择的任务 id 顺序（一个排列 / 前缀）。
pub type Schedule = Array[Int]

///|
/// 探索报告：已探索交错计数 `explored`（覆盖可审计），与首个失败交错的可重放
/// 凭据 `failing`（种子 + 轨迹）。
pub(all) struct ExploreReport {
  explored : Int
  failing : (UInt64, Array[SimEvent])?
} derive(Eq, Debug)

///|
/// 探索累加器（DFS 期间就地累计计数与首个失败交错）。
priv struct ExploreAcc {
  mut explored : Int
  mut failing : (UInt64, Array[SimEvent])?
}

///|
/// 在一条完整 / 截断交错 `order` 上执行一次 DES，累计计数并记录首个失败交错。
fn ExploreAcc::visit(
  self : ExploreAcc,
  seed : UInt64,
  scenario : DesScenario,
  order : Array[Int],
) -> Unit {
  let r = run_des_with_order(seed, scenario, order)
  self.explored = self.explored + 1
  match self.failing {
    Some(_) => ()
    None => if des_is_failed(r) { self.failing = Some((seed, r.trace)) }
  }
}

///|
/// DFS 枚举深度 ≤ `limit` 的全部任务唤醒排列；`remaining` 为尚未选择的任务 id，
/// `order` 为已选择前缀。到达深度上界或 `remaining` 为空即在该交错上执行一次仿真。
fn explore_rec(
  seed : UInt64,
  scenario : DesScenario,
  remaining : Array[Int],
  order : Array[Int],
  limit : Int,
  acc : ExploreAcc,
) -> Unit {
  if order.length() >= limit || remaining.length() == 0 {
    acc.visit(seed, scenario, order)
    return
  }
  for i in 0..<remaining.length() {
    let next_remaining : Array[Int] = []
    for j in 0..<remaining.length() {
      if j != i {
        next_remaining.push(remaining[j])
      }
    }
    let next_order = order.copy()
    next_order.push(remaining[i])
    explore_rec(seed, scenario, next_remaining, next_order, limit, acc)
  }
}

///|
/// 在深度上界 `depth` 内枚举全部可达任务交错，对每个交错执行一次仿真（R5.1）。
///
/// 返回的 `ExploreReport.explored` 为已探索交错数（深度 ≥ 任务数时即 n! 个完整
/// 排列）；`failing` 在存在失败交错时携带可经 `replay_des` 复现的种子 + 轨迹。
pub fn explore_bounded(
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
  let acc : ExploreAcc = { explored: 0, failing: None }
  explore_rec(seed, scenario, ids, [], limit, acc)
  { explored: acc.explored, failing: acc.failing }
}
