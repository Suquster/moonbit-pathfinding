# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **DST_Framework（方向八：确定性仿真测试框架，Deterministic Simulation Testing）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开 API（确定性随机源 `Rng`（xorshift64）与 `rng_new`/`next`/`next_below`；核心类型 `Task`/`Event`/`FaultKind`/`FaultPolicy`/`Scenario`/`SimStatus`/`SimResult`/`Sim`；流水线接口 `Sim::new`/`step`/`inject_fault`、`run(seed, scenario)`、`replay(seed, trace)`；既有 `prop_replay` 属性测试与 `release_info`/`release_info_with_gates` 发布门禁），并在其上扩展为一套对标 FoundationDB 确定性仿真、TigerBeetle VOPR、`madsim`/`turmoil` 与 Jepsen/Knossos 的旗舰级确定性分布式系统测试框架。

本方向的核心价值在骨架阶段已确立并必须在深化中无损保持：**同种子 → 同执行**——相同种子的两次运行产生逐事件一致的调度序列与相同终态；「`seed` + `trace`」构成可重放凭据，`replay` 复现完全相同的结果。

旗舰目标聚焦以下主线（均为本规格的验收范围）：

- **离散事件仿真升级**：引入逻辑时钟 / 虚拟时间、带时间戳的有序事件队列与任务间消息传递（`send` / `deliver` 事件），并在新模型下保持确定性与可重放。
- **丰富故障模型**：在既有崩溃 `Crash` / 延迟 `Delay` / 丢弃 `Drop` 之上增加网络分区（partition）、消息重排 / 重复（reorder / duplicate）、时钟偏移（clock skew），并以可选方式支持拜占庭（byzantine）故障；所有注入点确定且可重放。
- **失败用例收缩**：对失败的「种子 / 场景 / 故障序列」做最小化（delta debugging / QuickCheck shrinking），产出仍能复现失败的最小反例，收缩单调且终止。
- **调度空间探索**：在深度上界内对任务交错做有界穷尽枚举（bounded exhaustive interleaving），与确定性随机搜索互补。
- **DPOR 偏序约简**：以动态偏序约简（Flanagan & Godefroid 2005）剪枝等价交错，保证每个 Mazurkiewicz 迹等价类至少被探索一次。
- **运行时不变量与一致性检查**：在仿真过程中对全局状态断言不变量，并以可选方式支持 Jepsen 风格历史的线性一致性检查（Wing & Gong 线性化点）。
- **轨迹持久化**：`SimResult` / `trace` 的序列化与反序列化，支持跨会话重放（序列化往返 + 重放保真）。
- **旗舰端到端 demo**：一份贯穿文档与基准的分布式场景（多副本日志复制 / 键值存储），注入网络分区与崩溃触发失败，收缩到最小反例，重放复现并校验不变量。
- **性能基准**：`benches/` 覆盖大规模场景的 `run` / `replay` / 穷尽探索 / DPOR / 收缩，含回归 guard，native 后端前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
- **可解释性**：paper-to-code 可追溯与开源对标，并显式声明实现边界（纯内存确定性模型，不接入真实网络 / 时间 / 线程）。
- **质量门禁**：完整属性测试、三后端一致性、`README.mbt.md` 可执行文档扩充、自 `0.1.0` 起的独立 SemVer 推进与 `release_info_with_gates` 门禁。

