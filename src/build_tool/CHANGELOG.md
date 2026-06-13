# Changelog —— Build_Tool（方向六）

本文件记录 **Build_Tool** 方向（子包 `src/build_tool`）作为
**独立发布单元**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`）。

---

## [Unreleased]

## [0.2.0] - 2026-06-12

旗舰深化（🟣 档位 3「业界顶尖」）：在 `0.1.0` 骨架之上做**增量、严格向后兼容**的
深化，对标 GNU Make / Ninja / Bazel / Buck2 的调度 / 缓存 / 可复现模型。既有公开
契约（`Target` / `BuildGraph` / `BuildCache` / `ParseError` / `Cycle` 与
`parse_rules` / `detect_cycle` / `topo_order` / `is_dirty` / `schedule`）签名与
语义**全部冻结**，全部新能力以新增 `.mbt` 文件旁路扩展；`ParseError` 不扩容，
列号诊断由新增 `GrammarError` 旁路承载并经 `to_legacy` 投影回退。

### Added
- 完整规则文法（`rule_grammar.mbt`）：`parse_rules_full` /
  `parse_rules_full_with_includes` 构建于 `@parser_combinator`，覆盖目标 + 依赖、
  缩进 recipe 原文、`name = value` 变量定义与 `$(name)` 展开、模式规则 `%` 词干
  回填、`.PHONY`、`include` 合并、`#` 注释与空行；富模型 `RuleSet` / `Rule` /
  `PatternRule` / `Recipe` 与列号级诊断 `GrammarError`（携带
  `@parser_combinator.Pos`），`to_legacy` 投影回 `ParseError`，`to_graph` 向后
  兼容桥，`print_rules` 规范打印（解析 round-trip）（新增完整规则文法解析）。
- 内容寻址增量缓存与持久化（`cache.mbt`）：`content_hash`（FNV-1a 64 位）、
  `action_fingerprint`、`cache_key`（长度前缀单射编码）、`ActionCache` 动作缓存、
  `needs_rebuild_by_key`、`serialize_cache` / `deserialize_cache`（键升序确定性
  行式格式）与 `cache_eq`（新增内容寻址缓存与持久化）。
- 脏传播与最小重建集（`rebuild.mbt`）：`dirty_targets`、`propagate_dirty`（前向
  可达闭包）、`minimal_rebuild_set`（充分且最小）、`rebuild_schedule`（重建集导出
  子图调度）（新增脏传播与最小重建集）。
- 并行调度增强（`scheduler.mbt`）：`critical_path_length`（拓扑序 DP 最长路径）与
  `min_layers`，既有 `schedule` 冻结复用（新增关键路径分析）。
- 动态依赖（`dynamic.mbt`）：`add_dynamic_deps`（不可变追加）与
  `reschedule_with_dynamic`（保持无环并复用 `detect_cycle` / `schedule`）
  （新增动态依赖发现与重新调度）。
- 可复现与 provenance（`provenance.mbt`）：`Provenance`、`derive_output_hash`
  （长度前缀单射）、`record_provenance`（输入哈希规范升序）（新增可复现溯源）。
- 旗舰端到端示例（`demo.mbt`）：多模块 C / MoonBit 工程 `demo_rules` / `demo_graph`
  （新增端到端实战示例）。
- 性能基准（`benches/build_tool_bench`）：链 / 扇出 / 分层网格 DAG 上对拓扑排序 /
  并行调度 / 脏检查 / 最小重建集计时，附确定性回归 guard（新增构建基准与回归
  guard）。
- 属性测试：P1–P15（规则解析 round-trip、最小文法向后兼容、缓存键确定且内容敏感、
  缓存往返、最小重建集充分性 / 最小性、增量空操作幂等、调度尊重依赖 / 批内独立 /
  确定性 / 并行度约束、关键路径等于最小批次层数、环检测可靠性、动态依赖拓扑保持、
  可复现性与溯源确定），各 ≥100 迭代，复用 `@infra_pbt`，三后端一致（新增 15 条
  正确性属性测试）。
- 可执行文档：`README.mbt.md` 扩充完整规则文法 / 内容寻址缓存 / 最小重建集 / 关键
  路径调度 / 端到端 demo 的可运行示例，并补 paper-to-code 追溯与 Make / Ninja /
  Bazel / Buck2 对标及实现边界声明（扩充可执行文档）。

### Changed
- 版本自 `0.1.0` 推进至 `0.2.0`（向后兼容的次版本新增）。
- `release.mbt` 仅更新 `build_tool_version` 字符串，`release_info` /
  `release_info_with_gates` 语义不变。

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ 构建图环检测/拓扑调度不变量与增量幂等属性测试 + 可执行文档」的
方向骨架基线。

### Added
- 核心类型：`Target`、`BuildGraph`（`nodes` + 依赖边 `edges`）、`BuildCache`
  （mtime + 内容哈希双指纹）、`ParseError`（带行号）、`Cycle`（环节点序列），
  并提供 `Target::new` / `BuildGraph::new` / `BuildCache::new` /
  `BuildCache::observe` / `BuildCache::mark_built` 等基础 API
  （新增构建图核心类型与构建缓存）。
- 规则解析：`parse_rules` 解析「`target : dep1 dep2`」最小规则文法为构建图
  （节点按首次出现去重保序、依赖边 `(dep, target)`），非法行返回带 1 起始
  行号的 `ParseError`（新增构建规则解析器）。
- 环检测与拓扑序：`detect_cycle` 复用 `@directed.tarjan_scc`
  （`condensation` 底层）识别强连通分量与自环；`topo_order` 复用
  `@directed.topological_sort`（Kahn 拓扑序），存在环时返回含具体环节点
  序列的 `Cycle`（复用既有图资产，不重写已被证明谓词覆盖的图算法）。
- 并行调度：`schedule` 按拓扑分层产出「无相互依赖目标」的并行批次，并以
  并行度 `jobs` 约束批内宽度（新增拓扑分层并行批次调度）。
- 增量脏检查：`is_dirty` 基于 mtime 与内容哈希比对当前指纹与基线指纹，
  支撑「输入未变 → 零重建」的增量空操作（新增 mtime + 哈希增量脏检查）。
- 属性测试：构建调度拓扑不变量、构建图环检测错误条件与增量构建幂等
  （空操作）性质，跨三后端一致（新增构建调度与增量幂等属性测试）。
- 可执行文档：展示构建图解析与拓扑调度的 `*.mbt.md` 端到端样例
  （新增构建工具可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/build_tool/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/build_tool-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/build_tool-v0.1.0...build_tool-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/build_tool-v0.1.0
