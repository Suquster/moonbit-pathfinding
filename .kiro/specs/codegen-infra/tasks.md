# 实施计划（Implementation Plan）：Codegen_Infra 旗舰深化

## 概述（Overview）

本计划将 `design.md` 的旗舰深化拆解为一系列**增量、可执行、聚焦编码**的 MoonBit 任务，严格遵循「既有契约冻结、新能力旁路扩展」原则：

- **冻结不改**：`codegen_infra.mbt`（核心类型 `Var`/`Location`/`InterferenceGraph`/`LiveInterval`/`BasicBlock`/`Phi`/`SsaProgram`/`Pass`/`IselRule`/`IrNode`/`TargetInstr` 与 `allocate_coloring`/`allocate_linear_scan`/`interference_components`/`build_ssa`/`run_passes`/`select`）、`release.mbt`（`release_info`/`release_info_with_gates`）的既有 `pub`/`pub(all)` 声明签名、字段、变体与运行时行为一律不动；`pkg.generated.mbti` 既有条目稳定、仅追加。
- **枚举不扩容**：`Pass`（`ConstFold`/`DeadCodeElim`/`CopyProp`）不增加变体；新优化遍（SCCP/GVN）由新增 `OptPass` 枚举 + 新驱动 `run_pipeline`/`run_to_fixpoint` 旁路提供，既有 `run_passes(SsaProgram, Array[Pass])` 行为冻结。
- **复用而非重写**：连通分量分解复用 `@directed.tarjan_scc`；属性测试复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）；发布元数据复用 `@release_meta`。新增文件与既有 `codegen_infra.mbt` 同包，直接复用包内私有辅助（`tokenize`/`join_tokens`/`versioned`/`version_id`/`parse_int`/`rename_use` 等）。
- **任务依赖顺序**：活跃性 / 支配树 → 参考解释器 / 最小 SSA / out-of-SSA → SCCP / GVN / pass 框架 → 图着色 / 合并 / 线性扫描一致 → BURS / isel → demo / 基准 / 文档 / 发布，并设阶段检查点。
- **实现语言**：MoonBit（仅 `.mbt` / `.mbt.md` / `.md`，不写其他语言）。所有源文件位于 `src/codegen_infra/`，基准位于 `benches/codegen_bench/`。
- **属性测试**：P1–P17 每条独立成一个 `*` 可选子任务，统一以 `@infra_pbt` 的 `holds_for_all` / `round_trip` 实现，每条至少 100 次迭代，标注 `Feature: codegen-infra, Property N`。语义保持类属性（P12 out-of-SSA、P13 SCCP、P14 GVN）以参考解释器 `evaluate` 作为 oracle；指令选择代价最优（P17）以穷举 tiling 暴力解作为 oracle。
- **native 前置约束**：凡在 native 后端运行测试、运行基准、或校验 `README.mbt.md` 可执行文档的环节，**必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（见各检查点、基准与文档任务，以及末尾 Notes）。

---

## 任务（Tasks）

- [x] 1. 活跃性分析（`liveness.mbt`，旁路新增）
  - [x] 1.1 实现活跃性后向不动点分析与构造桥
    - 在 `src/codegen_infra/liveness.mbt` 新增 `LivenessResult`（`live_in` / `live_out` 块标签→变量集，`derive(Show)`），复用包内私有 `tokenize` 解析块内记号串提取 `use`/`def`（`name = rhs...` 定义 `name`、右值变量为 use；`ret x` / `br L` / `cbr c L1 L2` 仅含 use）
    - 实现 `analyze_liveness(blocks)`：后向数据流不动点迭代，满足 `live_out(b)=⋃_{s∈succ(b)} live_in(s)`、`live_in(b)=use(b)∪(live_out(b)\def(b))`，集合以 `Var.id` 升序数组规范化保三后端确定性
    - 实现 `build_interference_from_liveness`（同一程序点同时活跃的变量对建无向边）与 `build_intervals_from_liveness`（覆盖首次定义→最后一次活跃使用的线性序号区间）
    - 文件头注释标注 paper-to-code 来源（经典后向数据流不动点；Appel《Modern Compiler Implementation》）
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x]* 1.2 活跃性单元测试（构造端点 / 集合规范化见证）
    - 在 `src/codegen_infra/liveness_test.mbt` 覆盖 `build_interference_from_liveness` 端点见证、`build_intervals_from_liveness` 区间端点见证与集合升序规范化
    - _Requirements: 4.3, 4.4_

  - [x]* 1.3 编写属性测试：活跃性不动点正确
    - **Property 6: 活跃性不动点正确（再施加一次传递方程不改变任何块的 live-in / live-out）**
    - **Validates: Requirements 4.1, 4.5**
    - 文件 `src/codegen_infra/prop_liveness_test.mbt`，以 `@infra_pbt` 生成带唯一入口的随机 CFG，`holds_for_all` ≥100 迭代