本规格承袭仓库统一质量基线（见 Requirement 13），并复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **DST_Framework**：本方向的确定性仿真测试框架系统（子包 `src/dst`），是本文档所有验收标准的主体系统。
- **确定性仿真测试（Deterministic Simulation Testing, DST）**：在受控的纯内存确定性环境中，以单一种子驱动可重现的分布式系统执行，并据此发现并复现缺陷的测试方法。
- **种子（Seed）**：驱动确定性随机源的 `UInt64` 初值；相同种子产生逐位一致的随机序列与逐事件一致的调度序列。
- **Rng**：确定性随机源（采用 xorshift64：仅移位 + 异或，三后端逐位一致），提供 `rng_new`/`next`/`next_below`。
- **Task**：仿真任务，确定性调度的最小单元，含 `id`（唯一标识）与 `name`（可读名称）。
- **Event**：仿真事件，调度过程的可观测、可重放轨迹元素（既有 `Scheduled`/`Faulted`/`Completed`，深化中扩展时间戳与消息事件）。
- **trace**：事件轨迹，一次运行中按发生顺序记录的事件序列；与种子共同构成可重放凭据。
- **FaultKind**：故障类型枚举，既有 `Crash`/`Delay`/`Drop`，深化中扩展 `Partition`/`Reorder`/`Duplicate`/`ClockSkew` 及可选 `Byzantine`。
- **FaultPolicy**：故障策略，描述「在 `at_step` 对任务 `task_id` 注入 `kind` 故障」的确定性注入点。
- **Scenario**：仿真场景，一次 `run` 的完整输入描述，含任务集 `tasks`、故障策略集 `faults` 与步数上限 `max_steps`。
- **SimStatus**：仿真终态，`Completed`（正常完成）或 `Failed(reason)`（失败并携带可读原因）。
- **SimResult**：仿真结果，含 `seed`、`trace` 与 `status`，承载可重放凭据。
- **Sim**：仿真状态机，承载随机源 `rng`、待调度任务 `tasks` 与已产生事件轨迹 `trace`。
- **逻辑时钟 / 虚拟时间（Logical Clock / Virtual Time）**：仿真内部推进的离散时间度量，与真实墙钟无关，使带时间的事件可按时间排序且可重放。
- **离散事件仿真（Discrete-Event Simulation, DES）**：以「事件按时间戳出队、处理后产生未来事件入队」为核心循环的仿真模型。
- **事件队列（Event Queue）**：按「（时间戳，确定性次序键）」全序排列的待处理事件优先队列。
- **消息传递（Message Passing）**：任务间通过 `send`（发出消息）与 `deliver`（投递消息）事件通信的机制，投递受网络故障模型影响。
- **因果序（Causal Order）**：消息的投递事件不早于其发送事件、且同一对端的消息按其确定的投递规则保持的偏序关系。
- **网络分区（Partition）**：将任务集合划分为互不可达分组、阻断跨分组消息投递的故障。
- **消息重排（Reorder）**：改变同一对端之间消息投递顺序的故障。
- **消息重复（Duplicate）**：使同一消息被投递多于一次的故障。
- **时钟偏移（Clock Skew）**：对某任务的本地逻辑时钟施加确定性偏移量的故障。
- **拜占庭故障（Byzantine Fault）**：任务产生任意 / 不一致行为（如发送相互矛盾的消息）的故障，作为可选能力。
- **故障注入点确定性（Deterministic Injection Point）**：故障在「步序号 + 目标任务」维度上被精确定位，使同一种子下故障在同一位置触发。
- **失败用例收缩（Shrinking / Delta Debugging）**：在保持失败可复现的前提下，将反例（种子 / 场景 / 故障序列）缩减到更小规模的过程。
- **最小反例（Minimal Counterexample）**：经收缩后无法在所采用的收缩算子下进一步缩小且仍能复现失败的反例。
- **收缩单调性（Shrink Monotonicity）**：收缩过程的每一步接受的候选都仍复现原失败。
- **收缩终止性（Shrink Termination）**：收缩在有限步内停止（候选规模严格递减且有下界）。
- **调度空间探索（Schedule-Space Exploration）**：系统性地枚举任务交错（调度序列）以覆盖不同执行路径的过程。
- **有界穷尽交错（Bounded Exhaustive Interleaving）**：在给定深度上界内枚举全部可达调度序列的探索策略。
- **交错（Interleaving）**：并发任务的一种具体执行顺序（调度序列）。
- **DPOR（动态偏序约简，Dynamic Partial-Order Reduction）**：Flanagan & Godefroid 2005 提出的、在运行时基于依赖关系剪枝等价交错的算法。
- **Mazurkiewicz 迹（Mazurkiewicz Trace）**：在独立（可交换）事件的等价关系下，一组互为等价的交错所构成的等价类。
- **依赖关系（Dependency Relation）**：两事件不可交换（顺序影响结果）的二元关系；不依赖即独立。
- **持久集（Persistent Set）**：DPOR 在每个状态选择探索的、足以覆盖所有非等价后继的转移子集。
- **运行时不变量（Runtime Invariant）**：在仿真任意可观测状态上必须成立的布尔断言。
- **不变量违反（Invariant Violation）**：某可观测状态使不变量为假的情形，应被检出并报告为失败。
- **线性一致性（Linearizability）**：并发历史可被重排为某个保持实时先后序的合法顺序历史的一致性条件（Herlihy & Wing 1990）。
- **线性化点（Linearization Point）**：操作在历史中表现为瞬时生效的时刻（Wing & Gong 检查的依据）。
- **历史（History）**：操作的调用 / 返回事件按时间排列的序列，供一致性检查器分析。
- **轨迹持久化（Trace Persistence）**：将 `SimResult` / `trace` 编码为可存储文本并能无损解码的能力。
- **序列化往返（Serialization Round-Trip）**：`deserialize(serialize(x))` 与 `x` 逐字段一致的性质。
- **跨会话重放（Cross-Session Replay）**：从持久化的种子与轨迹在新进程 / 新会话中复现相同终态的能力。
- **回归 guard（Regression Guard）**：将新基准结果与已记入基线比较，超出容差即报失败的机制。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：确定性内核保持与逻辑时钟扩展

