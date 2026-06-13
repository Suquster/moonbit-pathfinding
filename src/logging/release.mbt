// release.mbt —— Logging_Library 方向（R7）的独立发布元数据登记。
//
// 对应任务 10.6 / Requirement 11.5：每个方向作为独立发布单元，拥有独立的
// 语义化版本号与 changelog。本文件把该约定落地为可被测试验证的登记入口：
//
//   * 版本号：骨架首版统一登记为 "0.1.0"（见 logging_version）；
//   * changelog：路径由 @release_meta.default_changelog_path 推导，固定为
//     "src/logging/CHANGELOG.md"；
//   * 发布身份：由 release_info() 返回一个 @release_meta.DirectionRelease。
//
// 放置位置说明（design.md §「数据模型 → 发布元数据模型」）：
//   发布元数据**由各方向自身登记**，而非集中堆放在 release_meta 包内——
//   release_meta 是不依赖任何方向子包的横切叶子包，仅承载纯数据模型与纯
//   函数；各方向通过向下依赖（import @release_meta）复用模型并登记自己的
//   DirectionRelease，从而保持方向自包含、release_meta 零反向耦合。

///|
/// 本方向的独立 SemVer 版本号。
///
/// 自骨架首版 `0.1.0` 推进至 `0.2.0`（次版本）：本次旗舰深化以**严格向后兼容**
/// 的方式新增大量能力（嵌套取值与嵌套 JSON 往返、多 formatter/sink、采样限流、
/// 过滤路由、OTel span 语义、W3C traceparent、脱敏、指标派生、端到端 demo），
/// 既有公开类型/函数签名与语义冻结、`Value` 仅加性追加 `VMap`/`VList`，故按
/// 0.x 约定以次版本推进（Requirement 12.6 / 13.6）。
pub let logging_version : String = "0.2.0"

///|
/// 本方向的包名（与子包目录名一致），用于推导 changelog 路径与发布身份。
pub let logging_name : String = "logging"

///|
/// 登记并返回 Logging_Library 方向的发布元数据。
///
/// `release_ready` 经由 `@release_meta.aggregate_release_ready` 依质量门禁
/// 三要素（测试 / 证明谓词 / 可执行文档）聚合计算，杜绝「门禁未全绿却标记
/// 为就绪」的不一致（Requirement 11.6）。本方向无独立证明谓词文件，证明门禁
/// 视为不适用即默认通过；测试与可执行文档门禁是否通过由调用方（CI 聚合）
/// 给定，骨架阶段默认保守标记为未就绪。
pub fn release_info() -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::new(
    logging_name,
    logging_version,
    @release_meta.default_changelog_path(logging_name),
    // 骨架阶段：完整实现（10.2）、可选属性测试 / 可执行文档任务尚在推进，
    // 保守标记为未就绪，待全部门禁绿后由 CI 聚合 evaluate 提升。
    false,
  )
}

///|
/// 依据运行期质量门禁三要素评估并登记本方向发布元数据。
///
/// 供 CI 聚合门禁（任务 18.1）在收集到三后端测试 / 证明谓词 / 可执行文档
/// 的真实通过状态后调用，得到 `release_ready` 与门禁一致的 `DirectionRelease`。
pub fn release_info_with_gates(
  gates : @release_meta.QualityGates,
) -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::evaluate(
    logging_name,
    logging_version,
    @release_meta.default_changelog_path(logging_name),
    gates,
  )
}