- [x] 2. 支配树与支配边界（`dominator.mbt`，旁路新增）
  - [x] 2.1 实现 Lengauer-Tarjan 支配树与支配边界
    - 在 `src/codegen_infra/dominator.mbt` 新增 `DomTree`（`root` / `idom` / `children` / `reachable`，`derive(Show)`），实现 `build_dom_tree(blocks, entry~)`（DFS 编号 → 半支配者 → 带路径压缩 forest 求 idom；不可达块不参与 DFS 从而被排除）
    - 实现 `dominance_frontier`（Cytron DF：对每个 ≥2 前驱的汇合块 `n`，对其每个前驱沿 idom 链上溯至 `idom(n)` 前，途中节点 DF 加入 `n`）与 `DomTree::dominates`（idom 父链上溯判定）
    - 文件头注释标注 Lengauer-Tarjan 1979 与 Cytron et al. 1991
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x]* 2.2 支配单元测试（不可达排除 / idom 唯一性边界）
    - 在 `src/codegen_infra/dominator_test.mbt` 覆盖不可达块被排除出支配树、除入口外每个可达节点恰有一个 idom 的具体见证
    - _Requirements: 5.2, 5.4_

  - [x]* 2.3 编写属性测试：支配树正确性
    - **Property 7: 支配树正确性（每个可达非入口节点恰有一个 idom，且 idom 父链推出的支配关系与「入口到该节点的所有路径均经过支配者」一致）**
    - **Validates: Requirements 5.1, 5.2, 5.5**
    - 文件 `src/codegen_infra/prop_dom_tree_test.mbt`，生成带唯一入口的随机 CFG，以「枚举入口到节点的路径校验支配定义」为参考，≥100 迭代

  - [x]* 2.4 编写属性测试：支配边界正确性
    - **Property 8: 支配边界正确性（`n` 属于 `d` 的支配边界 ⟺ `d` 支配 `n` 的某前驱且 `d` 不严格支配 `n`）**
    - **Validates: Requirements 5.3**
    - 文件 `src/codegen_infra/prop_dom_frontier_test.mbt`，生成带唯一入口的随机 CFG，对全部 `(d, n)` 节点对双向校验，≥100 迭代

- [x] 3. 检查点 —— 确保活跃性与支配关系全部测试通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行至此为止的测试套件；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. 参考解释器（`evaluate.mbt`，旁路新增；语义保持属性 oracle）
  - [x] 4.1 实现参考解释器
    - 在 `src/codegen_infra/evaluate.mbt` 新增 `EvalResult`（`values` 变量取值 + `output` 输出序列，`derive(Eq, Show)`），实现 `evaluate(p, init, path)`：沿给定块标签路径解释执行，处理 `name = a op b`（整数算术，沿用既有 `fold_op` 的 `+ - *` 语义）、`ret x`（产出）、`cbr/br`（按 `path` 实走分支）与 φ（按进入汇合块的前驱选择对应实参版本求值）
    - 实现为纯函数、确定性，三后端逐位一致，专用于比较「变换前后」「SSA 与析构后」在相同 `init`/`path` 下的输出与目标变量取值
    - 文件头注释标注其作为 R7.5/R8.5/R9.5 语义 oracle 的定位
    - _Requirements: 7.5, 8.5, 9.5_

  - [x]* 4.2 参考解释器单元测试（算术 / 控制流 / φ 求值见证）
    - 在 `src/codegen_infra/evaluate_test.mbt` 覆盖直线算术求值、`cbr` 沿指定分支走、φ 按来路选实参的具体见证
    - _Requirements: 7.5_

