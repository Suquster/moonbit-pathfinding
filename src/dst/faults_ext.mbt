// faults_ext.mbt —— DST_Framework 旗舰深化：丰富故障模型（旁路新增，设计 4.5）。
//
// 「枚举不扩容」取舍（R12.4）：既有 `FaultKind`（`pub(all) enum`，含 `Crash` /
// `Delay` / `Drop`）不可追加变体（会破坏下游穷尽匹配）。故本文件新增**平行**扩展
// 故障枚举 `NetFaultKind`，其 `Crash` / `Delay` / `Drop` 与既有语义等价、其余为
// 旗舰新增（`Partition` / `Reorder` / `Duplicate` / `ClockSkew` / `Byzantine`）。
// 同包两个枚举可共存（构造时以 `NetFaultKind::` 限定消歧，模式匹配按上下文类型
// 推断）。向后兼容桥 `*::of_legacy` 把既有故障无损提升为扩展形态。
//
// 注入点确定性（R3.7）：扩展策略 `FaultPolicyEx` 由「(步序号 at_step, 目标任务
// task_id)」精确定位；DES 引擎沿用既有 `run` 的规范化范式——故障按 `(at_step,
// task_id)` 升序处理，使同种子下故障在同一注入点触发、含故障运行可被精确重放。

///|
/// 扩展故障类型（network / fault kind）——既有 `FaultKind` 的平行旁路扩展。
///
///   * `Crash`                       —— 任务崩溃（语义同既有 `Crash`，整体终态 `Failed`）；
///   * `Delay(by)`                   —— 延迟（语义同既有 `Delay`，附确定延迟量 `by`）；
///   * `Drop`                        —— 丢弃（语义同既有 `Drop`，并阻断该任务消息）；
///   * `Partition(group, until_step)`—— 网络分区：任务属于 `group`，在 `[at_step,
///                                      until_step)` 内阻断跨组消息投递；
///   * `Reorder`                     —— 消息重排：确定性改变受影响消息投递顺序；
///   * `Duplicate`                   —— 消息重复：受影响消息被投递两次；
///   * `ClockSkew(offset)`           —— 时钟偏移：对目标任务本地逻辑时钟施加偏移；
///   * `Byzantine`                   —— 可选：任务向不同对端发送相互矛盾内容；
///   * `DiskFault(lose)`             —— 磁盘故障：目标节点丢失复制日志末尾
///                                      `lose` 条已持久条目（torn-write / 丢写建模，
///                                      对标 TigerBeetle VOPR 存储故障注入）。
pub(all) enum NetFaultKind {
  Crash
  Delay(by~ : LogicalTime)
  Drop
  Partition(group~ : Int, until_step~ : Int)
  Reorder
  Duplicate
  ClockSkew(offset~ : Int64)
  Byzantine
  DiskFault(lose~ : Int)
} derive(Eq, Debug)

///|
/// 扩展故障策略——注入点由「(步序号, 目标任务)」精确定位（R3.7）。
pub(all) struct FaultPolicyEx {
  at_step : Int
  task_id : Int
  kind : NetFaultKind
} derive(Eq, Debug)

///|
/// 由注入点、目标任务与扩展故障类型构造故障策略。
pub fn FaultPolicyEx::new(
  at_step : Int,
  task_id : Int,
  kind : NetFaultKind,
) -> FaultPolicyEx {
  { at_step, task_id, kind }
}

///|
/// 向后兼容桥：把既有 `FaultKind` 提升为扩展形态（语义等价）。
///
///   * `Crash → Crash`、`Delay → Delay(by=1)`（既有 `Delay` 无量纲，提升为最小延迟
///     1 个逻辑时间单位）、`Drop → Drop`。
pub fn NetFaultKind::of_legacy(k : FaultKind) -> NetFaultKind {
  match k {
    Crash => NetFaultKind::Crash
    Delay => NetFaultKind::Delay(by=1UL)
    Drop => NetFaultKind::Drop
  }
}

///|
/// 向后兼容桥：把既有 `FaultPolicy` 提升为扩展故障策略（注入点与语义等价）。
pub fn FaultPolicyEx::of_legacy(p : FaultPolicy) -> FaultPolicyEx {
  {
    at_step: p.at_step,
    task_id: p.task_id,
    kind: NetFaultKind::of_legacy(p.kind),
  }
}

///|
/// 比较两条扩展故障策略的规范顺序（按 `(at_step, task_id)` 升序），供引擎规范化
/// 注入顺序（沿用既有 `run` 的 `(at_step, task_id)` 升序范式）。
pub fn fault_ex_cmp(a : FaultPolicyEx, b : FaultPolicyEx) -> Int {
  if a.at_step != b.at_step {
    cmp_int(a.at_step, b.at_step)
  } else {
    cmp_int(a.task_id, b.task_id)
  }
}
