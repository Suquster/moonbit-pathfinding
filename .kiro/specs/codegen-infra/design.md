# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 `codegen_infra 0.1.0` 骨架之上，做**增量式、严格向后兼容**的旗舰级深化，目标对标 LLVM、GCC、Cranelift 与 regalloc2 的寄存器分配 / SSA / 指令选择模型。核心原则一句话：**既有公开类型与函数（`Var`/`Location`/`InterferenceGraph`/`LiveInterval`/`BasicBlock`/`Phi`/`SsaProgram`/`Pass`/`IselRule`/`IrNode`/`TargetInstr` 与 `allocate_coloring`/`allocate_linear_scan`/`interference_components`/`build_ssa`/`run_passes`/`select`）的签名、字段、变体与运行时行为一律冻结，所有新能力以旁路扩展（新增文件、新增类型、新增函数）的方式提供，绝不改写既有语义（R15）。**

### 实现边界声明（Scope Boundary）

Codegen_Infra 是编译器后端的**算法与中间表示模型层**，停留在「控制流图、活跃性、支配关系、SSA、数据流优化、寄存器分配、指令选择」这一抽象层：

- **不**生成真实目标机器码、**不**汇编或链接、**不**绑定任何具体指令集架构（ISA）；
- IR 为简化的教学/研究模型——块内指令是以空格分隔的记号串（`name = a op b` / `ret x` / `br L` / `cbr c L1 L2`），`IrNode` 是 `Const/VarRef/BinOp` 树；
- 目标指令以不透明 `TargetInstr{ op, operands }` 建模，`op` 是字符串操作码，不解释为真实助记符。

该边界是刻意取舍：它使核心算法（着色、支配、SSA、SCCP/GVN、tiling）可被属性测试穷尽校验，并在 `wasm-gc`/`js`/`native` 三后端行为逐位一致（R14.4）。

### 既有与旗舰流水线

既有骨架已建立一条「够用」的最小流水线（全部冻结）：

```
InterferenceGraph ─ allocate_coloring/allocate_linear_scan ─▶ Map[Var, Location]
Array[BasicBlock] ─ build_ssa ─▶ SsaProgram ─ run_passes ─▶ SsaProgram
IrNode ─ select(rules) ─▶ Array[TargetInstr]
```

旗舰深化在其旁侧新增一条**真实来源、功能完备**的后端流水线，并以参考解释器 `evaluate` 作为语义保持类属性的 oracle：

```
Array[BasicBlock]
   │
   ├─ analyze_liveness ─▶ LivenessResult ──┬─ build_interference_from_liveness ─▶ InterferenceGraph
   │   （后向不动点）                        └─ build_intervals_from_liveness  ─▶ Array[LiveInterval]
   │
   ├─ build_dom_tree(LT) ─▶ DomTree ─ dominance_frontier ─▶ Map[Block, DF]
   │                                        │
   │                                        ▼
   ├─ build_ssa_minimal（Cytron 支配边界 φ） ─▶ SsaProgram ─┐
   │      （在最小文法上与冻结 build_ssa 一致：R6.4）         │
   │                                                        ▼
   │                              run_pipeline / run_to_fixpoint（OptPass：SCCP/GVN/DCE/CopyProp/ConstFold，不动点）
   │                                                        │
   │                                                        ▼
   │                                            destruct_ssa（φ→并行复制→破环序列化）─▶ 无 φ 程序
   │
   ├─ allocate_coloring_briggs（Chaitin-Briggs 乐观着色 + 溢出代价 + George/Briggs 合并）
   │       与 allocate_linear_scan 在无溢出场景结论一致（R3.5）           ─▶ Map[Var, Location]
   │
   └─ select_burs（BURS 代价最优 tiling / 最大吞噬）                       ─▶ Array[TargetInstr]
```

旗舰能力分十二条主线落地：① Chaitin-Briggs 乐观着色；② 溢出代价启发式与 George/Briggs 保守合并；③ 线性扫描与着色一致性；④ 活跃性分析；⑤ Lengauer-Tarjan 支配树与支配边界；⑥ Cytron 最小 SSA；⑦ out-of-SSA；⑧ SCCP；⑨ GVN + 强化 DCE/复制传播；⑩ pass 框架（不动点）；⑪ BURS/最大吞噬指令选择；⑫ 端到端 demo + 基准 + 对标。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、三后端一致性策略、错误处理与正确性属性。

---

## 架构（Architecture）

### 设计原则与向后兼容契约

