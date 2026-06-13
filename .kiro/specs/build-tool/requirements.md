# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Build_Tool（方向六）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开 API（核心类型 `Target`、`BuildGraph`、`BuildCache`、`ParseError`、`Cycle`，以及接口 `parse_rules`/`detect_cycle`/`topo_order`/`is_dirty`/`schedule`），并在其上扩展为一套对标 GNU Make、Ninja、Bazel 与 Buck2 调度/缓存/可复现模型的旗舰级增量并行构建（图与缓存模型层）库。

本方向**显式声明实现边界**：Build_Tool 是构建系统的**图与缓存模型层**，停留在「依赖图、调度、增量缓存、溯源记录」这一抽象层，**不**执行真实文件系统读写、**不**派生构建进程、**不**调用编译器；输入指纹（mtime + 内容哈希）与动作（recipe）由调用方注入。该边界使核心算法可被属性测试穷尽校验且三后端行为一致。

旗舰目标聚焦九条主线：

- **完整规则文法**：在 `@parser_combinator` 之上实现带位置诊断的规则解析——目标与依赖、构建命令（recipe）、变量定义与展开、模式规则（`%`）、phony 目标、include 指令、注释，并保留既有最小文法兼容。
- **内容寻址增量缓存**：基于内容哈希的缓存键、动作缓存（action cache）、缓存命中跳过、缓存持久化（序列化 / 反序列化 `BuildCache`）。
- **脏传播与重建正确性**：变更沿依赖图传递闭包传播；输入未变即零重建（增量空操作幂等）；任一传递依赖变更则目标必重建，且重建集既最小又充分。
- **并行调度增强**：关键路径（critical path）感知调度、确定性调度（同输入产出确定批次序列）、jobs 并行度约束、批内目标相互独立不变量。
- **动态依赖发现**：构建动作产出的动态依赖（如头文件扫描）并入图后重新调度，并保持无环与拓扑正确。
- **可复现与 provenance**：确定性构建产物溯源记录（输入指纹 + 动作 + 输出哈希），同输入同输出可验证。
- **旗舰端到端示例**：一份贯穿文档与基准的实战构建规则集（多模块 C / MoonBit 工程依赖图），演示 `parse_rules` → 校验 / 环检测 → `schedule` → `is_dirty` 增量 → 最小重建集。
- **可解释性**：paper-to-code 可追溯（Mokhov / Mitchell / Peyton Jones《Build Systems à la Carte》的 rebuilder / scheduler 抽象、Kahn 拓扑、Tarjan 强连通分量），以及与 Make / Ninja / Bazel / Buck2 调度、缓存、可复现模型的对比与边界声明。
- **质量门禁**：完整属性测试（拓扑序合法性、调度尊重依赖且批内独立、调度确定性、增量空操作幂等、最小重建集正确性、环检测可靠性、缓存命中正确性、动态依赖加入后仍无环），三后端（`wasm-gc` / `js` / `native`）一致性，`README.mbt.md` 可执行文档扩充，以及独立 SemVer 版本推进。

