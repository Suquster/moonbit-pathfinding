// release.mbt —— 方向五（LSP_Binding / LSP_Server）的独立发布元数据登记。
//
// 对应任务 14.6 / Requirement 11.5：每个方向作为独立发布单元，拥有独立的
// 语义化版本号与 changelog。方向五由两个子包构成——`lsp_binding`（JSON-RPC
// 2.0 协议类型与编解码/分发框架）与 `lsp_server`（依赖前者的能力处理器层，
// 是方向对外入口）。二者作为**单一发布单元**统一登记，发布名称取 "lsp"：
//
//   * 版本号：骨架首版统一登记为 "0.1.0"（见 lsp_version）；
//   * changelog：路径由 @release_meta.default_changelog_path 推导，固定为
//     "src/lsp/CHANGELOG.md"——但本发布单元的 changelog 实际维护在方向入口
//     子包 `src/lsp_server/CHANGELOG.md`（见 lsp_changelog_path）；
//   * 发布身份：由 release_info() 返回一个 @release_meta.DirectionRelease。
//
// 放置位置说明（design.md §「数据模型 → 发布元数据模型」）：
//   发布元数据**由各方向自身登记**，而非集中堆放在 release_meta 包内——
//   release_meta 是不依赖任何方向子包的横切叶子包，仅承载纯数据模型与纯
//   函数；各方向通过向下依赖（import @release_meta）复用模型并登记自己的
//   DirectionRelease。方向五在入口子包 lsp_server 登记（它依赖 lsp_binding），
//   从而把两个子包收敛为一个自包含的发布单元。

///|
/// 本方向的独立 SemVer 版本号（骨架首版）。
pub let lsp_version : String = "0.1.0"

///|
/// 本发布单元的名称。方向五由 lsp_binding + lsp_server 两个子包组成，
/// 作为单一发布单元统一以 "lsp" 标识（而非任一子包目录名）。
pub let lsp_name : String = "lsp"

///|
/// 本发布单元 changelog 的实际维护路径。
///
/// 默认约定路径为 `src/{name}/CHANGELOG.md`（即 `src/lsp/CHANGELOG.md`），
/// 但方向五没有名为 `lsp` 的物理子包目录——changelog 维护在方向对外入口
/// 子包 `src/lsp_server/CHANGELOG.md`。`release_info()` 以此实际路径登记，
/// 确保发布元数据指向真实存在的文件。
pub let lsp_changelog_path : String = "src/lsp_server/CHANGELOG.md"

///|
/// 登记并返回方向五（LSP）的发布元数据。
///
/// `release_ready` 经由 `@release_meta.aggregate_release_ready` 依质量门禁
/// 三要素（测试 / 证明谓词 / 可执行文档）聚合计算，杜绝「门禁未全绿却标记
/// 为就绪」的不一致（Requirement 11.6）。本方向无独立证明谓词文件，证明门禁
/// 视为不适用即默认通过；测试与可执行文档门禁是否通过由调用方（CI 聚合）
/// 给定，骨架阶段默认保守标记为未就绪。
pub fn release_info() -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::new(
    lsp_name, lsp_version, lsp_changelog_path,
    // 骨架阶段：可选属性测试 / 可执行文档任务尚在推进，保守标记为未就绪，
    // 待全部门禁绿后由 CI 聚合 evaluate 提升。
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
    lsp_name, lsp_version, lsp_changelog_path, gates,
  )
}