1. **冻结即契约**：`codegen_infra.mbt` 与 `release.mbt` 中现有的 `pub`/`pub(all)` 声明，其签名、字段、变体与运行时行为一律不改；`pkg.generated.mbti` 现有条目稳定，新增条目仅追加（R15.1/15.2/15.5）。
2. **旁路扩展**：旗舰能力全部为新增文件中的新增 API（`analyze_liveness`/`build_dom_tree`/`build_ssa_minimal`/`destruct_ssa`/`sccp`/`gvn`/`run_pipeline`/`allocate_coloring_briggs`/`coalesce_*`/`select_burs` 等），新增方法只增不改既有类型。
3. **枚举不扩容**：`Pass` 是 `pub(all) enum`（`ConstFold/DeadCodeElim/CopyProp`），新增变体会改变其形态，故**不扩容 `Pass`**。新优化遍（SCCP/GVN）通过**新增 `OptPass` 枚举 + 新驱动 `run_pipeline`/`run_to_fixpoint`** 提供；既有 `run_passes(SsaProgram, Array[Pass])` 行为冻结（R10.4、R15.5）。这是「同一程序、两套驱动、互不干扰」的关键取舍。
4. **复用既有图资产**：`interference_components` 继续复用 `@directed.tarjan_scc`（连通分量分组）；旗舰着色构建于该分组之上，不重写已被覆盖的图算法（R15.3）。
5. **infra 复用**：全部新增属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`（每条 ≥100 迭代，R16.2）；发布元数据复用 `@release_meta`，`release_info`/`release_info_with_gates` 语义不变（R16.5/16.6）。
6. **同包私有复用**：新增文件与既有 `codegen_infra.mbt` 同属包 `codegen_infra`，故可直接复用包内私有辅助（`tokenize`/`join_tokens`/`versioned`/`version_id`/`parse_int`/`rename_use` 等），无需复制指令记号解析逻辑。

### 模块 / 文件划分

下表为 `src/codegen_infra/` 下的文件规划。**既有文件**保持冻结，仅可追加新方法所需的内部 import；**新增文件**承载旗舰能力（与 `moon.pkg` 注释中声明的 reg_alloc / ssa / isel 三模块对应）。

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `codegen_infra.mbt` | 冻结 | 既有核心类型 + `allocate_coloring`/`allocate_linear_scan`/`interference_components`/`build_ssa`/`run_passes`/`select` 及私有辅助 | R15.1/15.2 |
| `release.mbt` | 冻结 | 既有发布元数据登记（`release_info`/`release_info_with_gates`） | R16.5/16.6 |
| `liveness.mbt` | 新增 | `LivenessResult`、`analyze_liveness`（后向不动点）、`build_interference_from_liveness`、`build_intervals_from_liveness`、`use_def` 提取 | R4 |
| `dominator.mbt` | 新增 | `DomTree`、`build_dom_tree`（Lengauer-Tarjan）、`dominance_frontier`、`DomTree::dominates`、不可达排除 | R5 |
| `ssa_min.mbt` | 新增 | `build_ssa_minimal`（Cytron 支配边界 φ 放置 + 支配树驱动重命名），最小文法与冻结 `build_ssa` 一致 | R6 |
| `out_of_ssa.mbt` | 新增 | `destruct_ssa`（φ→并行复制）、`sequentialize_parallel_copy`（破环序列化） | R7 |
| `sccp.mbt` | 新增 | `LatticeValue`、`sccp`（格值 × 边可达性工作表迭代） | R8 |
| `gvn.mbt` | 新增 | `gvn`（值编号）、`dce_strong`、`copy_prop_strong` | R9 |
| `pipeline.mbt` | 新增 | `OptPass`、`run_pipeline`（按序）、`run_to_fixpoint`（不动点收敛） | R10 |
| `coloring.mbt` | 新增 | `allocate_coloring_briggs`（simplify/potential-spill/select 三阶段栈式乐观着色 + 实际溢出回退）、`SpillCost`、`spill_cost` | R1/R2.1 |
| `coalescing.mbt` | 新增 | `MoveSet`、`can_coalesce_george`/`can_coalesce_briggs`、`coalesce`（保守合并） | R2 |
| `burs.mbt` | 新增 | `CostRule`、`select_burs`（自底向上 DP 代价最优 tiling）、`tiling_cost`、`max_munch` | R11 |
| `evaluate.mbt` | 新增 | 参考解释器 `evaluate`（SSA/非 SSA 程序 × 初始赋值 × 控制流路径 → 变量取值），作为语义保持属性 oracle | R7.5/R8.5/R9.5 |
| `demo.mbt` | 新增 | 旗舰端到端示例：`demo_program`、`demo_pipeline`（贯穿文档与基准） | R12 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖升级后全链路 | R16.3 |
| `CHANGELOG.md` | 扩充 | SemVer 推进记录 | R16.5 |
| `prop_*_test.mbt` / `prop_*_wbtest.mbt` | 新增/既有 | 属性测试（见「测试策略」「正确性属性」） | R16.2 |

`benches/` 下新增基准包 `benches/codegen_bench/`（`codegen_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`），结构对齐既有 `benches/astar_bench` 等，覆盖支配树构造 / SSA 构造 / 图着色 / 线性扫描 / SCCP 五类工作负载，产出 `benches/results/` 工件并接入 guard（R13）。

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt`/`.mbti` 风格（`pub(all)` 暴露可构造数据，`pub` 暴露只读结构与函数）。所有签名为新增，既有签名一律不变。

### 4.1 活跃性分析（liveness.mbt，R4）

骨架的 `InterferenceGraph` 与 `LiveInterval` 此前需人工构造；旗舰让它们来自真实活跃性。指令的 use/def 由块内记号串解析：`name = rhs...` 定义 `name`、右值记号中的变量为 use；`ret x` / `br L` / `cbr c L1 L2` 仅含 use。

