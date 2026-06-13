# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Codegen_Infra（方向三）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开 API（核心类型 `Var`、`Location`、`InterferenceGraph`、`LiveInterval`、`BasicBlock`、`Phi`、`SsaProgram`、`Pass`、`IselRule`、`IrNode`、`TargetInstr`，以及接口 `allocate_coloring`、`allocate_linear_scan`、`interference_components`、`build_ssa`、`run_passes`、`select`），并在其上扩展为一套对标 LLVM、GCC、Cranelift 与 regalloc2 的寄存器分配 / SSA / 指令选择模型的旗舰级**编译器后端基础设施（代码生成中间层）**库。

本方向**显式声明实现边界**：Codegen_Infra 是编译器后端的**算法与中间表示模型层**，停留在「控制流图、SSA、支配关系、活跃性、数据流优化、寄存器分配、指令选择」这一抽象层，**不**生成真实目标机器码、**不**汇编或链接、**不**绑定具体指令集架构（ISA）。IR 为简化的教学/研究模型（`IrNode` 树与字符串指令），目标指令以不透明 `TargetInstr{ op, operands }` 建模。该边界使核心算法可被属性测试穷尽校验且三后端行为一致。

旗舰目标聚焦九条主线：

- **图着色寄存器分配升级**：Chaitin-Briggs 乐观着色（simplify / potential-spill / select 三阶段栈式着色 + 实际溢出回退）、溢出代价启发式、寄存器合并（coalescing，George / Briggs 保守合并），并始终保持「相邻变量不共享寄存器」的干涉不变量。
- **支配关系与最小 SSA**：Lengauer-Tarjan 支配树、支配边界（dominance frontier）、Cytron et al. 最小 φ 放置（仅在支配边界处放置 φ），以更结构化的 CFG 视图驱动，且保持既有 `build_ssa` 行为兼容。
- **SSA 析构（out-of-SSA）**：将 φ 消除为并行复制（parallel copy）并对复制序列做破环序列化，保证去 SSA 后语义与 SSA 等价。
- **数据流优化**：稀疏条件常量传播（SCCP）、全局值编号（GVN）、SSA 上强化的死代码消除与复制传播；以不动点迭代为框架并保持 SSA 单赋值不变量。
- **活跃性分析**：基于 CFG 的活跃变量数据流分析（liveness），据此构造干涉图与活跃区间，使寄存器分配的输入具有真实来源。
- **指令选择升级**：最大吞噬（maximal munch）与 BURS 带代价的树模式匹配（动态规划最优 tiling），覆盖完整 IR 树并给出代价最优的指令序列。
- **旗舰端到端示例**：一份贯穿文档与基准的小程序，从 CFG → 活跃性 → SSA（支配边界 φ）→ SCCP / GVN / DCE → 图着色 / 线性扫描分配 → 指令选择，演示完整后端流水线。
- **可解释性**：paper-to-code 可追溯（Chaitin 1982 / Briggs 1994 图着色、Poletto-Sarnak 1999 线性扫描、Cytron et al. 1991 SSA、Lengauer-Tarjan 1979 支配树、Wegman-Zadeck SCCP、BURS / 最大吞噬、Appel《Modern Compiler Implementation》），以及与 LLVM、GCC、Cranelift、regalloc2 的分配 / SSA / isel 模型对比与实现边界声明。
- **质量门禁**：完整属性测试（着色尊重干涉、k 充足无溢出 / k 不足溢出且不变量保持、SSA 单赋值不变量、支配树正确性、φ 仅放在支配边界、SCCP 保持语义、GVN 保持语义、out-of-SSA 与 SSA 等价、线性扫描与着色在无溢出场景一致、isel 覆盖完整且代价最优、活跃性不动点正确），三后端（`wasm-gc` / `js` / `native`）一致性，`README.mbt.md` 可执行文档扩充，以及独立 SemVer 版本推进。