**用户故事（User Story）：** 作为依赖可重现执行的分布式系统测试者，我想要在引入虚拟时间后仍保持「同种子 → 同执行」，以便我能在更丰富的时间模型下继续获得逐事件一致的可重放保证。

#### 验收标准（Acceptance Criteria）

1. WHEN 以同一种子与同一场景两次调用 `run`，THE DST_Framework SHALL 产出逐事件一致的事件轨迹与相同终态。
2. THE DST_Framework SHALL 以单调不减的逻辑时钟推进虚拟时间，使每个产出事件携带其发生的逻辑时间戳。
3. WHEN 在某一逻辑时间存在多个待处理事件，THE DST_Framework SHALL 以「（逻辑时间戳，任务 id 升序，确定性次序键）」的全序确定其处理顺序。
4. THE DST_Framework SHALL 仅由 `Rng`（xorshift64）驱动一切随机选择，使随机决策在 `wasm-gc`、`js`、`native` 三后端逐位一致。
5. FOR ALL 由生成器产生的种子与场景，THE DST_Framework SHALL 保证两次 `run` 的事件轨迹与终态逐字段一致（同种子确定性，以 PBT 验证）。
6. FOR ALL 由生成器产生的场景，THE DST_Framework SHALL 保证逻辑时间戳沿事件轨迹单调不减（虚拟时间单调性，以 PBT 验证）。

---

### Requirement 2：离散事件仿真升级 —— 事件队列与消息传递

**用户故事（User Story）：** 作为建模真实分布式协议的开发者，我想要带时间的事件队列与任务间消息传递，以便我能表达「发送—投递」的异步通信并观察其确定性时序。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 维护一个按「（逻辑时间戳，确定性次序键）」全序排列的事件队列，并以「取出队首事件、处理后将新产生事件入队」为核心仿真循环。
2. WHEN 一个任务发出消息，THE DST_Framework SHALL 记录一个 `send` 事件并安排该消息在确定的未来逻辑时间产生对应 `deliver` 事件。
3. WHEN 一个消息被投递，THE DST_Framework SHALL 记录一个携带源任务、目标任务与逻辑时间戳的 `deliver` 事件。
4. THE DST_Framework SHALL 在无任何故障的场景下保证每条已发送消息的 `deliver` 事件的逻辑时间戳严格大于其 `send` 事件的逻辑时间戳。
5. WHEN 事件队列为空或达到 `max_steps` 上限，THE DST_Framework SHALL 终止仿真循环并产出对应终态。
6. FOR ALL 由生成器产生的、无丢弃 / 无分区故障的消息收发场景，THE DST_Framework SHALL 保证每条已发送消息恰被投递一次且其投递不早于发送（因果序保持，以 PBT 验证）。

---

### Requirement 3：丰富故障模型