```moonbit
// liveness.mbt
pub(all) struct LivenessResult {
  live_in : Map[String, Array[Var]]    // 块 label → live-in 变量集（去重、按 id 升序）
  live_out : Map[String, Array[Var]]   // 块 label → live-out 变量集
} derive(Show)

pub fn analyze_liveness(blocks : Array[BasicBlock]) -> LivenessResult

// 由活跃性结果在「同一程序点同时活跃」的变量对之间建边（R4.3）
pub fn build_interference_from_liveness(
  blocks : Array[BasicBlock], live : LivenessResult,
) -> InterferenceGraph

// 由活跃性结果构造覆盖「首次定义→最后一次活跃使用」线性序号的区间（R4.4）
pub fn build_intervals_from_liveness(
  blocks : Array[BasicBlock], live : LivenessResult,
) -> Array[LiveInterval]
```

算法（R4.1/4.2）：后向数据流不动点迭代。初始 `live_in = live_out = ∅`；对每个块以传递方程 `live_out(b) = ⋃_{s∈succ(b)} live_in(s)`、`live_in(b) = use(b) ∪ (live_out(b) \ def(b))` 反复更新，直至一轮内所有块集合不变（worklist 或逆后序轮询，均收敛于唯一最小不动点）。集合以排序数组规范化，保证三后端确定性。

### 4.2 支配树与支配边界（dominator.mbt，R5）

```moonbit
// dominator.mbt
pub(all) struct DomTree {
  root : String                          // 唯一入口
  idom : Map[String, String]             // 可达非入口节点 → 直接支配者（入口不在键集）
  children : Map[String, Array[String]]  // idom 反向：支配树父→子
  reachable : Array[String]              // 从入口可达的块（确定性顺序）
} derive(Show)

pub fn build_dom_tree(blocks : Array[BasicBlock], entry~ : String) -> DomTree
pub fn dominance_frontier(
  blocks : Array[BasicBlock], dom : DomTree,
) -> Map[String, Array[String]]          // 块 → 其支配边界块集
pub fn DomTree::dominates(self : DomTree, a : String, b : String) -> Bool  // a 是否支配 b
```

算法：`build_dom_tree` 实现 Lengauer-Tarjan（DFS 编号 → 半支配者 semidominator → 经带路径压缩的 forest 求 idom）；不可达块不参与 DFS，从而被排除出支配树（R5.4）。`dominance_frontier` 采用 Cytron et al. 的 DF 计算：对每个有 ≥2 前驱的汇合块 `n`，对其每个前驱 `p`，自 `p` 沿 idom 链上溯至 `idom(n)`（不含），途中每个节点的 DF 加入 `n`（R5.3）。`dominates` 经 idom 父链上溯判定。除入口外每个可达节点恰有一个 idom（R5.2）。

### 4.3 最小 SSA 构造（ssa_min.mbt，R6）

```moonbit
// ssa_min.mbt
pub fn build_ssa_minimal(blocks : Array[BasicBlock], entry~ : String) -> SsaProgram
```

算法（Cytron et al. 1991）：① 计算 `DomTree` 与（迭代）支配边界；② **φ 放置**——对每个变量，在其定义块集合的迭代支配边界处放置 φ，φ 实参数等于该汇合块前驱数（R6.1/6.2/6.5）；③ **重命名**——沿支配树前序遍历，为每个定义分配带版本号的唯一变量、将每个使用重写为支配路径上最近定义版本，进入汇合块时以该块 φ 目标作当前版本（R6.3）。

向后兼容（R6.4）：对既有最小文法输入（直线代码、简单菱形），`build_ssa_minimal` 在 φ 数量、版本化文本 `name#ver` 与块结构上与冻结 `build_ssa` 一致——通过共享版本记号格式（`versioned`）与一致的汇合块处理实现。既有 `build_ssa` 本身不改（R15.2）。

### 4.4 SSA 析构 / out-of-SSA（out_of_ssa.mbt，R7）

```moonbit
// out_of_ssa.mbt
// 析构 SSA：消除全部 φ，产出不含 φ 的等价程序（R7.4）
pub fn destruct_ssa(p : SsaProgram) -> SsaProgram

// 把一组并行复制 [(dst, src)] 序列化为保持并行语义的串行复制序列；
// 存在复制环时引入临时变量打破（R7.2/7.3）
pub fn sequentialize_parallel_copy(copies : Array[(Var, Var)]) -> Array[(Var, Var)]
```

算法：对每个 φ `dest = φ(a_1, …, a_p)`，在第 `i` 个前驱到汇合块的边上插入复制 `dest ← a_i`（R7.1）。同一边上的多个 φ 形成一组**并行复制**，以「就绪节点优先 + 环检测引入临时」的序列化（经典 out-of-SSA 破环法）转为串行：先发射所有目标不再被其他复制用作源的复制；当仅剩环（如 `a←b, b←a`）时引入临时 `t←a`，将环中一条复制改为读 `t`，从而保持并行语义（R7.2/7.3）。析构后 `phis` 为空（R7.4）。

### 4.5 稀疏条件常量传播 / SCCP（sccp.mbt，R8）

```moonbit
// sccp.mbt
pub enum LatticeValue {
  Top            // 未定（尚未证明非常量）
  Const(Int)     // 已知常量
  Bottom         // 不确定（over-defined）
} derive(Eq, Show)

pub fn sccp(p : SsaProgram) -> SsaProgram
```

算法（Wegman-Zadeck）：联合维护两个工作表——SSA 变量格值（`Top → Const → Bottom` 单调下降）与 CFG 边可达性。从入口可达边出发迭代：对可达块求值指令更新变量格值，对常量条件分支仅将选定后继边标记可达、另一边标记不可达（R8.1/8.3）。不动点处，常量变量的全部使用替换为常量字面量（R8.2）。变换仅折叠/替换、不引入重复定义，故保持 SSA 单赋值不变量（R8.4）。