本规格承袭仓库统一质量基线（见 Requirement 16），并复用 `@directed`（图资产，提供 `tarjan_scc` / 拓扑序等）、`@infra_pbt`（`Gen` / `Rng` / `holds_for_all` / `round_trip`）、`@release_meta`（`DirectionRelease` / `QualityGates` / SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **Codegen_Infra**：本方向的编译器后端代码生成基础设施（子包 `src/codegen_infra`），是本文档所有验收标准的主体系统。
- **Var**：变量（虚拟寄存器）标识，以 `id : Int` 唯一标识，派生 `Compare + Eq + Hash + Show`，作为干涉图节点、活跃性集合元素与分配结果的键。
- **Location**：物理存储位置，枚举 `Reg(Int)`（物理寄存器编号）或 `Spill(Int)`（溢出栈槽编号）。
- **InterferenceGraph**：干涉图，由节点 `nodes : Array[Var]` 与无向干涉边 `edges : Array[(Var, Var)]` 构成；边的两端变量「同时活跃」而互相干涉，不能共享同一寄存器。
- **干涉边（Interference Edge）**：无向边 `(a, b)`，语义为变量 `a` 与 `b` 同时活跃从而不能被分配到同一物理寄存器。
- **干涉不变量（Interference Invariant）**：任意干涉边的两端变量若都被分配为寄存器，则其寄存器编号必不相同的性质。
- **k（寄存器数）**：可用物理寄存器的数量上限；分配时寄存器编号取值于 `0..k-1`，不足以着色的变量溢出。
- **溢出（Spill）**：当可用寄存器不足以为某变量分配寄存器时，将其放置到栈槽 `Spill(Int)` 的处理。
- **溢出代价（Spill Cost）**：用于在潜在溢出候选中选择溢出对象的启发式度量，综合使用频度与活跃区间长度等因素。
- **图着色分配（Graph-Coloring Allocation）**：以干涉图 k 着色建模寄存器分配的方法；本方向由 `allocate_coloring` 实现并升级为 Chaitin-Briggs 乐观着色。
- **Chaitin-Briggs 乐观着色（Optimistic Coloring）**：三阶段栈式着色——simplify（移除度 < k 节点入栈）、potential-spill（度 ≥ k 时乐观入栈标记潜在溢出）、select（出栈回填颜色，无可用颜色则实际溢出）。
- **寄存器合并（Coalescing）**：将通过传送（move / copy）相关联且不互相干涉的两个变量合并到同一寄存器以消除冗余传送的优化。
- **George 保守合并 / Briggs 保守合并（Conservative Coalescing）**：仅在合并不会增加图着色难度（不引入 ≥ k 高度数邻居）时才执行合并的两种保守判据。
- **LiveInterval**：活跃区间，结构 `{ variable : Var, start : Int, end : Int }`，表示变量在线性化指令序号上的活跃范围。
- **线性扫描分配（Linear Scan Allocation）**：按活跃区间起点升序扫描、回收过期区间寄存器并为当前区间分配空闲寄存器的分配方法；由 `allocate_linear_scan` 实现 Poletto-Sarnak 算法。
- **BasicBlock**：基本块，结构 `{ label : String, instrs : Array[String], succs : Array[String] }`，是控制流图的节点。
- **控制流图（CFG, Control Flow Graph）**：以基本块为节点、以 `succs` 后继关系为有向边的图。
- **前驱 / 后继（Predecessor / Successor）**：在 CFG 中，若存在边 `(u, v)` 则 `u` 为 `v` 的前驱、`v` 为 `u` 的后继。
- **支配（Dominate）**：在 CFG 中若从入口到节点 `n` 的每条路径都经过节点 `d`，则称 `d` 支配 `n`。
- **直接支配者（idom, Immediate Dominator）**：节点 `n` 的除自身外最近的支配者；除入口外每个可达节点有唯一 idom。
- **支配树（Dominator Tree）**：以 idom 为父子关系构成的树；由 Lengauer-Tarjan 算法计算。
- **支配边界（Dominance Frontier）**：节点 `n` 的支配边界是这样的节点集合——`n` 支配其某个前驱但不严格支配该节点本身；是放置 φ 的位置。
- **SsaProgram**：SSA 程序，结构 `{ blocks : Array[BasicBlock], phis : Array[Phi] }`。
- **SSA（Static Single Assignment，静态单赋值）**：每个变量版本恰被定义一次的中间表示形式。
- **单赋值不变量（Single-Assignment Invariant）**：SSA 程序中每个版本化变量在全程序至多被定义一次的性质。
- **版本化（Versioning）**：把同名变量的多次定义重写为带版本号的不同变量（如 `x#0` / `x#1`）的过程。
- **Phi（φ 函数）**：结构 `{ dest : Var, args : Array[Var] }`，置于汇合块开头，按控制流来路从各前驱选择对应版本的值。
- **最小 φ 放置（Minimal Phi Placement）**：仅在变量定义的支配边界处放置 φ 的策略；由 Cytron et al. 算法实现。
- **SSA 析构（Out-of-SSA / SSA Destruction）**：消除 φ 函数、将 SSA 程序转换回非 SSA 形式的过程。
- **并行复制（Parallel Copy）**：在控制流边上同时生效的一组复制；φ 消除时每条来路对应一组并行复制。
- **复制序列化与破环（Copy Sequentialization / Cycle Breaking）**：把并行复制转换为有序的串行复制序列，并在存在复制环（如 `a←b, b←a`）时引入临时变量打破循环以保持语义。
- **活跃性分析（Liveness Analysis）**：基于 CFG 的后向数据流分析，计算每个程序点的活跃变量集合（`live-in` / `live-out`）。
- **活跃变量（Live Variable）**：在某程序点其当前值在后续可能被使用的变量。
- **不动点迭代（Fixpoint Iteration）**：反复施加数据流传递方程直到集合不再变化的求解过程。
- **数据流优化（Dataflow Optimization）**：基于数据流信息变换程序的优化族，本方向含 SCCP、GVN、DCE、复制传播。
- **SCCP（Sparse Conditional Constant Propagation，稀疏条件常量传播）**：在 SSA 上联合常量传播与可达性分析、Wegman-Zadeck 提出的优化。
- **GVN（Global Value Numbering，全局值编号）**：为计算等价的表达式赋同一值编号并消除冗余计算的优化。
- **DCE（Dead Code Elimination，死代码消除）**：删除其结果从不被使用的定义的优化。
- **复制传播（Copy Propagation）**：将对复制目标的使用替换为复制源的优化。
- **Pass**：优化遍枚举，既有为 `ConstFold` / `DeadCodeElim` / `CopyProp`，旗舰深化追加 SCCP / GVN 等遍。
- **pass 框架（Pass Framework）**：按声明顺序施加优化遍、以不动点迭代驱动并保持 SSA 不变量的执行框架。
- **IrNode**：中间表示树节点，枚举 `Const(Int)` / `VarRef(Var)` / `BinOp(String, IrNode, IrNode)`。
- **指令选择（Instruction Selection, isel）**：将 IR 树映射为目标指令序列的过程；由 `select` 实现。
- **IselRule**：指令选择规则，结构 `{ pattern : String, template : String }`，按模式匹配 IR 节点并给出目标操作码。
- **最大吞噬（Maximal Munch）**：自顶向下每步贪心匹配能覆盖最大子树的规则的指令选择策略。
- **BURS（Bottom-Up Rewrite System）**：自底向上、带代价的树模式匹配指令选择，以动态规划求代价最优 tiling。
- **tiling（瓦覆盖）**：以一组模式「瓦片」覆盖整棵 IR 树的方案；最优 tiling 是总代价最小的覆盖。
- **代价最优（Cost-Optimal）**：在给定带代价规则集下，所选指令序列的总代价不大于任何其他合法覆盖方案的性质。
- **TargetInstr**：目标指令，结构 `{ op : String, operands : Array[String] }`，以不透明形式建模，不绑定真实 ISA。
- **@directed**：仓库共享有向图资产包，提供 `tarjan_scc`、`topological_sort`、`condensation` 等算法。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen` / `Rng` / `holds_for_all` / `round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease` / `QualityGates` / SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：图着色寄存器分配升级（Chaitin-Briggs 乐观着色）

**用户故事（User Story）：** 作为编译器后端开发者，我想要基于 Chaitin-Briggs 三阶段栈式乐观着色的寄存器分配，以便在寄存器充足时获得高质量着色、在不足时以受控方式溢出。

#### 验收标准（Acceptance Criteria）

1. WHEN 对干涉图执行图着色分配，THE Codegen_Infra SHALL 依次执行 simplify（反复移除度小于 `k` 的节点并压入选择栈）、potential-spill（无可移除低度节点时按溢出代价启发式选取一个度不小于 `k` 的节点乐观入栈并标记为潜在溢出）与 select（按入栈逆序出栈为每个节点回填一个未被其已着色邻居占用的最小寄存器）三个阶段。
2. WHEN select 阶段为某潜在溢出节点找不到可用寄存器，THE Codegen_Infra SHALL 将该节点分配为 `Spill` 栈槽位置。
3. WHILE 可用寄存器数 `k` 不小于干涉图的色数，THE Codegen_Infra SHALL 为每个节点分配 `Reg` 位置且不产生任何 `Spill`。
4. THE Codegen_Infra SHALL 为每个待分配变量产出恰好一个 `Location`（`Reg` 或 `Spill`），且分配结果以 `Var` 为键覆盖干涉图的全部节点。
5. FOR ALL 由生成器产生的干涉图与 `k`，THE Codegen_Infra SHALL 保证干涉不变量成立：任意干涉边两端若均被分配为 `Reg`，则其寄存器编号不同（着色尊重干涉，以 PBT 验证）。
6. FOR ALL 由生成器产生的干涉图与不小于其最大度加一的 `k`，THE Codegen_Infra SHALL 保证不产生任何 `Spill`（k 充足无溢出，以 PBT 验证）。

---

### Requirement 2：溢出代价启发式与寄存器合并（Coalescing）

**用户故事（User Story）：** 作为优化代码质量的后端开发者，我想要溢出代价启发式与保守寄存器合并，以便溢出选择更优且消除冗余传送指令而不增加着色难度。

#### 验收标准（Acceptance Criteria）

1. WHEN potential-spill 阶段需选取乐观溢出候选，THE Codegen_Infra SHALL 依据综合使用频度与活跃区间长度的溢出代价启发式选择代价度量最低的节点作为乐观溢出候选。
2. WHERE 启用寄存器合并，THE Codegen_Infra SHALL 仅在两个传送相关变量互不干涉时考虑将其合并到同一寄存器。
3. WHERE 启用寄存器合并且采用保守判据，THE Codegen_Infra SHALL 仅在合并后产生的节点的「度不小于 `k` 的邻居数」不超过判据阈值（George 或 Briggs 保守条件）时执行合并。
4. IF 两个变量之间存在干涉边，THEN THE Codegen_Infra SHALL 拒绝合并该变量对。
5. FOR ALL 由生成器产生的干涉图与合并候选集，THE Codegen_Infra SHALL 保证合并后再分配仍满足干涉不变量，且合并不会引入新的溢出（保守合并安全性，以 PBT 验证）。

---

### Requirement 3：线性扫描分配与着色一致性

**用户故事（User Story）：** 作为面向快速编译路径的后端开发者，我想要 Poletto-Sarnak 线性扫描分配，并在无溢出场景下与图着色给出一致的可分配性结论，以便在编译速度与代码质量间灵活取舍。

#### 验收标准（Acceptance Criteria）

1. WHEN 对活跃区间集合执行线性扫描分配，THE Codegen_Infra SHALL 按区间起点升序处理，先回收所有结束点早于当前区间起点的活跃区间所占寄存器，再为当前区间分配一个空闲寄存器。
2. IF 当前区间起点处空闲寄存器数为零，THEN THE Codegen_Infra SHALL 将某一活跃区间或当前区间溢出到 `Spill` 栈槽。
3. WHEN 任意时刻同时活跃（区间重叠）的区间数不超过 `k`，THE Codegen_Infra SHALL 为全部区间分配 `Reg` 位置且不产生 `Spill`。
4. FOR ALL 由生成器产生的活跃区间集合与 `k`，THE Codegen_Infra SHALL 保证任意两个区间重叠的变量不被分配到同一寄存器（线性扫描尊重重叠，以 PBT 验证）。
5. FOR ALL 由生成器产生的、最大重叠度不超过 `k` 的活跃区间集合，THE Codegen_Infra SHALL 保证线性扫描与图着色均判定为无需溢出（线性扫描与着色无溢出一致，以 PBT 验证）。

---

### Requirement 4：活跃性分析（Liveness）作为分配输入来源

**用户故事（User Story）：** 作为构建真实分配流水线的后端开发者，我想要基于 CFG 的活跃变量数据流分析，以便干涉图与活跃区间来自真实的活跃性而非人工构造。

#### 验收标准（Acceptance Criteria）

1. WHEN 对控制流图执行活跃性分析，THE Codegen_Infra SHALL 以后向数据流不动点迭代计算每个基本块的 `live-in` 与 `live-out` 变量集合，满足 `live-out(b)` 等于其全部后继 `live-in` 的并集、`live-in(b)` 等于 `use(b)` 与 `(live-out(b) 去除 def(b))` 的并集。
2. WHEN 活跃性不动点迭代到达稳定状态，THE Codegen_Infra SHALL 终止迭代并返回当次集合作为分析结果。
3. WHEN 由活跃性结果构造干涉图，THE Codegen_Infra SHALL 为在同一程序点同时活跃的每一对变量生成一条干涉边。
4. WHEN 由活跃性结果构造活跃区间，THE Codegen_Infra SHALL 使每个变量的区间覆盖其首次定义到最后一次活跃使用的线性化序号范围。
5. FOR ALL 由生成器产生的控制流图，THE Codegen_Infra SHALL 保证活跃性分析结果为数据流方程的不动点：再施加一次传递方程不改变任何块的 `live-in` 与 `live-out`（活跃性不动点正确，以 PBT 验证）。

---

### Requirement 5：支配树与支配边界（Lengauer-Tarjan）

**用户故事（User Story）：** 作为实现 SSA 与优化的后端开发者，我想要 Lengauer-Tarjan 支配树与支配边界计算，以便为最小 φ 放置与多种数据流优化提供支配信息。

#### 验收标准（Acceptance Criteria）

1. WHEN 对带唯一入口的控制流图计算支配关系，THE Codegen_Infra SHALL 以 Lengauer-Tarjan 算法为每个可达节点计算其直接支配者（idom）并构造支配树。
2. THE Codegen_Infra SHALL 使支配树中除入口外的每个可达节点恰有一个直接支配者。
3. WHEN 计算支配边界，THE Codegen_Infra SHALL 对每个节点产出其支配边界集合，其中节点 `n` 属于节点 `d` 的支配边界当且仅当 `d` 支配 `n` 的某个前驱且 `d` 不严格支配 `n`。
4. IF 某基本块从入口不可达，THEN THE Codegen_Infra SHALL 将其排除出支配树而不将其计入任何节点的支配关系。
5. FOR ALL 由生成器产生的带唯一入口的控制流图，THE Codegen_Infra SHALL 保证支配树正确性：每个可达非入口节点恰有一个 idom，且由 idom 父链推出的支配关系与「入口到该节点的所有路径均经过支配者」的定义一致（支配树正确性，以 PBT 验证）。

---

### Requirement 6：最小 SSA 构造（Cytron et al. 支配边界 φ 放置）

**用户故事（User Story）：** 作为构造 SSA 的后端开发者，我想要仅在支配边界放置 φ 的最小 SSA 构造，以便 φ 数量最小化同时保持既有 `build_ssa` 行为兼容。

#### 验收标准（Acceptance Criteria）

1. WHEN 构造最小 SSA，THE Codegen_Infra SHALL 仅在某变量的（迭代）支配边界对应的基本块处为该变量放置 φ 函数。
2. WHEN 为某变量在汇合块放置 φ，THE Codegen_Infra SHALL 使该 φ 的实参个数等于该汇合块的前驱个数。
3. WHEN 重命名变量定义与使用，THE Codegen_Infra SHALL 将每个定义重写为带版本号的唯一变量，并将每个使用重写为引用其支配路径上最近的定义版本。
4. WHEN 接收到既有最小文法输入（直线代码或简单菱形控制流），THE Codegen_Infra SHALL 产出与 `0.1.0` 骨架 `build_ssa` 在 φ 数量、版本化文本与块结构上一致的 `SsaProgram`（向后兼容）。
5. FOR ALL 由生成器产生的控制流图，THE Codegen_Infra SHALL 保证 φ 仅出现在对应变量的支配边界块（φ 仅放在支配边界，以 PBT 验证）。
6. FOR ALL 由生成器产生的控制流图，THE Codegen_Infra SHALL 保证构造结果满足单赋值不变量：每个版本化变量在全程序至多被定义一次（SSA 单赋值不变量，以 PBT 验证）。

---

### Requirement 7：SSA 析构（Out-of-SSA）—— 并行复制与破环序列化

**用户故事（User Story）：** 作为需要将 SSA 降级回执行形式的后端开发者，我想要把 φ 消除为并行复制并正确序列化，以便去 SSA 后的程序与 SSA 形式语义等价。

#### 验收标准（Acceptance Criteria）

1. WHEN 析构 SSA，THE Codegen_Infra SHALL 将每个 φ 函数消除为：在每个前驱到汇合块的控制流边上，从该前驱对应的 φ 实参向 φ 目标的一次复制。
2. WHEN 同一控制流边上存在多个并行复制，THE Codegen_Infra SHALL 将其序列化为保持并行语义的串行复制序列。
3. IF 并行复制集合存在复制环（目标与源相互依赖形成循环），THEN THE Codegen_Infra SHALL 引入临时变量打破该环以保持复制语义。
4. WHEN 析构完成，THE Codegen_Infra SHALL 产出不含任何 φ 函数的程序。
5. FOR ALL 由生成器产生的 SSA 程序与给定初始变量赋值，THE Codegen_Infra SHALL 保证按任一控制流路径解释执行析构后程序所得的目标变量取值，与按 SSA 语义沿同一路径求值 φ 所得取值一致（out-of-SSA 与 SSA 语义等价，以 PBT 验证）。

---

### Requirement 8：稀疏条件常量传播（SCCP）

**用户故事（User Story）：** 作为优化常量与不可达分支的后端开发者，我想要 Wegman-Zadeck 稀疏条件常量传播，以便在保持程序语义的前提下折叠常量并标记不可达代码。

#### 验收标准（Acceptance Criteria）

1. WHEN 在 SSA 程序上执行 SCCP，THE Codegen_Infra SHALL 联合维护每个 SSA 变量的格值（未定 / 常量 / 不确定）与每条 CFG 边的可达性，并以工作表迭代至不动点。
2. WHEN 某 SSA 变量在不动点处被判定为常量，THE Codegen_Infra SHALL 将其全部使用替换为该常量值。
3. WHEN 某条件分支的条件在不动点处被判定为常量，THE Codegen_Infra SHALL 仅将该条件选定的后继边标记为可达，另一后继边标记为不可达。
4. THE Codegen_Infra SHALL 在 SCCP 变换后保持 SSA 单赋值不变量。
5. FOR ALL 由生成器产生的 SSA 程序与给定初始变量赋值，THE Codegen_Infra SHALL 保证 SCCP 变换前后程序在所有可达输出上的解释执行结果一致（SCCP 保持语义，以 PBT 验证）。

---

### Requirement 9：全局值编号（GVN）与强化 DCE / 复制传播

**用户故事（User Story）：** 作为消除冗余计算的后端开发者，我想要全局值编号与在 SSA 上强化的死代码消除与复制传播，以便去除等价的重复计算且不改变程序语义。

#### 验收标准（Acceptance Criteria）

1. WHEN 在 SSA 程序上执行 GVN，THE Codegen_Infra SHALL 为计算等价（相同操作符与相同值编号操作数）的表达式赋同一值编号，并将后继冗余计算替换为对先前等价计算结果的引用。
2. WHEN 执行死代码消除，THE Codegen_Infra SHALL 删除其定义结果从不被任何活跃使用引用且无副作用的指令。
3. WHEN 执行复制传播，THE Codegen_Infra SHALL 将对复制目标变量的使用替换为对其复制源变量的使用。
4. THE Codegen_Infra SHALL 在 GVN、死代码消除与复制传播变换后保持 SSA 单赋值不变量。
5. FOR ALL 由生成器产生的 SSA 程序与给定初始变量赋值，THE Codegen_Infra SHALL 保证 GVN 变换前后程序在所有输出上的解释执行结果一致（GVN 保持语义，以 PBT 验证）。

---

### Requirement 10：pass 框架（不动点迭代）与 SSA 不变量保持

**用户故事（User Story）：** 作为编排优化遍的后端开发者，我想要按声明顺序施加优化遍并以不动点迭代收敛的 pass 框架，以便组合优化既可预测又始终维持 SSA 形式。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用 `run_passes` 并给定优化遍序列，THE Codegen_Infra SHALL 按声明顺序依次施加每个优化遍。
2. WHERE 优化遍序列被声明为迭代至不动点，THE Codegen_Infra SHALL 反复施加该序列直到程序在一轮内不再发生变化为止。
3. THE Codegen_Infra SHALL 在每个优化遍施加后保持 SSA 单赋值不变量。
4. WHEN 接收到既有 `Pass`（`ConstFold` / `DeadCodeElim` / `CopyProp`）序列，THE Codegen_Infra SHALL 产出与 `0.1.0` 骨架 `run_passes` 一致的结果（向后兼容）。
5. FOR ALL 由生成器产生的 SSA 程序与优化遍序列，THE Codegen_Infra SHALL 保证施加优化遍后结果仍满足 SSA 单赋值不变量（pass 保持 SSA 不变量，以 PBT 验证）。

---

### Requirement 11：指令选择升级（最大吞噬 / BURS 代价最优 tiling）

**用户故事（User Story）：** 作为生成目标指令的后端开发者，我想要带代价的树模式匹配指令选择，以便完整覆盖 IR 树并产出代价最优的指令序列。

#### 验收标准（Acceptance Criteria）

1. WHEN 对 IR 树执行指令选择，THE Codegen_Infra SHALL 以模式规则覆盖树中每个节点，使产出的目标指令序列覆盖整棵 IR 树而无未匹配节点。
2. WHERE 采用 BURS 带代价匹配，THE Codegen_Infra SHALL 以自底向上动态规划为每个子树计算最小代价的覆盖方案，并据此产出总代价最小的指令序列。
3. WHERE 存在运算符特化规则（如 `BinOp:<op>`）与通用规则（如 `BinOp`）同时匹配，THE Codegen_Infra SHALL 优先选用运算符特化规则。
4. WHEN 接收到既有 `IselRule` 集合与 IR 树，THE Codegen_Infra SHALL 产出与 `0.1.0` 骨架 `select` 一致的后序遍历指令序列（向后兼容）。
5. FOR ALL 由生成器产生的 IR 树与覆盖完整的带代价规则集，THE Codegen_Infra SHALL 保证所选指令序列覆盖每个 IR 节点（isel 覆盖完整，以 PBT 验证）。
6. FOR ALL 由生成器产生的 IR 树与覆盖完整的带代价规则集，THE Codegen_Infra SHALL 保证所选覆盖方案的总代价不大于任何其他合法覆盖方案的总代价（isel 代价最优，以 PBT 验证）。

---

### Requirement 12：旗舰端到端示例 —— 完整后端流水线

**用户故事（User Story）：** 作为评估该库能力的开发者，我想要一份贯穿文档与基准的小程序后端流水线示例，以便我能看到从 CFG 到指令选择的完整代码生成链路在真实结构上的端到端用法。

#### 验收标准（Acceptance Criteria）

1. THE Codegen_Infra SHALL 提供一份带控制流分支的小程序示例，覆盖从基本块控制流图到目标指令序列的完整后端流水线。
2. WHEN 对该示例依次执行活跃性分析 → 最小 SSA 构造 → SCCP / GVN / DCE 优化 → 图着色与线性扫描分配 → 指令选择，THE Codegen_Infra SHALL 在每一阶段产出与示例文档所声明一致的结果。
3. WHEN 对该示例构造 SSA，THE Codegen_Infra SHALL 仅在支配边界放置 φ 并产出文档所声明的 φ 数量。
4. WHEN 对该示例由活跃性结果构造的干涉图执行图着色分配且 `k` 充足，THE Codegen_Infra SHALL 产出无溢出且满足干涉不变量的分配结果。
5. WHEN 对该示例的同一无溢出场景分别执行图着色与线性扫描分配，THE Codegen_Infra SHALL 在「是否需要溢出」的结论上得到一致结果。

---

### Requirement 13：性能基准（benches/）

**用户故事（User Story）：** 作为关心后端编译性能的开发者，我想要可复现的基准证据覆盖大规模 CFG 的核心计算，以便我能确认支配树、SSA 构造、着色、线性扫描与 SCCP 的扩展趋势并防止回归。

#### 验收标准（Acceptance Criteria）

1. THE Codegen_Infra SHALL 在 `benches/` 下提供基准包，覆盖大规模控制流图上的支配树构造、SSA 构造、图着色分配、线性扫描分配与 SCCP 五类工作负载。
2. WHEN 运行基准，THE Codegen_Infra SHALL 输出包含机器标识、后端目标、图规模（节点数、边数、变量数）与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE Codegen_Infra SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的回归失败报告。
4. WHEN 运行 native 后端基准或测试，THE Codegen_Infra SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Codegen_Infra SHALL 在基准文档中记录可复现运行命令与图规模参数，以保证基准可被独立重跑。

---

### Requirement 14：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键算法可追溯到源论文并与主流编译器后端对比，以便我能理解设计依据、取舍与实现边界。

#### 验收标准（Acceptance Criteria）

1. THE Codegen_Infra SHALL 在文档中将图着色分配追溯到 Chaitin（1982）与 Briggs（1994），将线性扫描追溯到 Poletto-Sarnak（1999）。
2. THE Codegen_Infra SHALL 在文档中将最小 SSA 构造追溯到 Cytron et al.（1991）、将支配树算法追溯到 Lengauer-Tarjan（1979）、将 SCCP 追溯到 Wegman-Zadeck，并将指令选择追溯到 BURS / 最大吞噬与 Appel《Modern Compiler Implementation》。
3. THE Codegen_Infra SHALL 在文档中提供与 LLVM、GCC、Cranelift 与 regalloc2 的对比，覆盖寄存器分配策略、SSA 构造与指令选择模型差异。
4. THE Codegen_Infra SHALL 在文档中显式声明实现边界：本方向停留在算法与中间表示模型层，不生成真实目标机器码、不汇编或链接、不绑定具体指令集架构。
5. WHERE 本库的语义与所对标编译器后端存在差异，THE Codegen_Infra SHALL 显式声明该差异及其理由，而非隐式留白。

---

### Requirement 15：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有调用方在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Codegen_Infra SHALL 保留既有公开类型 `Var`、`Location`、`InterferenceGraph`、`LiveInterval`、`BasicBlock`、`Phi`、`SsaProgram`、`Pass`、`IselRule`、`IrNode`、`TargetInstr` 的现有字段与派生语义。
2. THE Codegen_Infra SHALL 保留既有接口 `allocate_coloring`、`allocate_linear_scan`、`interference_components`、`build_ssa`、`run_passes`、`select` 的现有公开签名与行为。
3. THE Codegen_Infra SHALL 复用 `@directed` 的 `tarjan_scc`（用于 `interference_components` 的连通分量分解）与拓扑序算法，而不重写已被覆盖的图算法。
4. THE Codegen_Infra SHALL 复用 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all` / `round_trip` 作为全部新增属性测试的模板。
5. WHERE 新增能力需要扩展行为，THE Codegen_Infra SHALL 以新增 API 的方式提供（既有 `0.1.0` 契约冻结、新能力旁路扩展），而不破坏既有 API 的调用方。

---

### Requirement 16：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Codegen_Infra SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Codegen_Infra SHALL 为本规格的核心正确性属性（着色尊重干涉、k 充足无溢出、保守合并安全性、线性扫描尊重重叠、线性扫描与着色无溢出一致、活跃性不动点正确、支配树正确性、φ 仅放在支配边界、SSA 单赋值不变量、out-of-SSA 与 SSA 语义等价、SCCP 保持语义、GVN 保持语义、pass 保持 SSA 不变量、isel 覆盖完整、isel 代价最优）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE Codegen_Infra SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖升级后的图着色分配、线性扫描、最小 SSA 构造、SSA 析构、数据流优化、升级后的指令选择与旗舰端到端示例，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE Codegen_Infra SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Codegen_Infra SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. IF 本方向的三后端测试、属性测试或可执行文档校验未通过，THEN THE Codegen_Infra SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