本规格承袭仓库统一质量基线（见 Requirement 14），并复用 `@directed`（图资产）、`@parser_combinator`（规则解析）、`@infra_pbt`（`Gen` / `Rng` / `holds_for_all` / `round_trip`）、`@release_meta`（`DirectionRelease` / `QualityGates` / SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **Build_Tool**：本方向的增量并行构建系统（子包 `src/build_tool`），是本文档所有验收标准的主体系统。
- **Target**：构建目标，以名字唯一标识（通常为产物路径或规则名），派生 `Eq + Hash` 以作为图节点参与 `@directed` 算法。
- **BuildGraph**：构建图，由节点 `nodes : Array[Target]` 与依赖边 `edges : Array[(Target, Target)]` 构成。
- **依赖边（Dependency Edge）**：有向边 `(u, v)`，语义为「`u` 必须在 `v` 之前构建」，即 `v` 依赖 `u`。
- **BuildCache**：构建缓存，持有「基线指纹」（`recorded_mtimes` / `recorded_hashes`，上次成功构建固化）与「当前指纹」（`current_mtimes` / `current_hashes`，本次观测）。
- **输入指纹（Input Fingerprint）**：目标输入的可比对标识，由修改时间（mtime）与内容哈希组成。
- **内容哈希（Content Hash）**：对目标输入内容计算的摘要，内容相同即哈希相同。
- **内容寻址缓存（Content-Addressed Cache）**：以内容哈希（而非时间戳）为主键索引构建结果的缓存模型。
- **缓存键（Cache Key）**：唯一标识一次构建动作及其输入的键，由目标、其全部输入的内容哈希与动作指纹复合而成。
- **动作缓存（Action Cache）**：以缓存键索引「动作 → 输出」结果的缓存，命中时跳过该动作的重新执行。
- **缓存命中（Cache Hit）**：当前缓存键已存在对应记录，从而无需重建的情形；反之为**缓存未命中（Cache Miss）**。
- **recipe（构建命令）**：规则中描述如何产出目标的命令文本；本方向以不透明字符串及其指纹建模，不实际执行。
- **变量定义与展开（Variable Definition / Expansion）**：规则文法中 `name = value` 形式的变量声明，以及在目标 / 依赖 / 命令中以 `$(name)` 引用并替换为其值的处理。
- **模式规则（Pattern Rule）**：以 `%` 通配符匹配一类目标的规则（如 `%.o: %.c`），`%` 捕获的词干（stem）在依赖与命令中回填。
- **phony 目标（Phony Target）**：不对应实际产物、恒被视为需要执行的逻辑目标（如 `all`、`clean`）。
- **include 指令（Include Directive）**：在规则文本中引入另一段规则源以合并入同一构建图的指令。
- **ParseError**：规则解析错误，携带人类可读信息 `message` 与 1 起始行号 `line`（旗舰深化追加列号与诊断类别）。
- **Cycle**：环检测结果，承载构成依赖环的目标序列 `nodes`。
- **拓扑序（Topological Order）**：节点的线性排列，使每个目标排在其全部依赖之后；由 `topo_order` 复用 `@directed.topological_sort`（Kahn 算法）计算。
- **拓扑分层（Topological Layering）**：逐层剥离入度为 0 目标的过程，每层目标相互无依赖。
- **并行批次（Parallel Batch）**：`schedule` 产出的一组可并行执行、相互无依赖的目标。
- **jobs（并行度）**：调度的并行宽度上限；`jobs > 0` 时每个批次的目标数不超过 `jobs`，`jobs <= 0` 视为不限并行度。
- **批内独立（Intra-Batch Independence）**：同一并行批次内任意两目标之间不存在依赖边的不变量。
- **关键路径（Critical Path）**：构建图中从源到汇的最长依赖链，决定理论最短完成层数（关键路径长度）。
- **确定性调度（Deterministic Scheduling）**：对同一构建图与同一 jobs，`schedule` 产出逐元素一致的批次序列。
- **脏检查（Dirty Check）**：由 `is_dirty` 依据当前指纹与基线指纹比对，判定单个目标是否需要重建。
- **脏传播（Dirty Propagation）**：将「脏」目标沿依赖边向其下游传递目标传播，使受影响目标一并标记为脏的过程。
- **传递闭包（Transitive Closure）**：从某目标集合出发，沿依赖边可达的全部下游目标集合。
- **最小重建集（Minimal Rebuild Set）**：在给定脏输入集合下，需要且仅需要重建的目标集合——既包含全部受变更传递影响的目标（充分），又不包含任何未受影响的目标（最小）。
- **增量空操作（Incremental No-Op）**：当无任何输入变更时，重建集为空、构建图状态不变的幂等情形。
- **动态依赖（Dynamic Dependency）**：构建动作执行后才发现的依赖（如编译时扫描出的头文件），需并入图并重新调度。
- **provenance（溯源记录）**：一次构建的可复现记录，含目标、输入指纹、动作指纹与输出内容哈希。
- **可复现构建（Reproducible Build）**：相同输入指纹与相同动作必产出相同输出哈希与相同溯源记录的性质。
- **rebuilder / scheduler**：《Build Systems à la Carte》对构建系统的两维分解——rebuilder 决定「是否重建某目标」，scheduler 决定「以何顺序构建」。
- **@directed**：仓库共享有向图资产包，提供 `topological_sort`（Kahn）、`tarjan_scc`、`condensation` 等算法。
- **@parser_combinator**：仓库共享解析器组合子包，本方向用其实现带位置诊断的规则文法解析。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen` / `Rng` / `holds_for_all` / `round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease` / `QualityGates` / SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：完整规则文法解析（基于 @parser_combinator）

**用户故事（User Story）：** 作为编写构建规则的开发者，我想要一个支持目标、依赖、命令、变量、模式规则、phony 与 include 的完整规则文法，以便我能以接近主流构建工具的表达力描述工程的构建依赖。

#### 验收标准（Acceptance Criteria）

1. WHEN 接收到形如 `target: dep1 dep2` 的规则行，THE Build_Tool SHALL 将 `target` 登记为节点、对每个依赖生成依赖边 `(dep, target)`，并把目标与依赖按首次出现去重登记为图节点。
2. WHERE 规则携带构建命令（recipe），THE Build_Tool SHALL 将该命令文本作为该目标的不透明动作记录，并保留其原始文本以供动作指纹计算。
3. WHERE 规则文本包含形如 `name = value` 的变量定义，THE Build_Tool SHALL 在解析后续目标、依赖与命令中出现的 `$(name)` 引用时，将其展开为对应变量值。
4. WHERE 规则为形如 `%.o: %.c` 的模式规则，THE Build_Tool SHALL 以 `%` 捕获词干（stem）并在生成具体目标的依赖与命令时回填该词干。
5. WHERE 规则声明 phony 目标，THE Build_Tool SHALL 将该目标标记为 phony，使其脏检查恒判定为需要重建。
6. WHEN 解析遇到 include 指令，THE Build_Tool SHALL 将被引入的规则源合并入同一构建图，且合并后的节点去重规则与单文件解析一致。
7. WHEN 规则行以 `#` 起始或为空行，THE Build_Tool SHALL 将该行作为注释或空白忽略而不产生节点或边。

