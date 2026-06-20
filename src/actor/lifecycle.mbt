// lifecycle.mbt —— 生命周期钩子与重启语义（任务 2.1，Requirement 3）。
//
// 本文件旁路新增 actor 生命周期钩子与重启语义所需的平行类型，不修改既有骨架：
//
//   * `LifecycleHooks[S]` —— pre_start / post_stop / pre_restart / post_restart 四钩子，
//     `LifecycleHooks::identity()` 给出全默认（恒等 / 空操作）实现；
//   * `TerminationReason` —— 投递给监视者的 `Terminated` 所携带的终止原因；
//   * `restart_state` —— 纯重启 reducer，严格按 `pre_restart → 以初始状态重置 →
//     post_restart` 顺序产出重启后状态（Requirement 3.3 / 3.5）。

// ───────────────────────────── 终止原因 ──────────────────────────────────

///|
/// 终止原因（termination reason）—— 被监视 actor 终止时投递给监视者的原因（Requirement 7.2）。
///
///   * `StoppedNormally` —— 因 `stop` 请求或 `Stop` 指令正常终止；
///   * `FailedWith(String)` —— 因未捕获错误终止，附带原因描述。
pub(all) enum TerminationReason {
  /// 正常停止。
  StoppedNormally
  /// 因错误失败，附带原因。
  FailedWith(String)
} derive(Eq, Show)

// ───────────────────────────── 生命周期钩子 ──────────────────────────────

///|
/// 生命周期钩子（lifecycle hooks）—— 四个生命周期转换点的回调（Requirement 3）。
///
///   * `pre_start`   —— 派生后、处理首条消息前调用一次，可加工初始状态（Requirement 3.1）；
///   * `post_stop`   —— 停止后调用一次（Requirement 3.2）；
///   * `pre_restart` —— 重启前调用，携带 (当前状态, 失败原因)（Requirement 3.3）；
///   * `post_restart`—— 以初始状态为入参、返回重启后初始状态（Requirement 3.3）。
pub(all) struct LifecycleHooks[S] {
  pre_start : (S) -> S
  post_stop : (S) -> Unit
  pre_restart : (S, String) -> Unit
  post_restart : (S) -> S
}

///|
/// 全默认钩子：`pre_start` / `post_restart` 为恒等，`post_stop` / `pre_restart` 为空操作。
///
/// 当 `spawn` 的可选 `hooks` 参数省略时取此默认，使无钩子需求的 actor 行为与
/// 既有骨架对齐。
pub fn[S] LifecycleHooks::identity() -> LifecycleHooks[S] {
  {
    pre_start: fn(s) { s },
    post_stop: fn(_s) {  },
    pre_restart: fn(_s, _reason) {  },
    post_restart: fn(s) { s },
  }
}

///|
/// 以四回调构造生命周期钩子。
pub fn[S] LifecycleHooks::new(
  pre_start : (S) -> S,
  post_stop : (S) -> Unit,
  pre_restart : (S, String) -> Unit,
  post_restart : (S) -> S,
) -> LifecycleHooks[S] {
  { pre_start, post_stop, pre_restart, post_restart }
}

// ───────────────────────────── 重启 reducer ──────────────────────────────

///|
/// 纯重启 reducer（Requirement 3.3 / 3.5）—— 严格按以下顺序产出重启后状态：
///
///   1. 调用 `pre_restart(current, reason)`（携带当前状态与失败原因）；
///   2. 以**初始状态** `init` 为基准重置（不沿用失败前累积状态，Requirement 3.5）；
///   3. 调用 `post_restart(init)` 得到重启后初始状态并返回。
///
/// 行为栈重置为仅含初始行为、暂存缓冲清空（Requirement 5.5 / 6.4）与生命周期状态
/// 恢复 `Running`（Requirement 3.3 步四）由 `ActorSystem` 在接线时配合完成。
pub fn[S] restart_state(
  init : S,
  hooks : LifecycleHooks[S],
  current : S,
  reason : String,
) -> S {
  (hooks.pre_restart)(current, reason)
  (hooks.post_restart)(init)
}

///|
/// 启动 reducer（Requirement 3.1）—— 对初始状态调用一次 `pre_start` 得到启动后状态。
pub fn[S] start_state(init : S, hooks : LifecycleHooks[S]) -> S {
  (hooks.pre_start)(init)
}
