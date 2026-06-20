// behavior.mbt —— 行为与处理上下文（任务 1.1，Requirement 5）。
//
// 本文件在冻结的既有骨架之上**旁路新增**行为切换（become / unbecome）所需的
// 平行类型，不修改任何既有 `pub(all)` 类型与 `Scheduler[S, M]`：
//
//   * `Behavior[S, M]` —— 一个 actor 当前生效的消息处理函数（包装为结构以入行为栈）；
//   * `ActorContext[S, M]` —— 处理上下文，handler 经此**记录效果**，由 `ActorSystem`
//     在 `step` 末尾确定性地统一应用（避免隐藏可变状态导致的三后端分歧）；
//   * 纯行为栈 helper —— `Array[Behavior]` 的 push / top / pop，深度 == 1 时 pop 为
//     空操作（不弹空初始行为，Requirement 5.4）。
//
// 返回值复用既有冻结枚举 `ActorOutcome[S]`（`Updated` / `Errored`），不新增结果类型。

// ───────────────────────────── 行为（Behavior） ──────────────────────────

///|
/// 行为（behavior）—— 一个 actor 当前生效的消息处理函数。
///
/// 包装为结构以便压入行为栈（Requirement 5.1）。`receive` 接收处理上下文
/// `ActorContext`（用于记录 become / unbecome / stash / watch 等效果）、当前状态
/// 与消息，返回既有 `ActorOutcome[S]`。
pub(all) struct Behavior[S, M] {
  receive : (ActorContext[S, M], S, M) -> ActorOutcome[S]
}

///|
/// 以处理函数构造一个行为。
pub fn[S, M] Behavior::new(
  receive : (ActorContext[S, M], S, M) -> ActorOutcome[S],
) -> Behavior[S, M] {
  { receive, }
}

///|
/// 以给定上下文、状态与消息驱动该行为的处理函数，返回处理结果。
pub fn[S, M] Behavior::apply(
  self : Behavior[S, M],
  ctx : ActorContext[S, M],
  state : S,
  msg : M,
) -> ActorOutcome[S] {
  (self.receive)(ctx, state, msg)
}

// ───────────────────────────── 处理上下文（Context） ─────────────────────

///|
/// handler 可记录的效果集合 —— 旁路新增，不污染既有冻结枚举。
///
/// `step` 末尾由 `ActorSystem` 按记录顺序统一应用，保证确定性、可测、无后端差异。
/// 以 `pub(all)` 暴露（仅新增、不改既有 API），因携带闭包故不派生 `Eq` / `Show`。
pub(all) enum ContextEffect[S, M] {
  /// become(b)：压入新行为。
  PushBehavior(Behavior[S, M])
  /// unbecome()：弹出栈顶行为（深度 == 1 时为空操作）。
  PopBehavior
  /// stash：把当前消息暂存到暂存缓冲。
  StashCurrent
  /// unstash_all：把暂存缓冲全部消息按原相对顺序回流到邮箱队首之前。
  UnstashAll
  /// watch(target, on_terminated)：登记对 target 终止的监视，附 Akka watchWith 风格适配器。
  Watch(ActorId, (ActorId, TerminationReason) -> M)
  /// unwatch(target)：撤销对 target 的监视。
  Unwatch(ActorId)
}

///|
/// 处理上下文（actor context）—— handler 经此记录效果。
///
/// `self_id` 为当前正在处理消息的 actor 标识；`effects` 为本次处理累积的效果列表，
/// 由 `ActorSystem` 在 `step` 末尾按顺序统一应用（Requirement 5.2 / 5.3 / 6.1 / 7.1）。
pub struct ActorContext[S, M] {
  self_id : ActorId
  effects : Array[ContextEffect[S, M]]
}

///|
/// 创建一个针对 `self_id` 的空效果上下文。
pub fn[S, M] ActorContext::new(self_id : ActorId) -> ActorContext[S, M] {
  { self_id, effects: [] }
}