---

### Requirement 2：带位置诊断与最小文法向后兼容

**用户故事（User Story）：** 作为调试构建规则的开发者，我想要带精确位置的解析诊断，并保证既有最小规则文法仍可解析，以便我能快速定位语法错误且升级后旧规则文件无需改写。

#### 验收标准（Acceptance Criteria）

1. IF 某规则行缺少 `:` 依赖分隔符，THEN THE Build_Tool SHALL 返回携带该行 1 起始行号的 `ParseError`，且不产出部分构造的构建图。
2. IF 某规则行 `:` 左侧的目标名为空，THEN THE Build_Tool SHALL 返回携带该行 1 起始行号与「目标名为空」诊断的 `ParseError`。
3. WHEN 经 `@parser_combinator` 解析失败，THE Build_Tool SHALL 在 `ParseError` 中提供失败位置（行号，旗舰深化追加列号）与人类可读的期望描述。
4. WHEN 接收到既有最小文法（仅 `target: dep1 dep2`、注释与空行）的规则文本，THE Build_Tool SHALL 产出与 `0.1.0` 骨架 `parse_rules` 逐字段一致的 `BuildGraph`。
5. FOR ALL 由生成器产生的合法最小文法规则文本，THE Build_Tool SHALL 保证完整文法解析器与既有最小文法解析在节点序列与依赖边集合上产生一致结果（向后兼容一致性，以 PBT 验证）。

---

### Requirement 3：内容寻址增量缓存与动作缓存