### 4.6 全局值编号与强化 DCE / 复制传播（gvn.mbt，R9）

```moonbit
// gvn.mbt
pub fn gvn(p : SsaProgram) -> SsaProgram            // 等价表达式同值编号 + 复用先前结果
pub fn dce_strong(p : SsaProgram) -> SsaProgram     // 删除无活跃使用且无副作用的定义
pub fn copy_prop_strong(p : SsaProgram) -> SsaProgram  // 复制目标使用替换为源
```

算法：`gvn` 为「相同操作符 + 相同值编号操作数」的表达式赋同一值编号（哈希值编号表），后继冗余计算替换为对先前等价结果的引用（R9.1）；`dce_strong` 以「被使用版本」可达性删除死定义（含 φ 实参用法，R9.2）；`copy_prop_strong` 把对单记号复制目标的使用（含 φ 实参）替换为源并删除复制（R9.3）。三者均仅删除/改写、不重复定义，保持单赋值不变量（R9.4）。

### 4.7 pass 框架 —— 不动点驱动（pipeline.mbt，R10）

`Pass` 枚举冻结，故新优化遍经新增 `OptPass` 与新驱动提供（R15.5）：

```moonbit
// pipeline.mbt
pub enum OptPass {
  ConstFold
  DeadCodeElim
  CopyProp
  Sccp
  Gvn
} derive(Eq, Show)

pub fn run_pipeline(p : SsaProgram, passes : Array[OptPass]) -> SsaProgram          // 按声明顺序施加一遍
pub fn run_to_fixpoint(p : SsaProgram, passes : Array[OptPass], max_iters~ : Int = 64) -> SsaProgram  // 反复施加直到一轮内不变或达上界
```

`run_pipeline` 按声明顺序依次施加各 `OptPass`（`ConstFold/DeadCodeElim/CopyProp` 委托既有实现，`Sccp/Gvn` 委托 §4.5/4.6，R10.1）；`run_to_fixpoint` 以「程序在一轮内不再变化」为收敛判据反复施加，`max_iters` 为安全上界保证终止（R10.2）。每个 pass 后保持单赋值不变量（R10.3/10.5）。**既有 `run_passes(SsaProgram, Array[Pass])` 行为完全冻结**（R10.4），旗舰驱动是其旁路超集。

### 4.8 Chaitin-Briggs 乐观着色与溢出代价（coloring.mbt，R1/R2.1）

```moonbit
// coloring.mbt
pub(all) struct SpillCost {
  cost : Map[Var, Double]   // 变量 → 溢出代价度量（使用频度 / 活跃区间长度）
} derive(Show)

// 由使用频度与区间长度估算溢出代价（频度高、区间短 → 代价高，越不该被溢出）
pub fn spill_cost(g : InterferenceGraph, intervals : Array[LiveInterval]) -> SpillCost

// Chaitin-Briggs 三阶段栈式乐观着色 + 实际溢出回退（R1.1/1.2）
pub fn allocate_coloring_briggs(
  g : InterferenceGraph, k : Int, cost~ : SpillCost = SpillCost::uniform(),
) -> Map[Var, Location]
```

算法（Chaitin 1982 / Briggs 1994）三阶段：
- **simplify**：反复移除度 `< k` 的节点并压入选择栈（移除后邻居度下降，可能触发更多移除）；
- **potential-spill**：无可移除低度节点时，按 `spill_cost` 选**代价最低**的度 `≥ k` 节点乐观入栈并标记潜在溢出（R2.1）；
- **select**：按入栈逆序出栈，为每个节点回填未被其已着色邻居占用的**最小**寄存器 `[0,k)`；潜在溢出节点若无可用寄存器则实际溢出为 `Spill`（R1.2）。

为每个待分配变量产出恰一个 `Location` 且覆盖全部节点（R1.4）；任意干涉边两端若都为 `Reg` 则编号不同（R1.5）；`k ≥ 最大度+1` 时无溢出（R1.3/1.6）。既有 `allocate_coloring` 保留为「贪心连通分量着色」基线，不被本函数替换（R15.2）。

### 4.9 寄存器合并 / Coalescing（coalescing.mbt，R2）

```moonbit
// coalescing.mbt
pub(all) struct MoveSet {
  moves : Array[(Var, Var)]   // 传送相关（move/copy）变量对
} derive(Show)

pub fn can_coalesce_george(g : InterferenceGraph, a : Var, b : Var, k : Int) -> Bool
pub fn can_coalesce_briggs(g : InterferenceGraph, a : Var, b : Var, k : Int) -> Bool
// 在保守判据下合并传送相关且互不干涉的变量对，返回合并后的干涉图
pub fn coalesce(
  g : InterferenceGraph, moves : MoveSet, k : Int,
  strategy~ : CoalesceStrategy = George,
) -> InterferenceGraph

pub enum CoalesceStrategy { George; Briggs } derive(Eq, Show)
```

判据：仅当两变量**互不干涉**时才考虑合并（R2.2），存在干涉边即拒绝（R2.4）。**Briggs 保守**：合并后节点的「度 `≥ k` 的邻居数」少于 `k` 才合并；**George 保守**：`a` 的每个邻居要么与 `b` 干涉、要么度 `< k`，才合并（R2.3）。保守判据保证合并不增加着色难度，故合并后再分配仍满足干涉不变量且不引入新溢出（R2.5）。