- [x] 5. 最小 SSA 构造（`ssa_min.mbt`，旁路新增）
  - [x] 5.1 实现 Cytron 支配边界 φ 放置与重命名
    - 在 `src/codegen_infra/ssa_min.mbt` 实现 `build_ssa_minimal(blocks, entry~)`：① 复用 `build_dom_tree` 与（迭代）支配边界；② 对每个变量在其定义块集合的迭代支配边界处放置 φ（实参数等于汇合块前驱数）；③ 沿支配树前序遍历重命名（定义分配带版本号唯一变量、使用重写为支配路径最近定义版本，进入汇合块以 φ 目标作当前版本），复用包内私有 `versioned` / `version_id` / `rename_use` 保持 `name#ver` 格式
    - 向后兼容：对既有最小文法（直线代码 / 简单菱形）在 φ 数量、版本化文本与块结构上与冻结 `build_ssa` 一致（既有 `build_ssa` 不改）
    - 文件头注释标注 Cytron et al. 1991
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x]* 5.2 最小 SSA 单元测试（重命名见证 / 向后兼容快照）
    - 在 `src/codegen_infra/ssa_min_test.mbt` 覆盖菱形汇合的版本化重命名见证，以及在最小文法输入上 `build_ssa_minimal` 与 `build_ssa` 的 φ 数量 / 版本化文本 / 块结构逐字段一致
    - _Requirements: 6.3, 6.4_

  - [x]* 5.3 编写属性测试：φ 仅放在支配边界
    - **Property 9: φ 仅放在支配边界（每个 φ 所在块都属于其对应变量定义块集合的迭代支配边界）**
    - **Validates: Requirements 6.1, 6.5**
    - 文件 `src/codegen_infra/prop_ssa_phi_frontier_test.mbt`，生成带唯一入口的随机 CFG，≥100 迭代

  - [x]* 5.4 编写属性测试：φ 结构良构
    - **Property 10: φ 结构良构（每个 φ 实参个数等于其所在汇合块的前驱个数）**
    - **Validates: Requirements 6.2**
    - 文件 `src/codegen_infra/prop_ssa_phi_arity_test.mbt`，生成带唯一入口的随机 CFG，≥100 迭代

  - [x]* 5.5 编写属性测试：SSA 单赋值不变量
    - **Property 11: SSA 单赋值不变量（每个版本化变量在全程序至多被定义一次）**
    - **Validates: Requirements 6.6**
    - 白盒文件 `src/codegen_infra/prop_ssa_single_assign_wbtest.mbt`（经包内私有 `version_id` 抽取版本号统计定义次数），生成随机 CFG，≥100 迭代

- [x] 6. SSA 析构 / out-of-SSA（`out_of_ssa.mbt`，旁路新增）
  - [x] 6.1 实现 φ 消除与并行复制破环序列化
    - 在 `src/codegen_infra/out_of_ssa.mbt` 实现 `destruct_ssa(p)`：对每个 φ 在「第 i 个前驱→汇合块」边上插入复制 `dest ← arg_i`，消除全部 φ 产出无 φ 等价程序；实现 `sequentialize_parallel_copy(copies)`：以「就绪节点优先 + 环检测引入临时」将并行复制转串行（仅剩环如 `a←b, b←a` 时引入临时 `t←a` 改写一条复制以保并行语义）
    - 文件头注释标注 Sreedhar et al. / Boissinot 并行复制破环
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x]* 6.2 析构单元测试（swap 环破环 / 析构后无 φ）
    - 在 `src/codegen_infra/out_of_ssa_test.mbt` 覆盖 `a←b, b←a` 复制环引入临时打破的见证，以及析构后 `phis` 为空
    - _Requirements: 7.3, 7.4_

  - [x]* 6.3 编写属性测试：out-of-SSA 与 SSA 语义等价
    - **Property 12: out-of-SSA 与 SSA 语义等价（沿任一路径解释执行析构后程序所得目标变量取值与可达输出，与按 SSA 语义沿同一路径求 φ 一致；且析构后不含 φ）**
    - **Validates: Requirements 7.1, 7.2, 7.4, 7.5**
    - 文件 `src/codegen_infra/prop_out_of_ssa_test.mbt`，以 `evaluate` 为 oracle，生成随机 SSA 程序 + 初始赋值 + 控制流路径，≥100 迭代

