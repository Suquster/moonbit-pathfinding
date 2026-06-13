# Changelog —— Codegen_Infra（方向三）

本文件记录 **Codegen_Infra** 方向（子包 `src/codegen_infra`）作为
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

旗舰深化（业界顶尖档位）：在 `0.1.0` 骨架之上做**严格向后兼容**的增量深化，
对标 LLVM / GCC / Cranelift / regalloc2 的寄存器分配 / SSA / 指令选择模型。
既有公开类型与六个既有函数（`allocate_coloring` / `allocate_linear_scan` /
`interference_components` / `build_ssa` / `run_passes` / `select`）签名、字段、
变体与运行时行为一律冻结；`Pass` 枚举不扩容；全部新能力以新增 `.mbt` 文件旁路
扩展。17 条正确性属性（Property 1–17）各 ≥100 迭代，三后端（wasm-gc / js /
native）一致、零回归。

### Added
- 活跃性分析（`liveness.mbt`）：`analyze_liveness`（后向数据流不动点）、
  `build_interference_from_liveness`、`build_intervals_from_liveness`，使干涉图
  与活跃区间来自真实活跃性（Appel 经典后向数据流；P6 活跃性不动点）。
- 支配树与支配边界（`dominator.mbt`）：`build_dom_tree`（Lengauer-Tarjan
  1979）、`dominance_frontier`（Cytron et al. 1991）、`DomTree::dominates`，
  不可达块排除（P7 支配树正确、P8 支配边界正确）。
- 最小 SSA 构造（`ssa_min.mbt`）：`build_ssa_minimal`（Cytron 迭代支配边界 φ
  放置 + 支配树前序重命名），最小文法上与冻结 `build_ssa` 逐字段一致
  （P9 φ 仅在支配边界、P10 φ 实参数=前驱数、P11 单赋值不变量）。
- SSA 析构（`out_of_ssa.mbt`）：`destruct_ssa`（φ→边上并行复制）、
  `sequentialize_parallel_copy`（破环序列化，Sreedhar / Boissinot）
  （P12 out-of-SSA 与 SSA 语义等价，以参考解释器为 oracle）。
- 稀疏条件常量传播（`sccp.mbt`）：`LatticeValue` 格 + `sccp`（Wegman-Zadeck
  1991，格值 × 边可达性工作表迭代）（P13 SCCP 保持语义）。
- 全局值编号（`gvn.mbt`）：`gvn`（支配性约束值编号合并）、`dce_strong`、
  `copy_prop_strong`（P14 GVN 保持语义）。
- pass 框架（`pipeline.mbt`）：`OptPass` 枚举 + `run_pipeline` / `run_to_fixpoint`
  不动点驱动（旁路超集，既有 `run_passes` 冻结）（P15 保持 SSA 不变量）。
- Chaitin-Briggs 乐观着色（`coloring.mbt`）：`allocate_coloring_briggs`
  （simplify / potential-spill / select 三阶段 + 实际溢出回退）、`SpillCost` /
  `spill_cost` 溢出代价启发式（Chaitin 1982 / Briggs 1994）
  （P1 着色尊重干涉、P2 k 充足无溢出）。
- 寄存器合并（`coalescing.mbt`）：`MoveSet`、`CoalesceStrategy`、
  `can_coalesce_george` / `can_coalesce_briggs` / `coalesce`（George-Appel /
  Briggs 保守判据）（P3 保守合并安全）。
- 线性扫描一致性桥（`consistency.mbt`）：`interference_from_intervals`、
  `allocation_has_spill`（P4 线性扫描尊重重叠、P5 与图着色无溢出一致）。
- BURS 指令选择（`burs.mbt`）：`CostRule`、`select_burs`（自底向上 DP 代价最优
  tiling）、`tiling_cost`、`max_munch`（Appel / BURS）（P16 覆盖完整、
  P17 代价最优，以穷举 tiling 为 oracle）。
- 参考解释器（`evaluate.mbt`）：`EvalResult`、`evaluate`，作为语义保持类属性
  （P12 / P13 / P14）的 oracle。