### 4.10 指令选择升级 —— BURS / 最大吞噬（burs.mbt，R11）

```moonbit
// burs.mbt
pub(all) struct CostRule {
  pattern : String   // "Const" / "VarRef" / "BinOp" / "BinOp:<op>"
  template : String  // 目标操作码
  cost : Int         // 该规则覆盖其匹配节点的代价（≥0）
} derive(Eq, Show)

// BURS：自底向上动态规划求每子树最小代价覆盖，发射总代价最小的指令序列（R11.2/11.6）
pub fn select_burs(rules : Array[CostRule], ir : IrNode) -> Array[TargetInstr]
// 最优 tiling 的总代价（供属性测试与 demo 度量）
pub fn tiling_cost(rules : Array[CostRule], ir : IrNode) -> Int
// 最大吞噬：自顶向下贪心匹配最大可覆盖子树（对照基线）
pub fn max_munch(rules : Array[CostRule], ir : IrNode) -> Array[TargetInstr]
```

算法：`select_burs` 自底向上为每个子树计算「以某规则为根 + 子树最优覆盖」的最小代价 DP 表，回溯发射代价最优指令序列；运算符特化规则 `BinOp:<op>` 优先于通用 `BinOp`（R11.3）；覆盖完整——每个 IR 节点都被某指令覆盖、无未匹配（R11.1/11.5）；所选覆盖总代价不大于任何其他合法覆盖（R11.6）。既有 `select(Array[IselRule], IrNode)` 的后序遍历语义完全冻结（R11.4，与 `select_burs` 互为旁路）。

### 4.11 参考解释器（evaluate.mbt，R7.5/R8.5/R9.5）

语义保持类属性（out-of-SSA、SCCP、GVN）需要可计算的语义 oracle。参考解释器对程序在「给定初始变量赋值 + 选定控制流路径」下求值：

```moonbit
// evaluate.mbt
pub(all) struct EvalResult {
  values : Map[String, Int]   // 程序点（路径末端）各（版本化）变量取值
  output : Array[Int]         // 可达输出序列（ret 记号产出）
} derive(Eq, Show)

// 沿给定块标签路径解释执行程序；phi 按来路前驱选择对应实参版本求值
pub fn evaluate(
  p : SsaProgram, init : Map[String, Int], path : Array[String],
) -> EvalResult
```

`evaluate` 处理 `name = a op b`（整数算术）、`ret x`（产出）、`cbr/br`（控制流，由 `path` 指定实走分支）与 φ（按 `path` 中进入汇合块的前驱选择实参）。它是纯函数、确定性，三后端一致，专用于属性测试比较「变换前后」「SSA 与析构后」在相同 `init`/`path` 下的 `output` 与目标变量取值。

### 4.12 旗舰端到端示例（demo.mbt，R12）

```moonbit
// demo.mbt
pub fn demo_program() -> Array[BasicBlock]              // 带条件分支的小程序（含菱形汇合）
pub(all) struct PipelineStages {
  liveness : LivenessResult
  dom : DomTree
  ssa : SsaProgram
  optimized : SsaProgram
  coloring : Map[Var, Location]
  linear_scan : Map[Var, Location]
  instrs : Array[TargetInstr]
} derive(Show)
pub fn demo_pipeline() -> PipelineStages                // 串起活跃性→SSA→优化→分配→isel 全链路
```

`demo_pipeline` 依次执行活跃性 → 支配边界最小 SSA → SCCP/GVN/DCE → 图着色与线性扫描 → 指令选择，各阶段产出与 README 文档声明一致（R12.2）：仅在支配边界放 φ 且 φ 数符合声明（R12.3）；k 充足时着色无溢出且满足干涉不变量（R12.4）；同一无溢出场景两法溢出结论一致（R12.5）。README 与基准复用同一 `demo_program`。

### 4.13 性能基准设计（benches/codegen_bench/，R13）

基准对五类工作负载在规模化随机 CFG 上计时：支配树构造、SSA 构造、图着色分配、线性扫描分配、SCCP（R13.1）。输出含机器标识、后端目标、图规模（节点数、边数、变量数）与计时统计的 JSON/Markdown 工件（R13.2），写入 `benches/results/`；新运行与基线中位数比较，超声明容差给可审计回归失败报告（R13.3，复用既有 guard 模式）。文档记录可复现运行命令与规模参数，并要求 native 后端先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R13.4/13.5）。

---

## 数据模型（Data Models）

新增类型一览（既有 `Var`/`Location`/`InterferenceGraph`/`LiveInterval`/`BasicBlock`/`Phi`/`SsaProgram`/`Pass`/`IselRule`/`IrNode`/`TargetInstr` 全部不变）：

| 类型 | 文件 | 说明 |
|---|---|---|
| `LivenessResult` | `liveness.mbt` | 各块 live-in / live-out 集 |
| `DomTree` | `dominator.mbt` | 入口、idom 映射、支配树子节点、可达集 |
| `LatticeValue` | `sccp.mbt` | SCCP 格：`Top`/`Const`/`Bottom` |
| `OptPass` | `pipeline.mbt` | 旗舰优化遍枚举（含 Sccp/Gvn） |
| `SpillCost` | `coloring.mbt` | 变量 → 溢出代价度量 |
| `MoveSet` / `CoalesceStrategy` | `coalescing.mbt` | 传送相关对集合与合并策略 |
| `CostRule` | `burs.mbt` | 带代价的指令选择规则 |
| `EvalResult` | `evaluate.mbt` | 参考解释器输出（变量取值 + 输出序列） |
| `PipelineStages` | `demo.mbt` | 端到端各阶段产物 |

