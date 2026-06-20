// release.mbt —— Mini_Compiler 方向（R1）的独立发布元数据登记。
//
// 对应任务 15.7 / Requirement 11.5：每个方向作为独立发布单元，拥有独立的
// 语义化版本号与 changelog。本文件把该约定落地为可被测试验证的登记入口：
//
//   * 版本号：骨架首版登记为 "0.1.0"，0.2.0 起为旗舰深化版（见
//     mini_compiler_version）；
//   * changelog：路径由 @release_meta.default_changelog_path 推导，固定为
//     "src/mini_compiler/CHANGELOG.md"；
//   * 发布身份：由 release_info() 返回一个 @release_meta.DirectionRelease。
//
// 放置位置说明（design.md §「数据模型 → 发布元数据模型」）：发布元数据由
// 各方向自身登记，release_meta 是不依赖任何方向子包的横切叶子包；各方向通过
// 向下依赖 import @release_meta 复用模型并登记自己的 DirectionRelease，从而
// 保持方向自包含、release_meta 零反向耦合。

///|
/// 本方向的独立 SemVer 版本号。
///
/// `0.2.0`（次版本号 +1）登记**旗舰深化**版本：在 `0.1.0` 骨架基线之上，以
/// bypass-additive 方式新增 MiniML 语言层（HM 类型推断 / 树遍历解释器 / 栈式
/// 字节码后端与 VM / AST 优化 / 统一流水线 / 旗舰 demo / 基准 / 可执行文档 /
/// 16 条正确性属性 PBT）。变更为**向后兼容的增量特性**——既有 MiniLet 的
/// `lex` / `parse` / `check` / `eval` / `print_ast` / `compile` 公开行为冻结，
/// 故按 SemVer 取次版本号递进而非主版本号。
pub let mini_compiler_version : String = "0.2.0"

///|
/// 本方向的包名（与子包目录名一致），用于推导 changelog 路径与发布身份。
pub let mini_compiler_name : String = "mini_compiler"

///|
/// 登记并返回 Mini_Compiler 方向的发布元数据。
///
/// `release_ready` 经由 `@release_meta.aggregate_release_ready` 依质量门禁
/// 三要素（测试 / 证明谓词 / 可执行文档）聚合计算，杜绝「门禁未全绿却标记
/// 为就绪」的不一致（Requirement 11.6）。骨架阶段可选属性测试 / 可执行文档
/// 任务尚在推进，保守标记为未就绪，待全部门禁绿后由 CI 聚合 evaluate 提升。
pub fn release_info() -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::new(
    mini_compiler_name,
    mini_compiler_version,
    @release_meta.default_changelog_path(mini_compiler_name),
    false,
  )
}

///|
/// 依据运行期质量门禁三要素评估并登记本方向发布元数据。
///
/// 供 CI 聚合门禁在收集到**三后端测试**（wasm-gc / js / native 一致通过）/
/// **属性测试**（16 条正确性属性 PBT 全绿）/ **可执行文档**（`*.mbt.md`
/// 端到端跑通）三要素的真实通过状态后调用，由
/// `@release_meta.aggregate_release_ready` 聚合得到 `release_ready` 与门禁
/// 一致的 `DirectionRelease`——杜绝「门禁未全绿却标记为就绪」的不一致。
/// 0.2.0 旗舰深化沿用既有签名，仅推进版本常量与门禁聚合语义。
pub fn release_info_with_gates(
  gates : @release_meta.QualityGates,
) -> @release_meta.DirectionRelease {
  @release_meta.DirectionRelease::evaluate(
    mini_compiler_name,
    mini_compiler_version,
    @release_meta.default_changelog_path(mini_compiler_name),
    gates,
  )
}