- [x] 7. 检查点 —— 确保参考解释器与 SSA 构造 / 析构全部测试通过
  - 在三后端运行至此为止的测试套件；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. 稀疏条件常量传播 / SCCP（`sccp.mbt`，旁路新增）
  - [x] 8.1 实现 Wegman-Zadeck SCCP
    - 在 `src/codegen_infra/sccp.mbt` 新增 `LatticeValue`（`Top` / `Const(Int)` / `Bottom`，`derive(Eq, Show)`），实现 `sccp(p)`：联合维护 SSA 变量格值（`Top→Const→Bottom` 单调下降）与 CFG 边可达性的工作表迭代；不动点处常量变量的全部使用替换为常量字面量，常量条件分支仅标记选定后继边可达；变换仅折叠 / 替换不引入重复定义以保持单赋值不变量
    - 文件头注释标注 Wegman-Zadeck 1991
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [x]* 8.2 SCCP 单元测试（恒真 / 恒假分支 / 常量折叠见证）
    - 在 `src/codegen_infra/sccp_test.mbt` 覆盖常量条件仅一侧后继可达、常量变量使用被替换的具体见证
    - _Requirements: 8.2, 8.3_

  - [x]* 8.3 编写属性测试：SCCP 保持语义
    - **Property 13: SCCP 保持语义（变换前后程序在所有可达输出上解释执行结果一致；且保持 SSA 单赋值不变量）**
    - **Validates: Requirements 8.4, 8.5**
    - 文件 `src/codegen_infra/prop_sccp_test.mbt`，以 `evaluate` 为 oracle，生成随机 SSA 程序 + 初始赋值 + 路径，≥100 迭代

- [x] 9. 全局值编号与强化 DCE / 复制传播（`gvn.mbt`，旁路新增）
  - [x] 9.1 实现 GVN / dce_strong / copy_prop_strong
    - 在 `src/codegen_infra/gvn.mbt` 实现 `gvn(p)`（哈希值编号表：相同操作符 + 相同值编号操作数赋同一值编号，后继冗余计算替换为先前等价结果引用）、`dce_strong(p)`（删除无活跃使用且无副作用的定义，含 φ 实参用法）、`copy_prop_strong(p)`（单记号复制目标使用替换为源并删除复制，含 φ 实参）；三者仅删除 / 改写不重复定义以保持单赋值不变量
    - 文件头注释标注值编号 / Appel《Modern Compiler Implementation》
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [x]* 9.2 GVN 单元测试（等价表达式复用 / 死定义删除 / 复制传播见证）
    - 在 `src/codegen_infra/gvn_test.mbt` 覆盖两个计算等价表达式被合并、无活跃使用定义被删除、复制目标使用被替换为源的具体见证
    - _Requirements: 9.1, 9.2, 9.3_

  - [x]* 9.3 编写属性测试：GVN 保持语义
    - **Property 14: GVN 保持语义（含强化 DCE 与复制传播，变换前后程序在所有输出上解释执行结果一致；且保持 SSA 单赋值不变量）**
    - **Validates: Requirements 9.4, 9.5**
    - 文件 `src/codegen_infra/prop_gvn_test.mbt`，以 `evaluate` 为 oracle，生成随机 SSA 程序 + 初始赋值 + 路径，≥100 迭代

- [x] 10. pass 框架 —— 不动点驱动（`pipeline.mbt`，旁路新增）
  - [x] 10.1 实现 OptPass 与按序 / 不动点驱动
    - 在 `src/codegen_infra/pipeline.mbt` 新增 `OptPass`（`ConstFold` / `DeadCodeElim` / `CopyProp` / `Sccp` / `Gvn`，`derive(Eq, Show)`），实现 `run_pipeline(p, passes)`（按声明顺序施加一遍，`ConstFold`/`DeadCodeElim`/`CopyProp` 委托既有实现，`Sccp`/`Gvn` 委托 `sccp`/`gvn`）与 `run_to_fixpoint(p, passes, max_iters~=64)`（反复施加直到一轮内不变或达安全上界）
    - 既有 `run_passes(SsaProgram, Array[Pass])` 行为完全冻结、旗舰驱动为其旁路超集
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [x]* 10.2 pass 框架单元测试（顺序 / 收敛 / run_passes 冻结）
    - 在 `src/codegen_infra/pipeline_test.mbt` 覆盖按声明顺序施加、不动点收敛终止、以及既有 `run_passes` 在既有 `Pass` 序列上与 `0.1.0` 一致的回归见证
    - _Requirements: 10.1, 10.2, 10.4_

  - [x]* 10.3 编写属性测试：pass 框架保持 SSA 不变量
    - **Property 15: pass 框架保持 SSA 不变量（经 run_pipeline 或 run_to_fixpoint 施加任意 OptPass 序列后仍满足单赋值不变量）**
    - **Validates: Requirements 8.4, 9.4, 10.3, 10.5**
    - 白盒文件 `src/codegen_infra/prop_pipeline_wbtest.mbt`（经 `version_id` 校验单赋值），生成随机 SSA 程序 + 随机 OptPass 序列，≥100 迭代