**版本记号约定**：旗舰 SSA 复用既有 `name#ver` 版本格式与 `version_id` 解析，保证与冻结 `build_ssa`/`run_passes` 互操作。**发布元数据**：版本自 `0.1.0` 起按本次旗舰深化做次/主版本推进（R16.5），`release_info`/`release_info_with_gates` 语义不变，仅 `codegen_infra_version` 字符串与 CHANGELOG 更新。

---

## 错误处理（Error Handling）

本方向算法层以**全函数**为主——无效或退化输入返回良构默认而非抛异常，保证三后端确定性与属性测试可穷尽：

- **空 / 退化输入**：空 CFG、空区间集、空规则集分别返回空 `LivenessResult` / 空分配 / 空指令序列；`k ≤ 0` 时所有变量溢出（既有 `allocate_linear_scan` 已如此，旗舰着色对齐）。
- **不可达块**：`build_dom_tree` 将其排除出支配树而不计入任何支配关系（R5.4），下游 SSA/优化忽略不可达块。
- **常量折叠溢出 / 非整数**：`evaluate` 与 `sccp` 的算术沿用既有 `fold_op` 语义（仅 `+ - *`），不支持的运算符保持原指令不折叠（与 `Bottom` 处理一致）。
- **isel 未匹配回退**：`select_burs` 在规则集覆盖完整前提下不应有未匹配节点；若某节点类型无规则，回退为以运算符/字面量为操作码的占位指令（与既有 `select` 回退一致），并在覆盖完整属性（P14）中以「规则集覆盖完整」为前置条件。
- **不动点上界**：`run_to_fixpoint` 与各数据流分析设 `max_iters` 安全上界，防止异常输入下不收敛（正常输入下远在上界内收敛）。

---

## 算法说明与 paper-to-code 可追溯（R14）

| 算法 | 论文 / 规范 | 本库落点 |
|---|---|---|
| 图着色寄存器分配 | Chaitin 1982《Register Allocation & Spilling via Graph Coloring》；Briggs 1994 乐观着色 | `allocate_coloring_briggs`（simplify/potential-spill/select 三阶段） |
| 线性扫描分配 | Poletto-Sarnak 1999《Linear Scan Register Allocation》 | 既有 `allocate_linear_scan`（过期回收 + 终点最远者溢出） |
| 寄存器合并 | George-Appel 1996 迭代合并；Briggs 保守判据 | `can_coalesce_george`/`can_coalesce_briggs`/`coalesce` |
| 支配树 | Lengauer-Tarjan 1979《A Fast Algorithm for Finding Dominators》 | `build_dom_tree` |
| 支配边界 + 最小 SSA | Cytron et al. 1991《Efficiently Computing SSA Form and the CFG》 | `dominance_frontier` + `build_ssa_minimal` |
| SSA 析构 | Sreedhar et al. / Boissinot 并行复制破环 | `destruct_ssa` + `sequentialize_parallel_copy` |
| 稀疏条件常量传播 | Wegman-Zadeck 1991《Constant Propagation with Conditional Branches》 | `sccp` |
| 全局值编号 | 值编号 / Appel《Modern Compiler Implementation》 | `gvn` |
| 活跃性分析 | 经典后向数据流不动点；Appel《Modern Compiler Implementation》 | `analyze_liveness` |
| 指令选择 | BURS（自底向上重写）/ 最大吞噬；Appel《Modern Compiler Implementation》 | `select_burs` / `max_munch` |

每个新增文件头部以注释标注其对应论文与本设计章节（沿用既有 `codegen_infra.mbt` 的注释风格），实现 paper-to-code 可追溯（R14.1/14.2）。

---

## 三后端一致性与可移植性（R16.1/16.4）

- **确定性随机源**：全部属性测试复用 `@infra_pbt` 种子驱动 `Rng`，保证 `wasm-gc`/`js`/`native` 三后端逐位一致、可重放，任一后端输出分歧即判构建失败（R16.1）。
- **确定性输出规范化**：活跃性集合、支配关系、分配结果、指令序列均以 `Var.id` / 块标签排序规范化，杜绝 `Map` 遍历序在后端间的差异。
- **可移植实现约束**：算法仅依赖整数、`Double`、数组、`Map` 与字符串记号解析，不使用后端特定 API。
- **native 前置**：文档与脚本要求 native 后端运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R13.4/R16.4）。
- **门禁聚合**：三后端测试、属性测试、可执行文档任一未过，`release_info_with_gates` 经 `@release_meta` 聚合阻止本方向进入 release-ready（R16.6）。

---

## 设计权衡与开源对标（R14.3/14.5）