**用户故事（User Story）：** 作为压力测试容错协议的开发者，我想要网络分区、消息重排 / 重复与时钟偏移等故障，以便我能在确定且可重放的注入点暴露协议在恶劣条件下的缺陷。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 在保留既有 `Crash`、`Delay`、`Drop` 故障类型语义不变的前提下，新增 `Partition`、`Reorder`、`Duplicate` 与 `ClockSkew` 故障类型。
2. WHILE 一个 `Partition` 故障在其生效区间内有效，THE DST_Framework SHALL 阻断被划分到不同分组的任务之间的消息投递。
3. WHEN 一个 `Reorder` 故障命中其注入点，THE DST_Framework SHALL 以确定性方式改变受影响消息之间的投递顺序。
4. WHEN 一个 `Duplicate` 故障命中其注入点，THE DST_Framework SHALL 使受影响消息被投递两次，并为每次投递记录独立的 `deliver` 事件。
5. WHEN 一个 `ClockSkew` 故障作用于某任务，THE DST_Framework SHALL 对该任务的本地逻辑时钟施加由故障策略确定的偏移量。
6. WHERE 启用拜占庭故障，THE DST_Framework SHALL 允许受影响任务向不同对端发送相互矛盾的消息内容，且该行为由种子确定。
7. FOR ALL 由生成器产生的含故障场景，THE DST_Framework SHALL 保证同一种子下故障在同一「步序号 + 目标任务」注入点触发，使含故障运行可被精确重放（故障注入确定性，以 PBT 验证）。

---

### Requirement 4：失败用例收缩（shrinking / delta debugging）

**用户故事（User Story）：** 作为诊断失败的开发者，我想要把触发失败的场景与故障序列自动最小化，以便我能在最小反例上快速定位根因。

#### 验收标准（Acceptance Criteria）

1. WHEN 提供一个使运行失败的场景，THE DST_Framework SHALL 产出一个仍使运行失败且规模不大于原场景的收缩后场景。
2. THE DST_Framework SHALL 以「移除任务、移除故障策略、缩减 `max_steps`」等保持失败的收缩算子缩减反例规模。
3. WHILE 收缩进行，THE DST_Framework SHALL 仅接受仍能复现原失败的候选，并丢弃任何使运行转为 `Completed` 的候选。
4. WHEN 在当前收缩算子下无法找到更小的仍失败候选，THE DST_Framework SHALL 停止并返回当前最小反例。
5. IF 输入场景并不失败，THEN THE DST_Framework SHALL 报告无可收缩的反例，而不返回任意场景。
6. FOR ALL 由生成器产生的失败场景，THE DST_Framework SHALL 保证收缩结果仍使运行失败（收缩保真，以 PBT 验证）。
7. FOR ALL 由生成器产生的失败场景，THE DST_Framework SHALL 保证收缩在有限步内终止且收缩结果的规模不大于输入（收缩终止与单调，以 PBT 验证）。

---

### Requirement 5：调度空间探索 —— 有界穷尽交错

**用户故事（User Story）：** 作为追求高覆盖的测试者，我想要在深度上界内穷尽枚举任务交错，以便我能系统性地覆盖确定性随机搜索可能遗漏的执行路径。

#### 验收标准（Acceptance Criteria）

1. WHEN 给定一个场景与深度上界 `depth`，THE DST_Framework SHALL 枚举深度不超过 `depth` 的全部可达任务交错并对每个交错执行一次仿真。
2. THE DST_Framework SHALL 为穷尽探索提供入口，使调用方能在不修改既有 `run` 语义的情况下选择启用交错枚举。
3. IF 任一被枚举的交错使不变量违反或运行失败，THEN THE DST_Framework SHALL 报告该失败交错对应的可重放种子与轨迹。
4. WHEN 探索在 `depth` 上界内完成，THE DST_Framework SHALL 报告已探索交错的计数，使覆盖范围可审计。
5. FOR ALL 由生成器产生的小规模场景与深度上界，THE DST_Framework SHALL 保证穷尽探索枚举到该深度内每一个可达交错（探索完整性，以 PBT 验证）。

---

### Requirement 6：DPOR 偏序约简

