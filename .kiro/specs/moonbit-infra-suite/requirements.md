# 需求文档（Requirements Document）

## 引言（Introduction）

本文档是 **moonbit-infra-suite** 的 **umbrella 总规划需求集**。其目标是基于 MoonBit 语言，从 0 到 1 高质量构建一套"基础设施级"开源项目集合，覆盖编译器/语言实现、开发者工具（LSP / 构建 / 可观测性）、系统与运行时三大领域，共 10 个方向。

本规划是一个 **总伞（umbrella）规划**，并非要求单一可交付物一次性完成。强烈建议按"**模块化拆分推进**"的策略实施：每个方向（Requirement 1 ~ Requirement 10）应被视为一个**可独立立项、独立发布、独立版本演进**的子项目（建议各自拥有独立的 `.kiro/specs/{子方向名}/` 设计与任务文档）。本文件只负责锁定**每个方向的范围边界与验收标准**，为后续逐一展开设计（design）与任务（tasks）提供共同基线。

本规划承袭 `moonbit-pathfinding` 已验证的工程理念，并将其作为**贯穿所有方向的强制质量基线**（见 Requirement 11）：

- **可执行证明谓词（Executable Proof Predicates）**：将关键后置条件编码为可在 CI 运行的 MoonBit 谓词函数，并预留 `moon prove` 升级路径。
- **属性测试（Property-Based Testing, PBT）**：对存在输入变化空间的核心逻辑（解析器、编解码器、调度器等）使用属性测试，并优先覆盖往返（round-trip）、不变量（invariant）、幂等（idempotence）等高价值性质。
- **三后端一致性（Multi-backend Consistency）**：在 `wasm-gc` / `native` / `js` 三个后端上运行同一测试套件，任何输出分歧（含快照不一致）均视为构建失败。
- **可执行文档（Executable Documentation）**：README 与教程中的示例通过 `moon test *.mbt.md` 编译并验证，杜绝文档与实现漂移。

**复用既有资产说明**：部分方向可直接复用 `moonbit-pathfinding` 已实现的图算法资产，包括拓扑排序（`@directed.topo_sort`）、强连通分量缩点（`@directed.condensation` / `@directed.tarjan_scc`）、图着色相关算法等。复用关系在对应方向的验收标准中显式标注。

---

## 术语表（Glossary）

- **Suite**：moonbit-infra-suite 总规划本身，作为统辖 10 个方向的总伞项目。
- **Mini_Compiler**：方向一的小语言编译器/解释器系统，实现"词法 → 语法 → 类型检查 → 求值/编译"流水线。
- **Regex_Engine**：方向二的正则表达式引擎系统，包含正则语法解析、自动机构造与匹配执行。
- **Codegen_Infra**：方向三的编译器基础设施组件集合，包含寄存器分配器、SSA 框架与指令选择 DSL。
- **Register_Allocator**：Codegen_Infra 内的寄存器分配子系统，提供图着色与线性扫描两种策略。
- **Parser_Combinator**：方向四的解析器组合子 / 解析器生成器库系统。
- **LSP_Server**：方向五的语言服务器系统，基于 JSON-RPC over stdio 提供语言能力。
- **LSP_Binding**：LSP_Server 的底层协议绑定库（LSP 协议类型定义 + JSON-RPC 框架）。
- **Build_Tool**：方向六的增量构建系统，解析构建图并执行脏检查与并行调度。
- **Logging_Library**：方向七的结构化日志与 tracing 系统，提供 span / trace 上下文传播。
- **DST_Framework**：方向八的确定性仿真测试（Deterministic Simulation Testing）框架。
- **Serialization_Framework**：方向九的序列化框架，覆盖 protobuf wire format 编解码、`.proto` 解析与代码生成。
- **Actor_Framework**：方向十的 Actor 并发框架，基于 `moonbitlang/async`。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。
- **证明谓词（Proof Predicate）**：将算法/系统后置条件编码为可在运行期校验的布尔函数。
- **往返性质（Round-trip Property）**：对编解码/解析-打印类操作，要求 `decode(encode(x)) == x` 或 `parse(print(x))` 语义等价。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`native`、`js` 三个编译目标。
- **黄金文件（Golden File）**：预先校验过、用于回归比对的期望输出文件。
- **构建图（Build Graph）**：以构建产物为节点、依赖关系为边的有向无环图。
- **脏检查（Dirty Check）**：基于文件修改时间（mtime）或内容哈希判定产物是否需要重建的检测过程。

