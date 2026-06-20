// release.mbt —— Actor_Framework 方向（R10）的独立发布元数据登记。
//
// 对应 Requirement 15.5 / 15.6：每个方向作为独立发布单元，拥有独立的
// 语义化版本号与 changelog，并经质量门禁聚合决定发布就绪。本文件把该约定
// 落地为可被测试验证的登记入口：
//
//   * 版本号：旗舰深化版登记为 "0.2.0"（见 actor_version）；
//   * changelog：路径由 @release_meta.default_changelog_path 推导，固定为
//     "src/actor/CHANGELOG.md"；
//   * 发布身份：由 release_info() 返回一个 @release_meta.DirectionRelease。
//
// SemVer 推进说明（Requirement 15.5）：
//   本次为旗舰深化（flagship deepening）——在 `0.1.0` 骨架之上新增大量能力
//   （监督树 / ask / become·unbecome / stash / death watch / router /
//   有界邮箱 / 确定性重放 / 受监督工作池等），同时完整保留并向后兼容既有
//   公开 API（`ActorId`/`Mailbox[M]`/`ActorRef[M]`/`Scheduler`/`spawn`/`send`/
//   `stop`/`reset_runtime` 等，见 Requirement 14）。依 SemVer 在 0.x 主版本下
//   新增向后兼容能力推进**次版本**，故自 `0.1.0` 推进至 `0.2.0`。
//
// 放置位置说明（design.md §「数据模型 → 发布元数据模型」）：
//   发布元数据**由各方向自身登记**，而非集中堆放在 release_meta 包内——
//   release_meta 是不依赖任何方向子包的横切叶子包，仅承载纯数据模型与纯
//   函数；各方向通过向下依赖（import @release_meta）复用模型并登记自己的
//   DirectionRelease，从而保持方向自包含、release_meta 零反向耦合。
//
// 关于 moonbitlang/async（design.md §「需求可追溯映射」R10）：
//   设计声明本方向依赖 `moonbitlang/async` 承载异步消息循环，但该外部依赖
//   尚未登记到本仓库 `moon.mod.json`，且引入存在三后端覆盖不一致的风险。
//   故本方向采用**本地确定性内存邮箱 + 同步驱动模型**（详见 moon.pkg
//   与 scheduler.mbt），对外契约（spawn / send / stop 与 FIFO / 串行 / 隔离
//   不变量）保持不变；待上游 API 稳定登记后可平滑替换为真实异步消息循环，
//   此演进将体现在本方向后续 SemVer 版本与 CHANGELOG 中。

///|
/// 本方向的独立 SemVer 版本号（旗舰深化版，自骨架 0.1.0 次版本推进）。
pub let actor_version : String = "0.2.0"

///|
/// 本方向的包名（与子包目录名一致），用于推导 changelog 路径与发布身份。
pub let actor_name : String = "actor"

///|
/// 登记并返回 Actor_Framework 方向的发布元数据。
///
/// `release_ready` 经由 `@release_meta.aggregate_release_ready` 依质量门禁
/// 三要素（测试 / 证明谓词 / 可执行文档）聚合计算，杜绝「门禁未全绿却标记
/// 为就绪」的不一致（Requirement 15.6）。本方向无独立证明谓词文件，证明门禁
/// 视为不适用即默认通过；测试与可执行文档门禁是否通过由调用方（CI 聚合）
/// 给定，静态登记默认保守标记为未就绪，待 CI 聚合 evaluate 提升。
pub fn release_info() -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::new(
    actor_name,
    actor_version,
    @release_meta.default_changelog_path(actor_name),
    // 静态登记：发布就绪需由 CI 聚合三门禁后 evaluate 提升，保守标记为未就绪。
    false,
  )
}

///|
/// 依据运行期质量门禁三要素评估并登记本方向发布元数据。
///
/// 供 CI 聚合门禁在收集到三后端测试 / 证明谓词 / 可执行文档的真实通过状态后
/// 调用，得到 `release_ready` 与门禁一致的 `DirectionRelease`：三门禁全绿方
/// 就绪，任一未通过即阻止发布就绪（Requirement 15.6）。
pub fn release_info_with_gates(
  gates : @release_meta.QualityGates,
) -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::evaluate(
    actor_name,
    actor_version,
    @release_meta.default_changelog_path(actor_name),
    gates,
  )
}