**用户故事（User Story）：** 作为受组合爆炸困扰的测试者，我想要动态偏序约简剪除等价交错，以便我能在不漏报缺陷的前提下显著减少需探索的调度数量。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 以动态偏序约简（Flanagan & Godefroid 2005）基于事件依赖关系剪枝相互等价的交错。
2. THE DST_Framework SHALL 将作用于不同任务且无消息因果关联的事件判定为独立（可交换），将作用于同一任务或存在消息因果关联的事件判定为依赖。
3. WHEN 对某场景运行 DPOR 探索，THE DST_Framework SHALL 对每个 Mazurkiewicz 迹等价类至少探索一个代表性交错。
4. IF 存在任一使不变量违反或运行失败的交错，THEN THE DST_Framework SHALL 在 DPOR 探索中检出该失败（约简不漏报缺陷）。
5. FOR ALL 由生成器产生的小规模场景，THE DST_Framework SHALL 保证 DPOR 探索与有界穷尽探索报告相同的「是否存在失败交错」结论（DPOR 可靠性，以 PBT 验证）。
6. FOR ALL 由生成器产生的小规模场景，THE DST_Framework SHALL 保证 DPOR 所探索的交错数量不超过有界穷尽探索的交错数量（约简有效性，以 PBT 验证）。

---

### Requirement 7：运行时不变量与一致性检查

**用户故事（User Story）：** 作为验证协议正确性的开发者，我想要在仿真中断言全局不变量并可选地检查线性一致性，以便我能在缺陷发生的当步即将其捕获。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 允许调用方为场景附加一组运行时不变量，每个不变量是对可观测全局状态的布尔断言。
2. WHILE 仿真推进，THE DST_Framework SHALL 在每个可观测状态上求值全部已附加的不变量。
3. IF 任一不变量在某状态求值为假，THEN THE DST_Framework SHALL 以 `Failed` 终止运行，并在原因中标识被违反的不变量与发生的逻辑时间戳。
4. WHERE 启用线性一致性检查，THE DST_Framework SHALL 依据操作历史与线性化点（Wing & Gong）判定该历史是否线性一致。
5. WHEN 一个操作历史不可线性化，THE DST_Framework SHALL 报告该历史为非线性一致，并给出导致冲突的操作。
6. FOR ALL 由生成器产生的、必然违反某不变量的场景，THE DST_Framework SHALL 保证该违反被检出并以 `Failed` 终态报告（不变量违反必被检出，以 PBT 验证）。

---

### Requirement 8：轨迹持久化与跨会话重放

**用户故事（User Story）：** 作为需要归档与共享失败用例的开发者，我想要把仿真结果序列化为可存储文本并能无损还原，以便我能在另一会话中精确重放同一失败。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 提供将 `SimResult`（含 `seed`、`trace`、`status`）序列化为文本表示的能力。
2. THE DST_Framework SHALL 提供从该文本表示反序列化重建 `SimResult` 的能力。
3. WHEN 一个序列化文本被反序列化，THE DST_Framework SHALL 重建与原 `SimResult` 逐字段一致的值。
4. WHEN 以反序列化得到的种子与轨迹调用 `replay`，THE DST_Framework SHALL 复现与原运行逐字段一致的终态。
5. IF 序列化文本格式非法或损坏，THEN THE DST_Framework SHALL 返回携带原因的解析失败，而不产生部分构造的 `SimResult`。
6. FOR ALL 由生成器产生的 `SimResult`，THE DST_Framework SHALL 满足序列化往返性质：`deserialize(serialize(r))` 与 `r` 逐字段一致（序列化往返，以 PBT 验证）。
7. FOR ALL 由生成器产生的运行结果，THE DST_Framework SHALL 保证以反序列化的种子与轨迹重放得到与原运行一致的终态（跨会话重放保真，以 PBT 验证）。

---

### Requirement 9：旗舰端到端 demo —— 多副本复制场景