**用户故事（User Story）：** 作为追求快速重建的开发者，我想要以内容哈希为键的缓存与动作缓存，以便在输入内容未变时跳过对应目标的重建。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 为每个目标计算由其全部输入内容哈希与动作指纹复合而成的缓存键。
2. WHEN 某目标的当前缓存键在动作缓存中已存在对应记录，THE Build_Tool SHALL 判定该目标缓存命中并将其排除出重建集。
3. IF 某目标的当前缓存键在动作缓存中不存在对应记录，THEN THE Build_Tool SHALL 判定该目标缓存未命中并将其纳入重建集。
4. WHEN 两个目标具有相同的输入内容哈希与相同的动作指纹，THE Build_Tool SHALL 为二者计算相同的缓存键。
5. IF 目标输入的内容哈希发生变化而修改时间未变，THEN THE Build_Tool SHALL 仍判定缓存键变化并将该目标纳入重建集。
6. FOR ALL 由生成器产生的目标输入与动作，THE Build_Tool SHALL 保证缓存键计算确定且对内容哈希敏感：相同输入产相同键、任一输入内容哈希改变即产不同键（缓存键正确性，以 PBT 验证）。

---

### Requirement 4：缓存持久化（序列化 / 反序列化）

**用户故事（User Story）：** 作为跨多次构建会话工作的开发者，我想要把构建缓存持久化并在下次会话恢复，以便增量优势能跨进程保留。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 提供将 `BuildCache` 序列化为可持久化文本表示的能力。
2. THE Build_Tool SHALL 提供从该文本表示反序列化重建 `BuildCache` 的能力。
3. IF 反序列化输入格式非法或字段缺失，THEN THE Build_Tool SHALL 返回携带诊断信息的错误，而不产出部分构造的缓存。
4. FOR ALL 由生成器产生的 `BuildCache`，THE Build_Tool SHALL 满足往返性质：序列化后再反序列化得到与原缓存逐字段一致的 `BuildCache`（缓存往返一致性，以 PBT 验证）。

---

### Requirement 5：脏传播与最小重建集计算

**用户故事（User Story）：** 作为修改了部分源文件的开发者，我想要构建系统沿依赖图传播变更并只重建受影响目标，以便我获得既正确又最快的增量构建。

#### 验收标准（Acceptance Criteria）

1. WHEN 给定一组脏输入目标，THE Build_Tool SHALL 沿依赖边将「脏」状态传播至其全部传递下游目标，得到受影响目标集合。
2. THE Build_Tool SHALL 计算最小重建集，使其恰好等于脏输入目标及其传递下游目标的并集。
3. IF 某目标不在任一脏输入目标的传递下游中且自身未变，THEN THE Build_Tool SHALL 将该目标排除出最小重建集。
4. WHEN 计算出最小重建集后，THE Build_Tool SHALL 仅对重建集内目标按拓扑序产出重建调度，重建集外目标不参与本次重建调度。
5. FOR ALL 由生成器产生的无环构建图与脏输入子集，THE Build_Tool SHALL 保证最小重建集**充分**：每个受变更传递影响的目标都被包含（充分性，以 PBT 验证）。
6. FOR ALL 由生成器产生的无环构建图与脏输入子集，THE Build_Tool SHALL 保证最小重建集**最小**：每个被包含的目标都可由某脏输入沿依赖边到达（最小性，以 PBT 验证）。

---

### Requirement 6：增量空操作幂等与重建充分性

**用户故事（User Story）：** 作为重复运行构建的开发者，我想要在无任何变更时构建为零重建，并在依赖变更时目标必被重建，以便增量构建既不做多余工作也不遗漏。

#### 验收标准（Acceptance Criteria）

1. WHEN 某目标的当前指纹与基线指纹完全一致（mtime 与内容哈希均相同），THE Build_Tool SHALL 经 `is_dirty` 判定该目标为干净（返回 `false`）。
2. IF 某目标的当前指纹缺失或与基线指纹不一致，THEN THE Build_Tool SHALL 经 `is_dirty` 判定该目标为脏（返回 `true`）。
3. WHEN 一次成功构建后所有目标的当前指纹被固化为基线且无后续输入变更，THE Build_Tool SHALL 在再次计算重建集时产出空集（增量空操作）。
4. WHEN 某目标的任一传递依赖的输入指纹相对基线发生变化，THE Build_Tool SHALL 将该目标纳入重建集。
5. FOR ALL 由生成器产生的构建图与缓存状态，THE Build_Tool SHALL 保证在无输入变更时连续两次计算的重建集均为空且相等（增量空操作幂等，以 PBT 验证）。

---

