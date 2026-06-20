// deathwatch.mbt —— 死亡监视与 Terminated 投递（任务 7.1，Requirement 7）。
//
// `WatchRegistry[M]` 以**数组**承载监视条目（保证遍历顺序确定，三后端一致）：
//
//   * `watch`   —— 登记监视关系（Requirement 7.1）；
//   * `unwatch` —— 置条目非 active，使其后终止不再通知（Requirement 7.3）；
//   * 投递 Terminated 经用户提供的 `on_terminated` 适配器映射为监视者消息类型 `M`
//     （Akka watchWith 风格），避免向冻结的 `M` / `ActorOutcome` 注入系统消息变体。
//
// 终止通知的实际投递（含「watch 已终止 target 立即投递」、同一监视者×同一终止
// 至多一条）由 `ActorSystem` 在任务 11.14 接线；本文件提供注册表数据结构与查询。

///|
/// 监视条目（watch entry）—— target → 监视者及其 Terminated 适配器。
/// 以 `pub(all)` 暴露（仅新增），因携带闭包故不派生 `Eq` / `Show`。
pub(all) struct WatchEntry[M] {
  target : ActorId
  watcher : ActorId
  on_terminated : (ActorId, TerminationReason) -> M
  mut active : Bool
}

///|
/// 监视注册表（watch registry）—— 以数组承载条目，遍历顺序确定。
pub struct WatchRegistry[M] {
  entries : Array[WatchEntry[M]]
}

///|
/// 创建一个空监视注册表。
pub fn[M] WatchRegistry::new() -> WatchRegistry[M] {
  { entries: [] }
}

///|
/// 登记监视关系（Requirement 7.1）。
///
/// 幂等性：若 (watcher, target) 已存在一个 active 条目，则刷新其适配器而不新增重复
/// 条目，保证「同一监视者×同一 target」仅有一个有效监视（配合 Requirement 7.5）。
pub fn[M] WatchRegistry::watch(
  self : WatchRegistry[M],
  watcher : ActorId,
  target : ActorId,
  on_terminated : (ActorId, TerminationReason) -> M,
) -> Unit {
  for entry in self.entries {
    if entry.active && entry.watcher == watcher && entry.target == target {
      // 已存在 active 监视：刷新适配器，避免重复条目。
      entry.active = true
      return
    }
  }
  self.entries.push({ target, watcher, on_terminated, active: true })
}

///|
/// 撤销监视关系（Requirement 7.3）—— 置所有匹配 (watcher, target) 的条目为非 active。
pub fn[M] WatchRegistry::unwatch(
  self : WatchRegistry[M],
  watcher : ActorId,
  target : ActorId,
) -> Unit {
  for entry in self.entries {
    if entry.watcher == watcher && entry.target == target {
      entry.active = false
    }
  }
}

///|
/// 收集监视某 target 的全部 active 监视者及其适配器，**并将这些条目置为非 active**
/// （保证同一监视者×同一终止至多投递一条，Requirement 7.5 / 7.6）。
///
/// 返回 `(watcher, message)` 列表，由 `ActorSystem` 据此向各监视者邮箱投递消息。
/// 遍历按登记顺序，结果顺序确定（三后端一致）。
pub fn[M] WatchRegistry::collect_terminations(
  self : WatchRegistry[M],
  target : ActorId,
  reason : TerminationReason,
) -> Array[(ActorId, M)] {
  let result : Array[(ActorId, M)] = []
  for entry in self.entries {
    if entry.active && entry.target == target {
      let msg = (entry.on_terminated)(target, reason)
      result.push((entry.watcher, msg))
      entry.active = false
    }
  }
  result
}

///|
/// 当前 active 监视条目数（观测用）。
pub fn[M] WatchRegistry::active_count(self : WatchRegistry[M]) -> Int {
  let mut count = 0
  for entry in self.entries {
    if entry.active {
      count = count + 1
    }
  }
  count
}