- [x] 11. 检查点 —— 确保数据流优化与 pass 框架全部测试通过
  - 在三后端运行至此为止的测试套件；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 12. Chaitin-Briggs 乐观着色与溢出代价（`coloring.mbt`，旁路新增）
  - [x] 12.1 实现三阶段栈式乐观着色与溢出代价启发式
    - 在 `src/codegen_infra/coloring.mbt` 新增 `SpillCost`（`cost` 变量→度量，`derive(Show)`，附 `SpillCost::uniform()`），实现 `spill_cost(g, intervals)`（综合使用频度与活跃区间长度）与 `allocate_coloring_briggs(g, k, cost~)`：simplify（反复移除度 `<k` 节点入栈）→ potential-spill（无低度节点时按 `spill_cost` 选代价最低的度 `≥k` 节点乐观入栈标记潜在溢出）→ select（按逆序出栈回填未被已着色邻居占用的最小寄存器 `[0,k)`，潜在溢出节点无可用寄存器则实际溢出 `Spill`）
    - 为每个待分配变量产出恰一个 `Location` 且覆盖全部节点；既有 `allocate_coloring` 保留为基线不被替换
    - 文件头注释标注 Chaitin 1982 / Briggs 1994
    - _Requirements: 1.1, 1.2, 1.4, 2.1_

  - [x]* 12.2 着色单元测试（阶段顺序 / k 不足出 Spill / 溢出代价选中）
    - 在 `src/codegen_infra/coloring_test.mbt` 覆盖 simplify/potential-spill/select 阶段顺序见证、`k` 不足时出现 `Spill`、potential-spill 选中预期最低代价节点
    - _Requirements: 1.1, 1.2, 2.1_

  - [x]* 12.3 编写属性测试：着色尊重干涉且分配良构
    - **Property 1: 着色尊重干涉且分配良构（结果以 Var 为键恰覆盖全部节点、每变量恰一个 Location，任意干涉边两端若都为 Reg 则编号不同）**
    - **Validates: Requirements 1.4, 1.5**
    - 文件 `src/codegen_infra/prop_coloring_interference_test.mbt`，生成随机干涉图 + 随机 `k`，≥100 迭代

  - [x]* 12.4 编写属性测试：k 充足无溢出
    - **Property 2: k 充足无溢出（k 不小于最大度加一时不产生任何 Spill，全部节点分配为 Reg）**
    - **Validates: Requirements 1.3, 1.6**
    - 文件 `src/codegen_infra/prop_coloring_ksufficient_test.mbt`，生成随机干涉图并取 `k = 最大度 + 1`，≥100 迭代

- [x] 13. 寄存器合并 / Coalescing（`coalescing.mbt`，旁路新增）
  - [x] 13.1 实现 George / Briggs 保守合并
    - 在 `src/codegen_infra/coalescing.mbt` 新增 `MoveSet`（`moves` 传送相关对，`derive(Show)`）与 `CoalesceStrategy`（`George` / `Briggs`，`derive(Eq, Show)`），实现 `can_coalesce_george`（`a` 每个邻居要么与 `b` 干涉、要么度 `<k`）、`can_coalesce_briggs`（合并后节点的度 `≥k` 邻居数 `<k`）与 `coalesce(g, moves, k, strategy~)`：仅在两变量互不干涉且满足保守判据时合并，存在干涉边即拒绝，返回合并后的干涉图
    - 文件头注释标注 George-Appel 1996 / Briggs 1994 保守判据
    - _Requirements: 2.2, 2.3, 2.4_

  - [x]* 13.2 合并单元测试（George / Briggs 判据布尔 / 干涉拒绝）
    - 在 `src/codegen_infra/coalescing_test.mbt` 覆盖两判据在典型图上的布尔结果，以及存在干涉边时拒绝合并的见证
    - _Requirements: 2.3, 2.4_

  - [x]* 13.3 编写属性测试：保守合并安全性
    - **Property 3: 保守合并安全性（保守判据下合并后再分配仍满足干涉不变量，溢出数量不大于合并前，互相干涉的变量对不被合并）**
    - **Validates: Requirements 2.2, 2.4, 2.5**
    - 文件 `src/codegen_infra/prop_coalescing_test.mbt`，生成随机干涉图 + 传送候选集 + `k`，合并前后均以 `allocate_coloring_briggs` 分配比较，≥100 迭代