---

## 需求（Requirements）

### Requirement 1：小语言编译器 / 解释器（Mini_Compiler）

**用户故事（User Story）：** 作为一名学习语言实现的 MoonBit 开发者，我想要一门小语言（如 mini-ML / Lox / Scheme / C 子集）的完整编译器/解释器实现，以便我能端到端理解从源码到执行的全流程并在生态中复用。

> 方向元数据：难度 ⭐⭐⭐⭐，烂尾风险高，生态缺口大；可参考《Crafting Interpreters》与官方 minimoonbit 教学项目。建议作为独立子项目分阶段推进（先解释器，后编译到 wasm/JS）。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 在项目文档中明确声明所实现的目标语言及其文法（grammar），并以可引用的形式给出完整的产生式规则。
2. WHEN 接收到一段符合目标语言文法的源代码字符串，THE Mini_Compiler SHALL 输出一棵抽象语法树（AST）。
3. IF 源代码包含词法或语法错误，THEN THE Mini_Compiler SHALL 返回包含错误类别、行号与列号的诊断结果，且不产生 AST。
4. WHEN 一棵语法正确的 AST 进入类型检查阶段且类型一致，THE Mini_Compiler SHALL 输出带类型标注的 AST。
5. IF 类型检查发现类型不一致，THEN THE Mini_Compiler SHALL 返回包含冲突类型与出错节点位置的类型错误诊断。
6. WHEN 一段通过类型检查的程序被求值，THE Mini_Compiler SHALL 产生与该语言语义规范一致的运行结果。
7. WHERE 启用了编译后端选项，THE Mini_Compiler SHALL 将通过类型检查的程序编译为 `wasm` 或 `js` 目标产物。
8. FOR ALL 由生成器产生的合法 AST，THE Mini_Compiler SHALL 满足"打印再解析"往返性质：解析其打印结果得到等价 AST（round-trip property，以 PBT 验证）。
9. THE Mini_Compiler SHALL 为求值器的关键语义不变量（如作用域绑定一致性、求值结果确定性）提供可执行证明谓词，并在 CI 中校验。
10. THE Mini_Compiler SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一示例程序集合产生一致的求值输出。

---

### Requirement 2：正则表达式引擎（Regex_Engine）

**用户故事（User Story）：** 作为需要文本匹配能力的 MoonBit 开发者，我想要一个对标 Rust `regex` 子集的正则引擎，以便我无需绑定外部库即可在三后端上进行可靠的模式匹配。

> 方向元数据：难度 ⭐⭐⭐，风险中，生态缺口大；可使用 PCRE 测试套件作为外部验收语料。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 在文档中声明所支持的正则语法子集（字符类、量词 `* + ? {m,n}`、分组、择一 `|`、锚点）。
2. WHEN 接收到一个属于受支持子集的正则表达式字符串，THE Regex_Engine SHALL 将其解析为正则语法树。
3. IF 正则表达式字符串语法非法，THEN THE Regex_Engine SHALL 返回包含错误位置的解析错误，且不构造自动机。
4. WHEN 一棵合法正则语法树进入构造阶段，THE Regex_Engine SHALL 构造出等价的 NFA，并可进一步确定化为 DFA。
5. WHEN 对给定输入字符串执行匹配，THE Regex_Engine SHALL 返回是否匹配以及匹配区间（起止偏移）。
6. FOR ALL 受支持子集内的正则表达式与任意输入字符串，THE Regex_Engine SHALL 保证 NFA 匹配结果与 DFA 匹配结果一致（差分一致性，以 PBT 验证）。
7. THE Regex_Engine SHALL 为"打印再解析"提供往返性质：对任一合法正则语法树，解析其打印结果得到等价语法树（round-trip property，以 PBT 验证）。
8. WHERE 提供了 PCRE 兼容测试语料，THE Regex_Engine SHALL 以黄金文件方式记录并回归校验匹配结果。
9. THE Regex_Engine SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一测试语料产生一致的匹配结果。