### Requirement 7：并行调度增强（关键路径感知与确定性）

**用户故事（User Story）：** 作为在多核环境构建的开发者，我想要确定性、关键路径感知且尊重并行度上限的调度，以便构建既可复现又能逼近理论最短完成时间。

#### 验收标准（Acceptance Criteria）

1. WHEN 对无环构建图调度，THE Build_Tool SHALL 按拓扑分层产出并行批次，使任一目标所在批次的序号大于其全部依赖所在批次的序号。
2. WHERE `jobs > 0`，THE Build_Tool SHALL 将每个并行批次的目标数限制为不超过 `jobs`，超宽的层被切分为多个批宽不超过 `jobs` 的批次。
3. WHERE `jobs <= 0`，THE Build_Tool SHALL 视为不限并行度，将每个拓扑层整层作为一个批次。
4. THE Build_Tool SHALL 计算构建图的关键路径长度，并据此报告在不限并行度下完成构建所需的最小批次层数。
5. FOR ALL 由生成器产生的无环构建图，THE Build_Tool SHALL 保证调度尊重依赖：批次展平后每个目标排在其全部依赖之后（拓扑不变量，以 PBT 验证）。
6. FOR ALL 由生成器产生的无环构建图，THE Build_Tool SHALL 保证批内独立：同一批次内任意两目标之间不存在依赖边（批内独立不变量，以 PBT 验证）。
7. FOR ALL 由生成器产生的无环构建图与同一 jobs，THE Build_Tool SHALL 保证确定性调度：两次调度产出逐元素一致的批次序列（调度确定性，以 PBT 验证）。

---

### Requirement 8：动态依赖发现与重新调度

**用户故事（User Story）：** 作为构建依赖在动作执行后才完全确定的开发者，我想要系统把动态发现的依赖并入图并重新调度，以便头文件等隐式依赖被正确纳入构建顺序。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用方为某目标提供构建动作产出的动态依赖集合，THE Build_Tool SHALL 为每个动态依赖向构建图追加依赖边并登记缺失的节点。
2. WHEN 动态依赖并入构建图后，THE Build_Tool SHALL 在更新后的图上重新计算调度批次。
3. IF 追加的动态依赖会引入依赖环，THEN THE Build_Tool SHALL 经 `detect_cycle` 报告构成环的目标序列并拒绝产出重建调度。
4. FOR ALL 由生成器产生的无环构建图与不引入环的动态依赖追加，THE Build_Tool SHALL 保证并入后的图仍无环，且重新调度仍满足拓扑不变量（动态依赖拓扑保持，以 PBT 验证）。

---

### Requirement 9：可复现构建与 provenance 溯源

**用户故事（User Story）：** 作为需要审计与复现构建的开发者，我想要每次构建记录输入指纹、动作与输出哈希的溯源信息，以便相同输入可验证地得到相同输出。

#### 验收标准（Acceptance Criteria）

1. WHEN 某目标被构建，THE Build_Tool SHALL 产出一条溯源记录，包含目标名、其全部输入的内容哈希、动作指纹与输出内容哈希。
2. WHEN 两次构建具有相同的输入内容哈希与相同的动作指纹，THE Build_Tool SHALL 产出相同的输出内容哈希与逐字段一致的溯源记录。
3. IF 输入内容哈希或动作指纹任一不同，THEN THE Build_Tool SHALL 在溯源记录中体现该差异并允许据此区分两次构建。
4. FOR ALL 由生成器产生的目标输入与动作，THE Build_Tool SHALL 保证溯源记录确定：相同输入与动作恒产生逐字段一致的溯源记录（可复现性，以 PBT 验证）。

---

### Requirement 10：旗舰端到端示例 —— 多模块工程依赖图