- [x] 14. 线性扫描与图着色一致性（`consistency.mbt`，旁路新增；既有 `allocate_linear_scan` 冻结复用）
  - [x] 14.1 实现区间↔干涉图桥与溢出结论判定
    - 在 `src/codegen_infra/consistency.mbt` 实现 `interference_from_intervals`（由活跃区间重叠构造干涉图）与 `allocation_has_spill`（判定分配结果是否含 `Spill`），作为「是否需要溢出」结论比较的纯函数辅助；既有 `allocate_linear_scan` 行为完全冻结、本文件仅旁路提供一致性桥
    - 文件头注释标注 Poletto-Sarnak 1999（线性扫描）与一致性结论对照
    - _Requirements: 3.3, 3.5_

  - [x]* 14.2 编写属性测试：线性扫描尊重重叠
    - **Property 4: 线性扫描尊重重叠（任意两个区间重叠的变量若都为 Reg 则编号不同）**
    - **Validates: Requirements 3.4**
    - 文件 `src/codegen_infra/prop_linear_scan_overlap_test.mbt`，生成随机活跃区间集合 + `k`，调用既有 `allocate_linear_scan`，≥100 迭代

  - [x]* 14.3 编写属性测试：线性扫描与图着色无溢出一致
    - **Property 5: 线性扫描与图着色无溢出一致（最大重叠度不超过 k 的区间集，由其导出干涉图的图着色与对其本身的线性扫描在「是否需要溢出」结论上均判无需溢出）**
    - **Validates: Requirements 3.3, 3.5**
    - 文件 `src/codegen_infra/prop_linear_scan_consistency_test.mbt`，生成最大重叠度 `≤k` 的随机区间集，经 `interference_from_intervals` + `allocate_coloring_briggs` 与 `allocate_linear_scan` 并以 `allocation_has_spill` 比较，≥100 迭代

- [x] 15. 检查点 —— 确保寄存器分配（着色 / 合并 / 线性扫描一致）全部测试通过
  - 在三后端运行至此为止的测试套件；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 16. 指令选择升级 —— BURS / 最大吞噬（`burs.mbt`，旁路新增）
  - [x] 16.1 实现 BURS 代价最优 tiling 与最大吞噬
    - 在 `src/codegen_infra/burs.mbt` 新增 `CostRule`（`pattern` / `template` / `cost`，`derive(Eq, Show)`），实现 `select_burs(rules, ir)`（自底向上动态规划为每子树计算最小代价覆盖并回溯发射代价最优指令序列，运算符特化规则 `BinOp:<op>` 优先于通用 `BinOp`，覆盖每个 IR 节点无未匹配）、`tiling_cost(rules, ir)`（最优 tiling 总代价）、`max_munch(rules, ir)`（自顶向下贪心对照基线）
    - 既有 `select(Array[IselRule], IrNode)` 后序遍历语义完全冻结，与 `select_burs` 互为旁路
    - 文件头注释标注 BURS / 最大吞噬 / Appel《Modern Compiler Implementation》
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [x]* 16.2 isel 单元测试（特化优先 / select 冻结回归）
    - 在 `src/codegen_infra/burs_test.mbt` 覆盖 `BinOp:<op>` 特化规则优先于 `BinOp` 通用规则的见证，以及既有 `select` 在既有 `IselRule` 集上与 `0.1.0` 后序序列一致的回归
    - _Requirements: 11.3, 11.4_

  - [x]* 16.3 编写属性测试：指令选择覆盖完整
    - **Property 16: 指令选择覆盖完整（select_burs 所选指令序列覆盖每个 IR 节点，无未匹配）**
    - **Validates: Requirements 11.1, 11.5**
    - 文件 `src/codegen_infra/prop_burs_coverage_test.mbt`，生成随机 IR 树 + 覆盖完整的带代价规则集，≥100 迭代

  - [x]* 16.4 编写属性测试：指令选择代价最优
    - **Property 17: 指令选择代价最优（select_burs 所选覆盖方案总代价不大于穷举得到的任何其他合法覆盖方案总代价）**
    - **Validates: Requirements 11.2, 11.6**
    - 文件 `src/codegen_infra/prop_burs_optimal_test.mbt`，以穷举所有合法 tiling 的暴力解为 oracle，生成随机 IR 树 + 带代价规则集，≥100 迭代

