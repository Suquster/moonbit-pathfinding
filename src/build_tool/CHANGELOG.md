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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/build_tool-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/build_tool-v0.1.0
