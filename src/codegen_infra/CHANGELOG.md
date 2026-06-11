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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/codegen_infra-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/codegen_infra-v0.1.0