- [x] 17. 旗舰端到端示例（`demo.mbt`，旁路新增）
  - [x] 17.1 实现完整后端流水线 demo
    - 在 `src/codegen_infra/demo.mbt` 实现 `demo_program()`（带条件分支含菱形汇合的小程序）、`PipelineStages`（`liveness` / `dom` / `ssa` / `optimized` / `coloring` / `linear_scan` / `instrs`，`derive(Show)`）与 `demo_pipeline()`：依次执行活跃性 → 支配边界最小 SSA → SCCP/GVN/DCE → 图着色与线性扫描分配 → BURS 指令选择，串起全链路并供文档与基准复用同一 `demo_program`
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_

  - [x]* 17.2 端到端 demo 单元测试（各阶段快照 / φ 数 / 无溢出 / 两法一致）
    - 在 `src/codegen_infra/demo_test.mbt` 断言：仅在支配边界放 φ 且 φ 数符合声明、`k` 充足时着色无溢出且满足干涉不变量、同一无溢出场景图着色与线性扫描溢出结论一致，以及各阶段产物与文档声明快照一致
    - _Requirements: 12.2, 12.3, 12.4, 12.5_

- [x] 18. 性能基准（`benches/codegen_bench/`，新增包）
  - [x] 18.1 创建基准包骨架
    - 新增 `benches/codegen_bench/moon.pkg` 与 `benches/codegen_bench/pkg.generated.mbti`，结构对齐既有 `benches/astar_bench`，声明对 `codegen_infra` 的依赖
    - _Requirements: 13.1_

  - [x] 18.2 实现五类工作负载基准与回归工件
    - 在 `benches/codegen_bench/codegen_bench.mbt` 实现规模化随机 CFG 生成与五类负载：支配树构造（`build_dom_tree`）、SSA 构造（`build_ssa_minimal`）、图着色分配（`allocate_coloring_briggs`）、线性扫描分配（`allocate_linear_scan`）、SCCP（`sccp`）；输出含机器标识、后端目标、图规模（节点数 / 边数 / 变量数）与计时统计的 JSON / Markdown 工件至 `benches/results/`，并接入 guard 与基线中位数比较的可审计回归报告
    - 在基准文档 / 脚本注明：运行 native 基准前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`，并记录可复现运行命令与规模参数
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

- [x] 19. 集成、文档与发布推进
  - [x] 19.1 同步公开接口签名文件
    - 重新生成并提交 `src/codegen_infra/pkg.generated.mbti`，追加全部新增 `pub` 声明（`LivenessResult` / `DomTree` / `LatticeValue` / `OptPass` / `SpillCost` / `MoveSet` / `CoalesceStrategy` / `CostRule` / `EvalResult` / `PipelineStages` 及新增函数 / 方法），既有条目保持稳定不删改
    - _Requirements: 15.1, 15.2, 15.5_

  - [x] 19.2 扩充 `README.mbt.md` 可执行文档（全链路 / 对标 / 边界）
    - 在 `src/codegen_infra/README.mbt.md` 串联升级后图着色、线性扫描、最小 SSA、SSA 析构、SCCP/GVN/DCE、升级后 isel 与端到端 demo 的可运行示例（经 `moon test *.mbt.md` 验证），并补充 paper-to-code 追溯（Chaitin 1982 / Briggs 1994、Poletto-Sarnak 1999、Cytron et al. 1991、Lengauer-Tarjan 1979、Wegman-Zadeck、BURS / 最大吞噬、Appel）、与 LLVM / GCC / Cranelift / regalloc2 的分配 / SSA / isel 对比、实现边界声明（不产真实机器码 / 不汇编链接 / 不绑定 ISA）与差异声明
    - 注明：校验 native 后端可执行文档前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 12.1, 14.1, 14.2, 14.3, 14.4, 14.5, 16.3_

  - [x] 19.3 推进 SemVer 版本字符串
    - 在 `src/codegen_infra/release.mbt` 仅更新 `codegen_infra_version` 字符串（自 `0.1.0` 起做次 / 主版本推进），保持 `release_info` / `release_info_with_gates` 语义不变
    - _Requirements: 16.5_

  - [x] 19.4 更新方向 CHANGELOG
    - 在 `src/codegen_infra/CHANGELOG.md` 追加本次旗舰深化的新增能力与版本条目
    - _Requirements: 16.5_

  - [x]* 19.5 既有 API 向后兼容回归测试
    - 在 `src/codegen_infra/compat_test.mbt` 补充回归断言：`allocate_coloring` / `allocate_linear_scan` / `interference_components` / `build_ssa` / `run_passes` / `select` 行为与 `0.1.0` 逐字段一致，核心类型字段 / 派生语义不变，`interference_components` 仍复用 `@directed.tarjan_scc`
    - _Requirements: 6.4, 10.4, 11.4, 15.1, 15.2, 15.3_

  - [x]* 19.6 发布门禁真值表测试
    - 在 `src/codegen_infra/release_test.mbt` 追加覆盖 `release_info_with_gates`：三后端测试 / 属性测试 / 可执行文档任一未过即阻止 release-ready
    - _Requirements: 16.1, 16.2, 16.6_

- [x] 20. 最终检查点 —— 确保三后端全部测试与文档校验通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行全部单元测试、17 条属性测试（各 ≥100 迭代）与 `moon test *.mbt.md`；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。任一后端输出分歧即判失败。
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- 标记 `*` 的子任务为可选测试任务（单元 / 属性 / 集成 / 门禁），可为加速 MVP 跳过，但 P1–P17 属性测试是 Requirement 16.2 的质量门禁，发布前应全部补齐。
- 每个任务引用具体需求条款（`_Requirements: X.Y_`）以保证可追溯；每条属性子任务标注 `Property N` 与 `**Validates: Requirements X.Y**`，统一以 `@infra_pbt` 实现且每条 ≥100 迭代。
- 语义保持类属性（P12 / P13 / P14）以参考解释器 `evaluate` 作为 oracle；指令选择代价最优（P17）以穷举 tiling 暴力解作为 oracle。
- **既有契约冻结**：`codegen_infra.mbt`（核心类型与六个既有函数）、`release.mbt`（除版本字符串）既有 `pub`/`pub(all)` 声明不改；新能力一律以新增 `.mbt` 文件旁路扩展；`Pass` 枚举不扩容，SCCP/GVN 经新增 `OptPass` + `run_pipeline`/`run_to_fixpoint` 旁路提供；连通分量复用 `@directed.tarjan_scc`，不重写已覆盖的图算法。
- **native 前置**：凡涉及 native 后端测试、基准运行、`README.mbt.md` 文档校验的任务（含检查点任务 3、7、11、15、20，以及 18.2、19.2），均须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "4.1", "16.1"] },
    { "id": 1, "tasks": ["5.1", "8.1", "9.1", "1.2", "1.3", "2.2", "2.3", "2.4", "4.2", "16.2", "16.3", "16.4"] },
    { "id": 2, "tasks": ["6.1", "10.1", "12.1", "5.2", "5.3", "5.4", "5.5", "8.2", "8.3", "9.2", "9.3"] },
    { "id": 3, "tasks": ["13.1", "14.1", "6.2", "6.3", "10.2", "10.3", "12.2", "12.3", "12.4"] },
    { "id": 4, "tasks": ["17.1", "18.1", "13.2", "13.3", "14.2", "14.3"] },
    { "id": 5, "tasks": ["18.2", "17.2", "19.1", "19.2", "19.3", "19.4"] },
    { "id": 6, "tasks": ["19.5", "19.6"] }
  ]
}
```