---

### Requirement 3：编译器基础设施组件（Codegen_Infra）

**用户故事（User Story）：** 作为构建编译器后端的开发者，我想要独立、可组合的代码生成基础设施（寄存器分配、SSA 框架、指令选择 DSL），以便我能在不重复造轮子的前提下搭建自己的后端。

> 方向元数据：难度 ⭐⭐⭐⭐，风险中。加分点：与 pathfinding 库技术同源——寄存器分配的图着色即图算法，可复用现有图着色 / 干涉图相关资产。

#### 验收标准（Acceptance Criteria）

1. WHEN 接收到一个变量干涉图（interference graph）与可用寄存器数量 K，THE Register_Allocator SHALL 输出一个变量到寄存器或溢出槽（spill slot）的分配方案。
2. THE Register_Allocator SHALL 同时提供图着色（graph-coloring）与线性扫描（linear-scan）两种分配策略，并复用 `moonbit-pathfinding` 的图着色相关图算法资产。
3. FOR ALL 由生成器产生的干涉图与寄存器数量 K，THE Register_Allocator SHALL 保证分配方案中任意两个相互干涉的变量不共享同一寄存器（核心正确性不变量，以 PBT 验证）。
4. WHEN 接收到一段基本块序列，THE Codegen_Infra SHALL 构造出满足支配关系的 SSA 形式（含 φ 函数插入）。
5. FOR ALL 合法的 SSA 程序，THE Codegen_Infra SHALL 保证每个变量恰有唯一一次静态定义（SSA 单赋值不变量，以可执行证明谓词与 PBT 验证）。
6. WHERE 注册了若干优化 pass，THE Codegen_Infra SHALL 按声明顺序依次执行各 pass 并在每个 pass 后保持 SSA 不变量成立。
7. THE Codegen_Infra SHALL 提供指令选择 DSL，使调用方能以声明式规则将 IR 节点映射为目标指令。
8. THE Codegen_Infra SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一输入产生一致的分配方案与 SSA 结构。

---

### Requirement 4：解析器组合子 / 解析器生成器（Parser_Combinator）

**用户故事（User Story）：** 作为需要解析自定义格式的开发者，我想要一个类似 nom / parsec 的解析器组合子库（或 LALR 生成器），以便我能用可组合的原语快速构建解析器，并作为方向一、方向二的地基。

> 方向元数据：难度 ⭐⭐⭐，风险低，生态缺口大；是 Mini_Compiler 与 Regex_Engine 的共同地基。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 提供基础解析原语，至少包含字符/词法单元匹配、序列组合、择一组合、重复（many / many1）与可选（optional）。
2. WHEN 一个由组合子构造的解析器成功消费输入前缀，THE Parser_Combinator SHALL 返回解析结果与剩余未消费输入。
3. IF 解析失败，THEN THE Parser_Combinator SHALL 返回包含失败位置与期望符号的错误信息，且不消费输入。
4. WHILE 解析器处于回溯（backtracking）模式，THE Parser_Combinator SHALL 在择一分支失败时恢复到分支起始位置。
5. FOR ALL 由生成器产生的合法语法结构，THE Parser_Combinator SHALL 满足"打印再解析"往返性质（round-trip property，以 PBT 验证）。
6. WHERE 调用方提供了文法描述以生成 LALR 解析器，THE Parser_Combinator SHALL 在文法存在移进-归约或归约-归约冲突时报告冲突所在产生式。
7. THE Parser_Combinator SHALL 通过 `moon test *.mbt.md` 形式提供可执行文档示例，覆盖至少 3 个端到端解析样例。
8. THE Parser_Combinator SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一输入产生一致的解析结果。