**用户故事（User Story）：** 作为评估该库能力的开发者，我想要一份贯穿文档与基准的实战构建规则集，以便我能看到解析、环检测、调度、增量与最小重建集在真实工程结构中的端到端用法。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 提供一份多模块 C / MoonBit 工程的实战构建规则集示例，覆盖源文件、目标文件、库与顶层可执行产物的依赖层级。
2. WHEN 对该示例规则集调用 `parse_rules`，THE Build_Tool SHALL 产出与示例文档所声明一致的节点集合与依赖边集合。
3. WHEN 对该示例构建图调用 `detect_cycle`，THE Build_Tool SHALL 报告该无环工程图不含依赖环（返回 `None`）。
4. WHEN 对该示例构建图调用 `schedule`，THE Build_Tool SHALL 产出满足拓扑不变量与批内独立的并行批次序列。
5. WHEN 对该示例在单个源文件变更场景计算最小重建集，THE Build_Tool SHALL 产出仅含该源文件传递下游目标的重建集，并据此演示增量重建相对全量重建的目标数缩减。

---

### Requirement 11：性能基准（benches/）

**用户故事（User Story）：** 作为关心构建性能的开发者，我想要可复现的基准证据覆盖大规模 DAG 的核心计算，以便我能确认拓扑、调度、脏检查与最小重建集的扩展趋势并防止回归。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 在 `benches/` 下提供构建基准包，覆盖大规模有向无环依赖图上的拓扑排序、并行调度、脏检查与最小重建集计算四类工作负载。
2. WHEN 运行基准，THE Build_Tool SHALL 输出包含机器标识、后端目标、图规模（节点数与边数）与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE Build_Tool SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的回归失败报告。
4. WHEN 运行 native 后端基准或测试，THE Build_Tool SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Build_Tool SHALL 在基准文档中记录可复现运行命令与图规模参数，以保证基准可被独立重跑。

---

### Requirement 12：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键算法可追溯到源论文并与主流构建系统对比，以便我能理解设计依据、取舍与实现边界。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 在文档中将增量重建与调度的两维分解（rebuilder / scheduler）追溯到 Mokhov、Mitchell 与 Peyton Jones 的《Build Systems à la Carte》。
2. THE Build_Tool SHALL 在文档中将拓扑序计算追溯到 Kahn 算法、将环检测追溯到 Tarjan 强连通分量算法，并标明二者复用自 `@directed`。
3. THE Build_Tool SHALL 在文档中提供与 GNU Make、Ninja、Bazel 与 Buck2 的对比，覆盖调度策略、缓存模型（时间戳 vs 内容寻址）与可复现性差异。
4. THE Build_Tool SHALL 在文档中显式声明实现边界：本方向停留在图与缓存模型层，不执行真实文件系统读写、不派生构建进程、不调用编译器。
5. WHERE 本库的语义与所对标构建系统存在差异，THE Build_Tool SHALL 显式声明该差异及其理由，而非隐式留白。

---

### Requirement 13：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有构建图与调用方在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 保留既有公开类型 `Target`、`BuildGraph`、`BuildCache`、`ParseError`、`Cycle` 及其现有公开方法的签名与语义。
2. THE Build_Tool SHALL 保留既有接口 `parse_rules`、`detect_cycle`、`topo_order`、`is_dirty`、`schedule` 的现有公开签名与行为。
3. THE Build_Tool SHALL 复用 `@directed` 的 `topological_sort`、`tarjan_scc` 与 `condensation` 作为拓扑序与环检测的底层算法，而不重写已被覆盖的图算法。
4. THE Build_Tool SHALL 复用 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all` / `round_trip` 作为全部新增属性测试的模板。
5. WHERE 新增能力需要扩展行为，THE Build_Tool SHALL 以新增 API 的方式提供，而不破坏既有 API 的调用方（既有 `0.1.0` 契约冻结、新能力旁路扩展）。

---

### Requirement 14：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Build_Tool SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Build_Tool SHALL 为本规格的核心正确性属性（拓扑序合法性、调度尊重依赖、批内独立、调度确定性、增量空操作幂等、最小重建集充分性与最小性、环检测可靠性、缓存键正确性、缓存往返一致性、动态依赖拓扑保持、可复现性）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE Build_Tool SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖完整规则文法、增量缓存、最小重建集、增强调度与旗舰端到端示例，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE Build_Tool SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Build_Tool SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. IF 本方向的三后端测试、属性测试或可执行文档校验未通过，THEN THE Build_Tool SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