| 维度 | 本库（Codegen_Infra） | LLVM | GCC | Cranelift | regalloc2 |
|---|---|---|---|---|---|
| 寄存器分配 | 图着色（Chaitin-Briggs）+ 线性扫描，二者并存 | 贪心 + PBQP 可选 | 图着色（IRA）| 偏好引导 + 线性扫描风格 | SSA-based 回填 + 移动优化 |
| 合并 | George / Briggs 保守 | 复制合并 + rematerialization | 合并 + 重materialize | 偏好/约束驱动 | 移动消除 |
| SSA 构造 | Cytron 支配边界最小 φ | 内存到寄存器 + 支配边界 | GIMPLE→SSA | CLIF 即 SSA | 输入即 SSA |
| 指令选择 | BURS 代价最优 / 最大吞噬（模型层）| SelectionDAG / GlobalISel | RTL 模式 | ISLE 模式 | 不涉及 isel |
| 输出层级 | **IR/算法模型层，不产机器码** | 真实机器码 | 真实机器码 | 真实机器码 | 仅分配结果 |

**核心取舍**：本库**停留在算法与 IR 模型层**——以放弃真实机器码生成换取算法可被属性测试穷尽校验、三后端逐位一致与 paper-to-code 透明可追溯。凡与所对标后端的语义差异（如 isel 不产真实助记符、寄存器为抽象编号、不做 rematerialization）均在 README 与本文档显式声明，而非隐式留白（R14.4/14.5）。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 |
|---|---|
| R1 Chaitin-Briggs 乐观着色 | 4.8 `allocate_coloring_briggs` |
| R2 溢出代价 + 合并 | 4.8 `spill_cost`；4.9 `coalesce`/`can_coalesce_*` |
| R3 线性扫描与着色一致 | 既有 `allocate_linear_scan` + 4.8（一致性属性 P5） |
| R4 活跃性分析 | 4.1 `analyze_liveness` 及构造桥 |
| R5 支配树 / 支配边界 | 4.2 `build_dom_tree`/`dominance_frontier` |
| R6 最小 SSA | 4.3 `build_ssa_minimal` |
| R7 out-of-SSA | 4.4 `destruct_ssa`/`sequentialize_parallel_copy`；4.11 oracle |
| R8 SCCP | 4.5 `sccp`；4.11 oracle |
| R9 GVN / DCE / 复制传播 | 4.6 `gvn`/`dce_strong`/`copy_prop_strong`；4.11 oracle |
| R10 pass 框架（不动点）| 4.7 `OptPass`/`run_pipeline`/`run_to_fixpoint` |
| R11 BURS / 最大吞噬 | 4.10 `select_burs`/`tiling_cost`/`max_munch` |
| R12 端到端 demo | 4.12 `demo_program`/`demo_pipeline` |
| R13 基准 | 4.13 `benches/codegen_bench` |
| R14 可解释性 / 对标 | 「算法说明」「设计权衡与对标」 |
| R15 向后兼容 / 复用 | 「设计原则与兼容契约」「模块划分」冻结列 |
| R16 质量门禁 | 「三后端一致性」+ 测试策略 + 正确性属性 |

---

## 测试策略（Testing Strategy）

**双轨测试**：单元测试锁定具体见证、边界与错误条件；属性测试以 `@infra_pbt` 覆盖通用不变量（每条 ≥100 迭代，R16.2）。属性测试与单元测试互补，不设独立测试任务，测试作为实现父任务的子任务。

- **单元测试 / 见证示例**：三阶段着色阶段顺序（R1.1）、k 不足出现 Spill（R1.2/3.2）、溢出代价选中预期节点（R2.1）、George/Briggs 判据布尔（R2.3）、活跃性构造端点（R4.3/4.4）、不可达块排除（R5.4，边界）、重命名见证（R6.3）、swap 环破环（R7.3，边界）、SCCP 恒真/恒假分支（R8.3）、GVN/DCE/复制传播折叠见证（R9.1/9.2/9.3）、pass 顺序与收敛见证（R10.1/10.2）、isel 特化优先（R11.3）、demo 各阶段快照（R12.2–12.5）、guard 比较与门禁聚合纯函数（R13.3/R16.6）、既有 API 回归（R6.4/R10.4/R11.4/R15.2）。
- **属性测试**：见下「正确性属性」P1–P17，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`（语义等价类经参考解释器 `evaluate` 作 oracle；代价最优经穷举 tiling 暴力 oracle）。生成器包括随机干涉图、随机活跃区间集、带唯一入口的随机 CFG、随机 SSA 程序、随机 IR 树与带代价规则集。
- **可执行文档**：`README.mbt.md` 扩充覆盖升级后图着色、线性扫描、最小 SSA、SSA 析构、SCCP/GVN/DCE、升级后 isel 与端到端 demo，全部经 `moon test *.mbt.md` 验证（R16.3）。
- **属性测试标注**：统一 `Feature: codegen-infra, Property {n}: {text}`，并以 `**Validates: Requirements X.Y**` 链接验收标准。
- **三后端 + native 前置**：同一套件在 `wasm-gc`/`js`/`native` 运行，native 前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`；任一后端分歧即构建失败（R16.1/16.4）。

---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有合法执行下应恒成立行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。下列属性均以全称量化表述，并复用 `@infra_pbt` 的 `holds_for_all`/`round_trip`（每条 ≥100 迭代）。*

### Property 1：着色尊重干涉且分配良构

*对任意*由生成器产出的干涉图与寄存器数 `k`，`allocate_coloring_briggs(g, k)` 的结果以 `Var` 为键恰覆盖图的全部节点、每个变量获得恰一个 `Location`（`Reg` 或 `Spill`），且任意干涉边两端若都被分配为 `Reg` 则其寄存器编号不同。

