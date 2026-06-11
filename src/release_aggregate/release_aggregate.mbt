// release_aggregate.mbt —— 全方向 release-ready 聚合门禁。
//
// 任务 18.1 / Requirement 11.1 与 11.6：
//   * R11.1：每个方向在 wasm-gc / native / js 三后端运行同一测试套件，任一
//     后端输出分歧判定为构建失败。该约束由仓库 `.github/workflows/ci.yml`
//     的三后端矩阵（`matrix.backend = [wasm-gc, js, native]`）落地——`moon
//     check` / `moon test` 不指定包名时作用于模块内**全部** `src` 子包，因此
//     本聚合包及其依赖的 10 个方向子包均自动纳入三后端门禁（接入零成本）。
//   * R11.6：当任一方向的「测试 / 证明谓词 / 可执行文档」校验未通过时，阻止
//     该方向进入发布就绪（release-ready）。本文件把「全方向聚合」实现为纯
//     函数：汇集全部 10 个方向的 `DirectionRelease`，**全部方向 release_ready
//     才整体就绪**，并随报告给出各方向清单，供 CI 聚合检查与属性测试复用。
//
// ── 10 个方向发布单元清单（与各方向 release.mbt 登记的名称一致）──────────
//   parser_combinator / regex_engine / serialization / build_tool / logging /
//   codegen_infra / dst / lsp（入口子包 lsp_server 登记）/ mini_compiler / actor

///|
/// 本套件纳入 release-ready 聚合门禁的方向（发布单元）总数。
///
/// 用作清单完整性的常量基线：聚合产出的方向清单长度必须恒等于本值，
/// 防止漏接或重复接入某个方向。
pub let direction_count : Int = 10

///|
/// 全套件级发布就绪报告。
///
/// * `directions`：全部 10 个方向的发布元数据清单（顺序稳定，便于快照比对
///   与三后端一致性校验）；
/// * `release_ready`：当且仅当清单中**每一个**方向都 `release_ready` 时为
///   `true`（Requirement 11.6 的全方向逻辑合取）。
pub(all) struct SuiteReleaseReport {
  directions : Array[@release_meta.DirectionRelease]
  release_ready : Bool
} derive(Eq, Show)

///|
/// 每个方向各自质量门禁三要素的入参集合。
///
/// 由 CI 聚合检查在收集到各方向三后端「测试 / 证明谓词 / 可执行文档」的真实
/// 通过状态后填充，再交由 `aggregate_suite` 评估为整体发布就绪报告。方向五
/// （LSP）以单一发布单元 `lsp` 表示（对应入口子包 lsp_server）。
pub(all) struct SuiteGates {
  parser_combinator : @release_meta.QualityGates
  regex_engine : @release_meta.QualityGates
  serialization : @release_meta.QualityGates
  build_tool : @release_meta.QualityGates
  logging : @release_meta.QualityGates
  codegen_infra : @release_meta.QualityGates
  dst : @release_meta.QualityGates
  lsp : @release_meta.QualityGates
  mini_compiler : @release_meta.QualityGates
  actor : @release_meta.QualityGates
} derive(Eq, Show)

///|
/// 收集全部 10 个方向**默认登记**的发布元数据（`release_info()`）。
///
/// 顺序稳定，长度恒为 `direction_count`。各方向在骨架阶段默认保守标记为
/// 未就绪，故本清单主要用于「方向清单完整性」与「身份字段（名称 / 版本 /
/// changelog 路径）」的审计与展示。
pub fn release_manifest() -> Array[@release_meta.DirectionRelease] {
  [
    @parser_combinator.release_info(),
    @regex_engine.release_info(),
    @serialization.release_info(),
    @build_tool.release_info(),
    @logging.release_info(),
    @codegen_infra.release_info(),
    @dst.release_info(),
    @lsp_server.release_info(),
    @mini_compiler.release_info(),
    @actor.release_info(),
  ]
}

///|
/// 依据各方向质量门禁三要素，收集全部 10 个方向的发布元数据。
///
/// 每个方向的 `release_ready` 由其 `release_info_with_gates` 经
/// `@release_meta.aggregate_release_ready`（测试 ∧ 证明谓词 ∧ 可执行文档）
/// 计算，杜绝「门禁未全绿却标记为就绪」的不一致。顺序与 `release_manifest`
/// 保持一致，长度恒为 `direction_count`。
pub fn collect_direction_releases(
  gates : SuiteGates,
) -> Array[@release_meta.DirectionRelease] {
  [
    @parser_combinator.release_info_with_gates(gates.parser_combinator),
    @regex_engine.release_info_with_gates(gates.regex_engine),
    @serialization.release_info_with_gates(gates.serialization),
    @build_tool.release_info_with_gates(gates.build_tool),
    @logging.release_info_with_gates(gates.logging),
    @codegen_infra.release_info_with_gates(gates.codegen_infra),
    @dst.release_info_with_gates(gates.dst),
    @lsp_server.release_info_with_gates(gates.lsp),
    @mini_compiler.release_info_with_gates(gates.mini_compiler),
    @actor.release_info_with_gates(gates.actor),
  ]
}

///|
/// 整体发布就绪聚合判定（纯函数）。
///
/// 当且仅当给定清单**非空**且其中每个方向都 `release_ready` 时返回 `true`
/// （Requirement 11.6：任一方向门禁未全绿即整体不就绪）。空清单视为未就绪，
/// 以防「无任何方向」被误判为就绪。
pub fn suite_release_ready(
  directions : Array[@release_meta.DirectionRelease],
) -> Bool {
  if directions.is_empty() {
    return false
  }
  for d in directions {
    if not(d.release_ready) {
      return false
    }
  }
  true
}

///|
/// 聚合全部 10 个方向，产出整体发布就绪报告（任务 18.1 的聚合点）。
///
/// 流程：按各方向质量门禁三要素收集 `DirectionRelease` 清单 → 全方向逻辑
/// 合取得出整体 `release_ready`。返回的报告既含整体判定，也含各方向清单，
/// 供 CI 聚合检查输出与属性测试穷举验证。
pub fn aggregate_suite(gates : SuiteGates) -> SuiteReleaseReport {
  let directions = collect_direction_releases(gates)
  { directions, release_ready: suite_release_ready(directions) }
}