---

### Requirement 5：通用 DSL 的 LSP 服务器（LSP_Server）

**用户故事（User Story）：** 作为编辑某种 DSL（如 TOML / JSON Schema / 自定义 DSL）的开发者，我想要一个提供诊断、补全、跳转定义与悬停的 LSP 服务器，以便我在任意支持 LSP 的编辑器中获得语言智能。

> 方向元数据：难度 ⭐⭐⭐⭐，风险中高。入门可先交付 LSP_Binding（协议类型定义 + JSON-RPC 框架）；不针对 MoonBit 自身（官方已有 LSP）。

#### 验收标准（Acceptance Criteria）

1. THE LSP_Binding SHALL 提供 LSP 协议核心消息的 MoonBit 类型定义与一个基于 JSON-RPC 2.0 的请求/响应/通知分发框架。
2. WHEN 通过 stdio 接收到一个符合 JSON-RPC 2.0 的请求，THE LSP_Server SHALL 解析该请求并路由到对应的能力处理器。
3. IF 接收到的消息不符合 JSON-RPC 2.0 规范，THEN THE LSP_Server SHALL 返回符合规范的错误响应（含错误码与消息），且不终止服务进程。
4. WHEN 接收到 `initialize` 请求，THE LSP_Server SHALL 在响应的 `capabilities` 中声明其支持的能力集合（诊断、补全、跳转定义、悬停）。
5. WHEN 目标 DSL 文档发生变更通知（`didChange`），THE LSP_Server SHALL 重新分析该文档并发布 `publishDiagnostics` 诊断。
6. WHEN 接收到补全请求（`completion`），THE LSP_Server SHALL 基于当前位置上下文返回补全候选列表。
7. WHEN 接收到跳转定义请求（`definition`）且目标符号已定义，THE LSP_Server SHALL 返回该符号定义所在的位置。
8. WHEN 接收到悬停请求（`hover`）且光标位于已知符号上，THE LSP_Server SHALL 返回该符号的描述信息。
9. THE LSP_Binding SHALL 为 JSON-RPC 消息的编解码提供往返性质：解码再编码任一合法消息得到语义等价消息（round-trip property，以 PBT 验证）。

---

### Requirement 6：增量构建系统（Build_Tool）

**用户故事（User Story）：** 作为管理多产物项目的开发者，我想要一个类似 ninja/n2 的增量构建工具，以便仅重建发生变化的部分并尽可能并行执行，从而缩短构建时间。

> 方向元数据：难度 ⭐⭐⭐，风险中，官方点名需要。核心是图算法（拓扑排序、关键路径），直接复用 `@directed.topo_sort` 与 `@directed.condensation`。

#### 验收标准（Acceptance Criteria）

1. WHEN 接收到一份构建规则描述，THE Build_Tool SHALL 将其解析为以产物为节点、依赖为边的构建图（Build Graph）。
2. IF 构建图中存在环（cyclic dependency），THEN THE Build_Tool SHALL 报告构成环的节点序列并拒绝执行构建。
3. WHEN 构建图无环，THE Build_Tool SHALL 复用 `@directed.topo_sort` 计算合法的拓扑执行顺序。
4. WHEN 对某产物执行脏检查，THE Build_Tool SHALL 依据输入文件的 mtime 与内容哈希判定该产物是否需要重建。
5. WHILE 存在多个相互无依赖的待执行任务，THE Build_Tool SHALL 在不违反依赖顺序的前提下并行调度这些任务。
6. WHEN 一次成功构建之后输入文件均未发生变化，THE Build_Tool SHALL 在再次构建时不执行任何重建动作（增量空操作）。
7. FOR ALL 由生成器产生的无环构建图，THE Build_Tool SHALL 保证其调度顺序满足"任一节点在其所有依赖之后执行"的不变量（以 PBT 验证）。
8. THE Build_Tool SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一构建图产生一致的调度结果。