- 端到端示例（`demo.mbt`）：`demo_program` / `demo_pipeline` / `PipelineStages`，
  贯穿活跃性 → 最小 SSA → SCCP/GVN/DCE → 图着色 / 线性扫描 → BURS 全链路。
- 性能基准（`benches/codegen_bench/`）：支配树 / SSA / 图着色 / 线性扫描 / SCCP
  五类规模化工作负载 + 平滑回归守卫。
- 可执行文档：`README.mbt.md` 扩充全链路示例、paper-to-code 追溯与
  LLVM / GCC / Cranelift / regalloc2 对标及实现边界声明。

### Changed
- `release.mbt`：`codegen_infra_version` 自 `0.1.0` 推进至 `0.2.0`
  （`release_info` / `release_info_with_gates` 语义不变）。

### Compatibility
- 严格向后兼容：既有公开 API 签名 / 行为冻结，`Pass` 枚举不扩容，新能力旁路
  新增；连通分量分解仍复用 `@directed.tarjan_scc`。新增 API 枚举 `OptPass` /
  `CoalesceStrategy` / `LatticeValue` 以 `pub(all)` 暴露以便调用方构造与匹配。

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ 寄存器分配干涉不变量与 SSA 单赋值不变量属性测试 + 可执行文档」的
方向骨架基线。代码生成基础设施聚焦寄存器分配（图着色 + 线性扫描）、SSA
（支配关系汇合 + φ 插入 + 不变量保持）与指令选择（isel DSL）。

### Added
- 核心类型：`Var`（虚拟寄存器标识）、`Location`（`Reg` / `Spill`）、
  `InterferenceGraph`（`nodes` + 无向干涉边 `edges`）、`LiveInterval`
  （线性扫描输入）、`BasicBlock` / `Phi` / `SsaProgram`（SSA 构造单元）、
  `Pass`（`ConstFold` / `DeadCodeElim` / `CopyProp`）、`IselRule` /
  `IrNode` / `TargetInstr`（指令选择 DSL），类型签名严格对齐设计文档
  （新增代码生成核心类型）。
- 复用图着色接缝：`interference_components` 复用 `@directed.tarjan_scc`
  在对称邻接下把干涉图分解为连通分量，将图着色化归为对各分量独立着色的
  子问题（复用既有图算法资产，不重写已被证明谓词覆盖的图算法）。
- 寄存器分配：`allocate_coloring`（基于连通分量分组的贪心 k 着色 + 溢出，
  保证相邻变量不共享寄存器）与 `allocate_linear_scan`（Poletto-Sarnak
  线性扫描：过期回收 + 终点最远者溢出），输出均确定性排序
  （新增图着色与线性扫描寄存器分配）。
- SSA 构造：`build_ssa` 预扫描为每个定义分配全局唯一版本号（单赋值
  不变量），对 ≥2 前驱的汇合块插入 φ 函数，并线性扫描重命名定义左值与
  右值使用为带版本记号 `name#ver`（新增 SSA 构造与 φ 插入）。
- Pass 流水线：`run_passes` 按声明顺序执行常量折叠 / 死代码消除 /
  复制传播，各 pass 仅删除定义或改写右值、绝不引入重复定义，逐 pass
  保持 SSA 单赋值不变量（新增 SSA pass 流水线）。
- 指令选择：`select` 以声明式 `IselRule`（`pattern → template`）后序覆盖
  IR 树为目标指令序列，支持 `BinOp:<op>` 特化优先于通用 `BinOp`
  （新增指令选择 DSL）。
- 属性测试：寄存器分配干涉不变量与 SSA 单赋值不变量（建立与保持）性质，
  跨三后端一致（新增代码生成属性测试）。
- 可执行文档：展示干涉图着色分配与 SSA 构造的 `*.mbt.md` 端到端样例
  （新增代码生成可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/codegen_infra/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/codegen_infra-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/codegen_infra-v0.1.0...codegen_infra-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/codegen_infra-v0.1.0
