// supervision.mbt —— 监督策略、重启指令与最大重启强度（任务 3.1，Requirement 1 / 2）。
//
// 本文件旁路新增监督所需的平行类型与**纯 helper**（不修改既有骨架）：
//
//   * `SupervisionStrategy` —— OneForOne / OneForAll / RestForOne 三策略（Requirement 1.1）；
//   * `Directive` —— Restart / Stop / Escalate 三重启指令（Requirement 2.1）；
//   * `RestartIntensity{max_restarts, window}` —— 最大重启强度（Requirement 2.5）；
//   * `SupervisorSpec{strategy, intensity, default_directive}` —— 监督者配置；
//   * `affected_children` —— 纯 helper，给出某策略下一个子失败时的处置范围（Requirement 1.2~1.4）；
//   * `within_intensity` —— 纯 helper，判定窗口内是否仍可重启（Requirement 2.6 / 2.7）。

// ───────────────────────────── 监督策略 ──────────────────────────────────

///|
/// 监督策略（supervision strategy）—— 决定一个子失败时的影响范围（Requirement 1.1）。
///
///   * `OneForOne`  —— 仅处置失败者（Requirement 1.2）；
///   * `OneForAll`  —— 处置全部兄弟，含失败者（Requirement 1.3）；
///   * `RestForOne` —— 处置失败者及按启动顺序在其后的全部子（Requirement 1.4）。
pub(all) enum SupervisionStrategy {
  OneForOne
  OneForAll
  RestForOne
} derive(Eq, Show)

///|
/// 重启指令（directive）—— 对失败子的处置（Requirement 2.1）。
///
///   * `Restart`  —— 按钩子重启并恢复 `Running`（Requirement 2.2）；
///   * `Stop`     —— 永久终止为 `Stopped`（Requirement 2.3）；
///   * `Escalate` —— 上抛给上层 supervisor（Requirement 2.4）。
pub(all) enum Directive {
  Restart
  Stop
  Escalate
} derive(Eq, Show)

// ───────────────────────────── 重启强度 ──────────────────────────────────

///|
/// 最大重启强度（restart intensity）—— `window` 个逻辑时钟（step）内至多
/// `max_restarts` 次重启（Requirement 2.5）。
pub(all) struct RestartIntensity {
  max_restarts : Int
  window : Int
} derive(Eq, Show)

///|
/// 构造重启强度配置。
pub fn RestartIntensity::new(
  max_restarts : Int,
  window : Int,
) -> RestartIntensity {
  { max_restarts, window }
}

///|
/// 监督者配置（supervisor spec）—— 策略 + 强度 + 每子的默认指令。
///
/// 每个子也可在 `spawn` 时以可选 `directive` 单独覆盖其失败处置。
pub(all) struct SupervisorSpec {
  strategy : SupervisionStrategy
  intensity : RestartIntensity
  default_directive : Directive
} derive(Eq, Show)

///|
/// 构造监督者配置。
pub fn SupervisorSpec::new(
  strategy : SupervisionStrategy,
  intensity : RestartIntensity,
  default_directive : Directive,
) -> SupervisorSpec {
  { strategy, intensity, default_directive }
}

// ───────────────────────────── 纯 helper ─────────────────────────────────

///|
/// 处置范围（affected children）—— 给定策略、子总数与失败者下标（按启动顺序的
/// 0-based 索引），返回应被处置的子下标列表（升序，Requirement 1.2~1.4）：
///
///   * `OneForOne`  —— 仅 `[failed_index]`；
///   * `OneForAll`  —— 全部 `[0, 1, ..., child_count-1]`；
///   * `RestForOne` —— `[failed_index, ..., child_count-1]`（失败者及其后）。
///
/// `failed_index` 越界（`< 0` 或 `>= child_count`）时返回空列表（无可处置者）。
pub fn affected_children(
  strategy : SupervisionStrategy,
  child_count : Int,
  failed_index : Int,
) -> Array[Int] {
  let result : Array[Int] = []
  if failed_index < 0 || failed_index >= child_count {
    return result
  }
  match strategy {
    OneForOne => result.push(failed_index)
    OneForAll =>
      for i in 0..<child_count {
        result.push(i)
      }
    RestForOne =>
      for i in failed_index..<child_count {
        result.push(i)
      }
  }
  result
}

///|
/// 重启强度判定（within intensity）—— 在逻辑时钟 `clock` 处再触发一次重启前，
/// 判定该 actor 是否仍在强度上界之内（Requirement 2.6 / 2.7）。
///
/// 统计 `restart_times` 中落在当前窗口 `(clock - window, clock]` 内的历史重启次数，
/// 若该次数严格小于 `max_restarts`，则仍可重启（返回 `true`）；否则超限（返回
/// `false`），调用方据此升级（Escalate 上抛）或停止该 actor。
///
/// `window <= 0` 视为「不限定窗口」（统计全部历史重启）；`max_restarts <= 0` 表示
/// 不允许任何重启，恒返回 `false`。
pub fn within_intensity(
  restart_times : Array[Int],
  clock : Int,
  window : Int,
  max_restarts : Int,
) -> Bool {
  if max_restarts <= 0 {
    return false
  }
  let mut recent = 0
  for t in restart_times {
    if window <= 0 || t > clock - window {
      recent = recent + 1
    }
  }
  recent < max_restarts
}