---

### Requirement 7：结构化日志与 tracing 库（Logging_Library）

**用户故事（User Story）：** 作为构建可观测服务的开发者，我想要一个对标 Rust `tracing` 的结构化日志与跨度（span）追踪库，以便我能记录结构化字段并在异步调用间传播 trace 上下文。

> 方向元数据：难度 ⭐⭐⭐，风险低，官方点名需要；基于 `moonbitlang/async`。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用方记录一条带键值字段的日志事件，THE Logging_Library SHALL 输出包含时间戳、级别与全部结构化字段的日志记录。
2. WHERE 配置了最低日志级别阈值，THE Logging_Library SHALL 丢弃级别低于该阈值的日志事件。
3. WHEN 进入一个 span，THE Logging_Library SHALL 将该 span 与其父 span 关联以形成 span 树。
4. WHILE 一个 span 处于激活状态，THE Logging_Library SHALL 将在该 span 内产生的日志事件标注该 span 的上下文标识。
5. WHEN 一个 span 结束，THE Logging_Library SHALL 记录该 span 的持续时长。
6. WHERE 跨异步任务边界传播 trace 上下文，THE Logging_Library SHALL 在子任务中保留父任务的 trace 标识。
7. WHERE 配置了结构化输出格式（如 JSON），THE Logging_Library SHALL 产出可被解析的结构化日志记录，并满足"序列化再解析"往返性质（round-trip property，以 PBT 验证）。

---

### Requirement 8：确定性仿真测试框架（DST_Framework）

**用户故事（User Story）：** 作为测试分布式/并发系统的开发者，我想要一个 FoundationDB / TigerBeetle 风格的确定性仿真框架，以便我能用固定随机种子可重放地复现并发交错与故障场景。

> 方向元数据：难度 ⭐⭐⭐⭐，风险中。核心价值在"同种子 → 同执行"的确定性可重放。

#### 验收标准（Acceptance Criteria）

1. WHEN 以一个随机种子启动一次仿真运行，THE DST_Framework SHALL 使用该种子驱动一个确定性的伪随机源。
2. FOR ALL 给定的随机种子，THE DST_Framework SHALL 保证两次运行产生逐事件一致的调度序列与最终状态（确定性可重放不变量，以 PBT 验证）。
3. WHEN 多个并发任务等待被调度，THE DST_Framework SHALL 依据当前确定性随机源选择下一个被执行的任务。
4. WHERE 启用了故障注入策略，THE DST_Framework SHALL 在确定性随机源指示的注入点触发所配置的故障（如消息丢失、延迟、节点崩溃）。
5. WHEN 一次仿真运行因断言失败而终止，THE DST_Framework SHALL 输出可重放该失败的种子与事件轨迹。
6. WHEN 使用某次失败运行所输出的种子重新运行，THE DST_Framework SHALL 复现完全相同的失败。
7. THE DST_Framework SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一种子产生一致的事件调度序列。

---

### Requirement 9：序列化框架（Serialization_Framework）

**用户故事（User Story）：** 作为需要跨语言数据交换的开发者，我想要一个 protobuf 序列化框架（wire format 编解码 + `.proto` 解析 + 代码生成），以便我能在 MoonBit 中与 protobuf 生态互操作。

> 方向元数据：难度 ⭐⭐⭐，风险低，官方点名需要；测试黄金文件现成（protobuf 官方 conformance 语料）。

#### 验收标准（Acceptance Criteria）