///|
/// 当前上下文所属 actor 的标识。
pub fn[S, M] ActorContext::id(self : ActorContext[S, M]) -> ActorId {
  self.self_id
}

///|
/// 本次处理已记录的效果条数（观测用，便于测试见证记录顺序与数量）。
pub fn[S, M] ActorContext::effect_count(self : ActorContext[S, M]) -> Int {
  self.effects.length()
}

///|
/// 记录 `become(next)` 效果：后续消息将由 `next` 处理（Requirement 5.2）。
///
/// 命名 `become_`（尾下划线）避免与潜在关键字冲突，沿用既有房屋风格。
pub fn[S, M] ActorContext::become_(
  self : ActorContext[S, M],
  next : Behavior[S, M],
) -> Unit {
  self.effects.push(PushBehavior(next))
}

///|
/// 记录 `unbecome()` 效果：恢复到前一行为（深度 == 1 时为空操作，Requirement 5.3 / 5.4）。
pub fn[S, M] ActorContext::unbecome(self : ActorContext[S, M]) -> Unit {
  self.effects.push(PopBehavior)
}

///|
/// 记录 `stash` 效果：把当前消息暂存而不立即处理（Requirement 6.1）。
pub fn[S, M] ActorContext::stash(self : ActorContext[S, M]) -> Unit {
  self.effects.push(StashCurrent)
}

///|
/// 记录 `unstash_all` 效果：把暂存消息按原相对顺序回流到邮箱队首之前（Requirement 6.2）。
pub fn[S, M] ActorContext::unstash_all(self : ActorContext[S, M]) -> Unit {
  self.effects.push(UnstashAll)
}

///|
/// 记录 `watch(target)` 效果：登记对 target 终止的监视（Requirement 7.1）。
///
/// `on_terminated` 为 Akka `watchWith` 风格适配器，把 `(ActorId, TerminationReason)`
/// 映射为该监视者的消息类型 `M`，避免向冻结的 `M` / `ActorOutcome` 注入系统消息变体。
pub fn[S, M] ActorContext::watch(
  self : ActorContext[S, M],
  target : ActorId,
  on_terminated : (ActorId, TerminationReason) -> M,
) -> Unit {
  self.effects.push(Watch(target, on_terminated))
}

///|
/// 记录 `unwatch(target)` 效果：撤销对 target 的监视（Requirement 7.3）。
pub fn[S, M] ActorContext::unwatch(
  self : ActorContext[S, M],
  target : ActorId,
) -> Unit {
  self.effects.push(Unwatch(target))
}

// ───────────────────────────── 纯行为栈 helper ───────────────────────────

///|
/// 以初始行为构造一个行为栈（栈底恒为初始行为，Requirement 5.1）。
pub fn[S, M] behavior_stack_new(
  initial : Behavior[S, M],
) -> Array[Behavior[S, M]] {
  [initial]
}

///|
/// 行为栈深度。
pub fn[S, M] behavior_stack_depth(stack : Array[Behavior[S, M]]) -> Int {
  stack.length()
}

///|
/// 压入新行为（become，Requirement 5.2）。
pub fn[S, M] behavior_stack_push(
  stack : Array[Behavior[S, M]],
  next : Behavior[S, M],
) -> Unit {
  stack.push(next)
}

///|
/// 弹出栈顶行为（unbecome，Requirement 5.3）；深度 <= 1 时为**空操作**，
/// 不弹空初始行为（Requirement 5.4）。
pub fn[S, M] behavior_stack_pop(stack : Array[Behavior[S, M]]) -> Unit {
  if stack.length() > 1 {
    let _ = stack.pop()
  }
}

///|
/// 当前生效的栈顶行为（每条消息由其被处理时刻的栈顶行为处理，Requirement 5.6）。
/// 空栈返回 None（由构造保证非空，正常调用恒为 Some）。
pub fn[S, M] behavior_stack_top(
  stack : Array[Behavior[S, M]],
) -> Behavior[S, M]? {
  if stack.is_empty() {
    None
  } else {
    Some(stack[stack.length() - 1])
  }
}