**用户故事（User Story）：** 作为评估该框架能力的开发者，我想要一个贯穿文档与基准的真实分布式 demo，以便我能看到注入故障、触发失败、收缩反例、重放复现与不变量校验的完整闭环。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 提供一个多副本日志复制（或键值存储）的端到端示例场景，由若干副本任务通过消息传递达成状态同步。
2. WHEN 在该示例中注入网络分区与崩溃故障，THE DST_Framework SHALL 产生一次违反副本一致性不变量的失败运行。
3. WHEN 对该失败运行执行收缩，THE DST_Framework SHALL 产出一个仍触发同一不变量违反的最小反例。
4. WHEN 以该最小反例的种子与轨迹重放，THE DST_Framework SHALL 复现同一失败终态。
5. THE DST_Framework SHALL 在该示例中对每个观测状态校验副本一致性不变量，并在违反时报告被违反的不变量与逻辑时间戳。
6. THE DST_Framework SHALL 使该 demo 同时作为可执行文档（`README.mbt.md`）示例与基准工作负载出现，使「发现—收缩—重放—校验」闭环可被复现。

---

### Requirement 10：性能基准（benches/）

**用户故事（User Story）：** 作为关心仿真吞吐与探索成本的开发者，我想要可复现的基准证据，以便我能比较 `run`/`replay`/穷尽探索/DPOR/收缩在大规模场景下的开销与回归。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 在 `benches/` 下提供基准包，覆盖大规模场景的 `run`、`replay`、有界穷尽探索、DPOR 探索与收缩五类工作负载。
2. WHEN 运行基准，THE DST_Framework SHALL 输出包含机器标识、后端目标、场景规模与计时统计的基准结果工件（JSON 或 Markdown）。
3. THE DST_Framework SHALL 在基准中记录 DPOR 探索相对有界穷尽探索的交错数量约简比，以呈现偏序约简的有效性。
4. WHERE 提供基准回归基线，THE DST_Framework SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告（回归 guard）。
5. THE DST_Framework SHALL 在基准文档中记录运行命令，并要求 native 后端前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib` 以保证可复现。

---

### Requirement 11：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键算法可追溯到源论文并与主流系统对比、且明确实现边界，以便我能理解设计依据、取舍与适用范围。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 在文档中将确定性仿真测试方法追溯到 FoundationDB 的确定性仿真实践。
2. THE DST_Framework SHALL 在文档中将偏序约简追溯到 Flanagan & Godefroid 2005 的 DPOR 算法。
3. THE DST_Framework SHALL 在文档中将线性一致性检查追溯到 Herlihy & Wing 1990 与 Wing & Gong 的线性化点方法。
4. THE DST_Framework SHALL 在文档中将失败收缩追溯到 delta debugging 与 QuickCheck shrinking 的对应技术。
5. THE DST_Framework SHALL 在文档中提供与 FoundationDB simulation、TigerBeetle VOPR、`madsim`/`turmoil` 及 Jepsen/Knossos 的能力与模型对比。
6. THE DST_Framework SHALL 显式声明本实现的边界：纯内存确定性模型，不接入真实网络、真实时间与操作系统线程。

---

### Requirement 12：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我现有的仿真脚本在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 保留既有公开类型 `Task`、`Event`、`FaultKind`、`FaultPolicy`、`Scenario`、`SimStatus`、`SimResult`、`Sim` 与 `Rng` 的现有字段与语义。
2. THE DST_Framework SHALL 保留既有接口 `Sim::new`、`Sim::step`、`Sim::inject_fault`、`run`、`replay`、`rng_new`、`Rng::next`、`Rng::next_below` 的现有公开签名与行为。
3. THE DST_Framework SHALL 维持既有 `run` 的规范化语义：任务按 id 升序规范化、故障按「（at_step，task_id）」升序处理，且同种子产生同调度序列与同终态。
4. WHERE 新增能力（虚拟时间、消息事件、新故障类型、探索、收缩、持久化、不变量）需要扩展行为，THE DST_Framework SHALL 以新增 API 或旁路扩展提供，而不破坏既有 API 的调用方。
5. THE DST_Framework SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板，并复用 `@release_meta` 承载发布元数据。

---

### Requirement 13：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE DST_Framework SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE DST_Framework SHALL 为本规格的核心正确性属性（同种子确定性、虚拟时间单调性、因果序保持、故障注入确定性、收缩保真与终止、探索完整性、DPOR 可靠性、不变量违反检出、序列化往返、跨会话重放保真）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE DST_Framework SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖虚拟时间与消息传递、丰富故障注入、收缩、探索与多副本 demo，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE DST_Framework SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE DST_Framework SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE DST_Framework SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