1. WHEN 接收到一个内存中的消息对象，THE Serialization_Framework SHALL 将其编码为符合 protobuf wire format 的字节序列。
2. WHEN 接收到一段符合 protobuf wire format 的字节序列与对应消息模式，THE Serialization_Framework SHALL 将其解码为内存中的消息对象。
3. FOR ALL 由生成器产生的合法消息对象，THE Serialization_Framework SHALL 满足"编码再解码"往返性质：`decode(encode(x))` 等价于 `x`（round-trip property，以 PBT 验证）。
4. IF 输入字节序列不符合 protobuf wire format，THEN THE Serialization_Framework SHALL 返回包含出错字节偏移的解码错误，且不产生部分构造的对象。
5. WHEN 接收到一份 `.proto` 文件，THE Serialization_Framework SHALL 将其解析为消息/字段/枚举的模式描述。
6. IF `.proto` 文件存在语法错误，THEN THE Serialization_Framework SHALL 返回包含行列位置的解析错误。
7. WHEN 对一份合法 `.proto` 模式执行代码生成，THE Serialization_Framework SHALL 产出对应的 MoonBit 消息类型定义与编解码代码。
8. WHERE 提供了 protobuf 官方 conformance 黄金语料，THE Serialization_Framework SHALL 以黄金文件方式回归校验编解码结果。
9. THE Serialization_Framework SHALL 在 `wasm-gc`、`native`、`js` 三后端上对同一消息产生一致的编码字节序列。

---

### Requirement 10：Actor 并发框架（Actor_Framework）

**用户故事（User Story）：** 作为构建并发系统的开发者，我想要一个基于 `moonbitlang/async` 的 Actor 框架，以便我能用消息传递模型隔离状态并安全地组织并发逻辑。

> 方向元数据：难度 ⭐⭐⭐⭐，风险中高（async 生态处于变动期，需关注上游 API 稳定性）。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用方派生（spawn）一个 actor，THE Actor_Framework SHALL 返回一个可用于向该 actor 投递消息的引用句柄。
2. WHEN 一条消息被投递给某个 actor，THE Actor_Framework SHALL 将该消息追加到该 actor 的邮箱队列。
3. THE Actor_Framework SHALL 保证单个 actor 一次仅处理一条消息（单 actor 内串行处理不变量）。
4. FOR ALL 单一发送者向单一 actor 投递的消息序列，THE Actor_Framework SHALL 保证该 actor 按投递顺序处理这些消息（FIFO 顺序不变量，以 PBT 验证）。
5. WHILE 某个 actor 的邮箱为空，THE Actor_Framework SHALL 使该 actor 处于挂起状态而不占用执行资源。
6. IF 某个 actor 在处理消息期间抛出未捕获错误，THEN THE Actor_Framework SHALL 终止该 actor 并通知其监督者（supervisor），且不影响其他 actor 的运行。
7. WHEN 调用方请求停止某个 actor，THE Actor_Framework SHALL 在该 actor 处理完当前消息后停止其消息循环并释放相关资源。

---

### Requirement 11：贯穿性工程质量门禁（适用于所有方向）

**用户故事（User Story）：** 作为 Suite 的维护者，我想要一套适用于全部 10 个方向的统一工程质量基线，以便每个子项目都达到与 `moonbit-pathfinding` 一致的可验证、可复现、可信赖标准。

> 说明：本组为横切（cross-cutting）需求，是对 Requirement 1 ~ Requirement 10 的统一约束，确保 umbrella 规划在拆分推进时仍保持一致的质量门槛。

#### 验收标准（Acceptance Criteria）

1. THE Suite SHALL 要求每个方向在 `wasm-gc`、`native`、`js` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Suite SHALL 要求每个方向为其核心后置条件提供可在 CI 运行的可执行证明谓词，并预留 `moon prove` 升级路径。
3. WHERE 某方向包含解析器或序列化器，THE Suite SHALL 要求该方向提供配套的打印器/编码器以及一条往返（round-trip）属性测试。
4. THE Suite SHALL 要求每个方向提供通过 `moon test *.mbt.md` 验证的可执行文档示例。
5. THE Suite SHALL 要求每个方向作为可独立发布的子项目，拥有独立的 SemVer 版本与变更日志（changelog）。
6. WHEN 任一方向的测试、证明谓词或可执行文档校验未通过，THE Suite SHALL 阻止该方向进入发布就绪（release-ready）状态。
