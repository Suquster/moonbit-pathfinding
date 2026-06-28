// deterministic.mbt —— 确定性调度的 trace 事件与重放校验（任务 11.1 / 11.18，Requirement 10）。
//
//   * `TraceEvent{actor, seq}` —— 一次处理事件：actor id × 全局序号（Requirement 10.3）；
//   * `replay_consistent` —— 以同一种子与同一构造函数运行两次，比对 trace 逐事件
//     一致（Requirement 10.2 / 10.6）。

///|
/// 处理事件（trace event）—— 记录「哪个 actor 在第几个全局序号处处理了一条消息」。
///
/// `seq` 为单调递增的全局逻辑时钟（每处理一条消息加一），与 `ActorSystem::clock`
/// 同步。该序列供检视与重放比对（Requirement 10.3）。
pub(all) struct TraceEvent {
  actor : ActorId
  seq : Int
} derive(Eq, Debug)

///|
/// 重放校验（Requirement 10.2 / 10.6）—— 以同一种子 `seed` 调用构造函数 `build`
/// 两次（各自独立构造并跑至空闲），比对两次的处理序列是否逐事件一致。
///
/// `build(seed)` 应返回一个**已派生好 actor 与初始消息**的 `ActorSystem`（通常以
/// `ActorSystem::with_seed(seed)` 构造），本函数对其各执行一次 `run_until_idle`
/// 后取 `trace_of` 比对。
pub fn[S, M] replay_consistent(
  seed : UInt64,
  build : (UInt64) -> ActorSystem[S, M],
) -> Bool {
  let sys_a = build(seed)
  sys_a.run_until_idle()
  let trace_a = sys_a.trace_of()
  let sys_b = build(seed)
  sys_b.run_until_idle()
  let trace_b = sys_b.trace_of()
  if trace_a.length() != trace_b.length() {
    return false
  }
  for i in 0..<trace_a.length() {
    if trace_a[i] != trace_b[i] {
      return false
    }
  }
  true
}