**Validates: Requirements 1.4, 1.5**

### Property 2：k 充足无溢出

*对任意*由生成器产出的干涉图与不小于其最大度加一的 `k`，`allocate_coloring_briggs(g, k)` 不产生任何 `Spill`，全部节点分配为 `Reg`。

**Validates: Requirements 1.3, 1.6**

### Property 3：保守合并安全性

*对任意*由生成器产出的干涉图、传送相关候选集与 `k`，在保守判据（George 或 Briggs）下执行 `coalesce` 后再分配，仍满足干涉不变量，且溢出数量不大于合并前分配的溢出数量（合并不引入新溢出，且互相干涉的变量对不被合并）。

**Validates: Requirements 2.2, 2.4, 2.5**

### Property 4：线性扫描尊重重叠

*对任意*由生成器产出的活跃区间集合与 `k`，`allocate_linear_scan(intervals, k)` 中任意两个区间重叠的变量若都被分配为 `Reg` 则其寄存器编号不同。

**Validates: Requirements 3.4**

### Property 5：线性扫描与图着色无溢出一致

*对任意*由生成器产出的、最大重叠度不超过 `k` 的活跃区间集合，由其导出的干涉图经图着色与对其本身的线性扫描，二者在「是否需要溢出」的结论上一致——均判定为无需溢出。

**Validates: Requirements 3.3, 3.5**

### Property 6：活跃性不动点正确

*对任意*由生成器产出的控制流图，`analyze_liveness` 的结果为数据流方程的不动点：对每个块再施加一次传递方程（`live_out = ⋃ 后继 live_in`、`live_in = use ∪ (live_out \ def)`）不改变任何块的 `live_in` 与 `live_out`。

**Validates: Requirements 4.1, 4.5**

### Property 7：支配树正确性

*对任意*由生成器产出的带唯一入口的控制流图，`build_dom_tree` 使每个可达非入口节点恰有一个直接支配者；且由 idom 父链推出的支配关系与参考定义「入口到该节点的所有路径均经过支配者」一致。

**Validates: Requirements 5.1, 5.2, 5.5**

### Property 8：支配边界正确性

*对任意*由生成器产出的带唯一入口的控制流图与任意节点对 `(d, n)`，`n` 属于 `dominance_frontier` 中 `d` 的支配边界，当且仅当 `d` 支配 `n` 的某个前驱且 `d` 不严格支配 `n`。

**Validates: Requirements 5.3**

### Property 9：φ 仅放在支配边界

*对任意*由生成器产出的控制流图，`build_ssa_minimal` 产出的每个 φ 所在块都属于其对应变量定义块集合的（迭代）支配边界。

**Validates: Requirements 6.1, 6.5**

### Property 10：φ 结构良构（实参数等于前驱数）

*对任意*由生成器产出的控制流图，`build_ssa_minimal` 产出的每个 φ 的实参个数等于其所在汇合块的前驱个数。

**Validates: Requirements 6.2**

### Property 11：SSA 单赋值不变量

*对任意*由生成器产出的控制流图，`build_ssa_minimal` 的结果满足单赋值不变量：每个版本化变量在全程序至多被定义一次。

**Validates: Requirements 6.6**

### Property 12：out-of-SSA 与 SSA 语义等价

*对任意*由生成器产出的 SSA 程序、给定初始变量赋值与任一控制流路径，沿该路径解释执行 `destruct_ssa` 后的程序所得目标变量取值与可达输出，与按 SSA 语义沿同一路径求值 φ 所得结果一致；且析构后程序不含任何 φ。

**Validates: Requirements 7.1, 7.2, 7.4, 7.5**

### Property 13：SCCP 保持语义

*对任意*由生成器产出的 SSA 程序、给定初始变量赋值与任一控制流路径，`sccp` 变换前后程序在所有可达输出上的解释执行结果一致；且变换后保持 SSA 单赋值不变量。

**Validates: Requirements 8.4, 8.5**

### Property 14：GVN 保持语义

*对任意*由生成器产出的 SSA 程序、给定初始变量赋值与任一控制流路径，`gvn`（含强化 DCE 与复制传播）变换前后程序在所有输出上的解释执行结果一致；且变换后保持 SSA 单赋值不变量。

**Validates: Requirements 9.4, 9.5**

### Property 15：pass 框架保持 SSA 不变量

*对任意*由生成器产出的 SSA 程序与 `OptPass` 序列（含 `ConstFold`/`DeadCodeElim`/`CopyProp`/`Sccp`/`Gvn`），经 `run_pipeline` 或 `run_to_fixpoint` 施加后结果仍满足 SSA 单赋值不变量。

**Validates: Requirements 8.4, 9.4, 10.3, 10.5**

### Property 16：指令选择覆盖完整

*对任意*由生成器产出的 IR 树与覆盖完整的带代价规则集，`select_burs` 所选指令序列覆盖每个 IR 节点，无未匹配节点。

**Validates: Requirements 11.1, 11.5**

### Property 17：指令选择代价最优

*对任意*由生成器产出的 IR 树与覆盖完整的带代价规则集，`select_burs` 所选覆盖方案的总代价（`tiling_cost`）不大于由穷举得到的任何其他合法覆盖方案的总代价。

**Validates: Requirements 11.2, 11.6**
