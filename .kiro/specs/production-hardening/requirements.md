# Requirements Document

> 需求文档 · 全程中文撰写

## Introduction

> 引言

本规格 **Production_Hardening（生产级加固）** 的目标，是把仓库中已完成的 10 个方向 spec（`build-tool`、`codegen-infra`、`dst`、`logging`、`lsp`、`mini-compiler`、`moonbit-infra-suite`、`parser-combinator`、`regex-engine`、`serialization`）的实现质量，从「教学级 / 展示级」整体拔高到「真实机器运行时可用的生产级」。本规格不是从零重建，而是在既有公开 API 之上做**增量加固**：以「只新增、不破坏」为基本盘，复用既有类型与函数，并补齐性能、真实 I/O、类型化数据结构、增量算法、运行时可观测性与工具链鲁棒性。

加固覆盖 12 条主线：(1) 消除跨 7 个 spec 共 107+ 处 `out = out + ...` 的 O(n²) 字符串拼接性能致命伤；(2) 补齐真实 I/O 层；(3) 正则引擎深化；(4) 解析器组合子深化；(5) 序列化深化；(6) 代码生成基础设施类型化；(7) 确定性仿真测试深化；(8) 迷你编译器语言特性与优化；(9) 日志真实落地与运行时调级；(10) 构建工具执行与持久化；(11) LSP 协议鲁棒性；(12) PBT 框架增强。

本规格按 workspace 三档递进规则呈现加固深度选择，**默认采用 🟣 档位 3「业界顶尖（旗舰）」**：覆盖全部 12 条主线、最大广度与难度、完整属性测试（≥100 次迭代）、三后端（`wasm-gc`/`js`/`native`）一致性、开源对标与可解释文档。用户可在评审阶段对个别方向降档（🟢 夯实基础 / 🔵 进阶完善），或统一选择某一档位。

本规格承袭仓库统一质量基线：复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（SemVer / `QualityGates`）与 `README.mbt.md`「文档即测试」模式，并以「冻结现有公开 API + bypass 新增」策略保证向后兼容。

---

## Glossary

> 术语表

- **Production_Hardening**：本规格定义的跨方向生产级加固工作集，是横切约束（Requirement 12）的主体系统。
- **Shared_Text_Builder**：新增的共享高效文本构建工具（位于共享基础设施包），以 `Array[Char]` 缓冲或 `Array[String] + join` 实现摊还 O(1) 追加、O(n) 物化，替换各方向中的 O(n²) 拼接。
- **O(n²) 拼接（Quadratic String Concatenation）**：以 `out = out + s` 在循环中反复构造新字符串、累计复制代价为输入规模平方级的反模式。
- **Logging_Sink_Layer**：`logging` 方向的输出端抽象层，新增 `ConsoleSink`/`CallbackSink`/`BufferedSink` 等真实落地实现，及运行时 `set_level` 调级能力。
- **ConsoleSink**：通过 `println` 将日志记录写入标准输出（stdout）的 Sink 实现。
- **CallbackSink**：将日志记录交付给调用方传入的回调函数处理的 Sink 实现。
- **BufferedSink**：在内部缓冲日志记录、达到阈值或显式 `flush` 时批量交付下游 Sink 的实现。
- **Build_Executor_Framework**：`build-tool` 方向新增的动作执行框架，含 `Action` 类型、`Executor` 接口、`DryRunExecutor`/`CallbackExecutor`、`ParallelSchedule` 与 `BuildLog`。
- **Action**：构建图中一个可执行单元的声明式描述（如命令、输入、输出、指纹）。
- **Executor**：执行 `Action` 的接口；`DryRunExecutor` 仅记录而不实际执行，`CallbackExecutor` 把执行委派给回调。
- **ParallelSchedule**：基于依赖图标记彼此无依赖、可并行执行的 `Action` 分组（波次 / wave）。
- **BuildLog**：持久化的构建记录，含每个 `Action` 的输入指纹（fingerprint）与结果，用于增量构建判定。
- **Serialization_Enhancer**：`serialization` 方向的加固系统，补齐 proto3 缺失功能、结构化代码生成与流式编解码及 `.proto` 文件读写。
- **Structured_Codegen_AST**：代码生成的结构化中间表示（声明 / 语句 / 表达式节点）与 pretty-printer，替代直接字符串拼接。
- **Regex_Engine**：`regex-engine` 方向系统，本规格为其新增 Unicode General Category 支持、hybrid NFA/DFA 切换与惰性 DFA 缓存淘汰、高层实用 API 与 `CharSet` 二分查询。
- **Unicode_General_Category**：Unicode 字符的通用类别（如 `L`/`Lu`/`Ll`/`N`/`Nd`/`P`/`Z` 等），用于字符类匹配。
- **Hybrid_Matcher**：在惰性 DFA 与 NFA/Pike VM 之间按缓存压力动态切换的匹配执行路径。
- **Parser_Combinator**：`parser-combinator` 方向系统，本规格为其新增基于续延的增量流式解析、错误恢复组合子与有界 packrat 缓存。
- **Incremental_Streaming_Parse（增量流式解析）**：在分块输入到达时，仅就新增输入推进解析状态、而非从头重解析的解析模式。
- **withRecovery（错误恢复组合子）**：在子解析失败时，按恢复策略跳过 / 同步到指定标记并产出占位结果以继续解析的组合子。
- **Packrat 缓存（Packrat Cache）**：记忆化解析结果以保证线性时间的缓存；本规格为其新增容量上限与淘汰策略。
- **Codegen_IR**：`codegen-infra` 方向的中间表示，本规格将其从字符串化指令改造为类型化枚举，并新增验证器与解释器。
- **Typed_IR_Instruction（类型化 IR 指令）**：以枚举建模的指令（如 `Add`/`Sub`/`Mul`/`Load`/`Store`/`Call`/`Ret`/`Br`/`Phi`）及操作数类型 `Operand`（`Reg`/`Imm`/`Mem`）。
- **IR_Validator（IR 验证器）**：检验 IR 的 SSA 属性、类型一致性与控制流完整性的组件。
- **IR_Interpreter（IR 解释器）**：按 IR 语义对类型化 IR 求值、产出可观测结果的组件。
- **SSA**：静态单赋值（Static Single Assignment）形式，每个虚拟寄存器至多被定义一次。
- **Dst_Simulator**：`dst` 方向的确定性仿真系统，本规格为其新增可执行任务体、模拟网络层、虚拟时钟与不变量检查框架。
- **TaskBody**：可执行任务体，签名为 `(SimContext) -> TaskResult`，取代仅含 `{id, name}` 的占位任务。
- **NetworkSim（模拟网络层）**：在仿真内提供消息传递、确定性延迟、丢失、乱序与网络分区的组件。
- **SimClock（虚拟时钟）**：仿真内确定性推进的逻辑时钟，不依赖真实墙钟时间。
- **invariant / eventually（不变量框架）**：分别表达「在所有可观测状态恒成立的断言」与「在有限步内最终成立的断言」的检查原语。
- **Mini_Compiler**：`mini-compiler` 方向系统，本规格为其新增 `match` 模式匹配、元组类型与列表字面量，并为字节码 VM 新增 peephole 优化与尾调用优化（TCO），改进类型错误报告。
- **Peephole 优化（Peephole Optimization）**：对字节码局部相邻指令窗口应用等价改写以消除冗余的优化。
- **TCO（Tail Call Optimization，尾调用优化）**：把处于尾位置的调用复用当前调用帧、避免栈增长的优化。
- **Lsp_Server**：`lsp` 方向系统，本规格保证其 JSON-RPC 2.0 完整性、`Content-Length` 多换行符兼容、真正增量文档同步与大文档非平方级处理。
- **JSON-RPC 2.0**：LSP 传输所基于的远程过程调用协议，含 `id`/`method`/`params`/`result`/`error` 与批处理语义。
- **Content-Length 帧（Content-Length Framing）**：LSP 消息头部声明消息体字节长度的成帧机制，头尾以换行分隔。
- **增量文档同步（Incremental Document Sync）**：依据范围（range）增量变更而非全量替换地更新服务端文档镜像的机制。
- **Pbt_Framework**：`moonbit-infra-suite` 中的属性测试框架（`@infra_pbt`），本规格为其新增 shrink、生成器组合子与统计收集。
- **Shrink（反例收缩）**：属性测试失败时，自动将反例缩小为更小、更易诊断的最小失败输入的过程。
- **生成器组合子（Generator Combinators）**：`one_of`（等概率择一）、`frequency`（按权重择一）、`sized`（按规模参数生成）等构造随机生成器的组合子。
- **统计收集（Statistics Collection）**：在属性测试运行中对生成样本分类计数、报告分布的能力。
- **API 冻结（API Freeze）**：将既有公开 API 标记为冻结基线、仅允许新增、不允许变更或删除的策略。
- **bypass 新增**：在不修改既有公开签名的前提下，以新增类型 / 函数 / 重载形式扩展能力的方式。
- **三后端一致性（Tri-Backend Consistency）**：同一行为在 `wasm-gc`、`js`、`native` 三个后端上测试结果一致。
- **`.mbti` 接口文件**：`moon info` 生成的包公开接口快照；本规格要求其只增不减以保证向后兼容。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 SemVer 推进与 `QualityGates` 描述。

---

## Requirements

> 需求

### Requirement 1: 共享高效文本构建工具，消除 O(n²) 拼接

**User Story:** 作为库的维护者，我想要一个共享的高效文本构建工具替换分散在各方向的循环字符串拼接，以便在大输入下获得线性而非平方级的构建性能。

#### Acceptance Criteria

1. THE Shared_Text_Builder SHALL 提供创建空缓冲、追加单个字符、追加字符串与物化为最终字符串的操作。
2. WHEN 调用方依次追加 N 个片段，THE Shared_Text_Builder SHALL 以对总输出长度呈线性的总时间完成构建。
3. THE Shared_Text_Builder SHALL 使物化结果与等价的顺序字符串拼接逐字符相等。
4. WHEN 物化为最终字符串后再次追加，THE Shared_Text_Builder SHALL 在后续物化中包含先前与新追加的全部片段且顺序保持。
5. THE Production_Hardening SHALL 将 `serialization`、`build-tool`、`logging`、`regex-engine`、`parser-combinator` 等方向中循环内的 `out = out + ...` 拼接点替换为 Shared_Text_Builder 调用，且替换后每个被改造函数的输出与改造前逐字符相等。
6. WHERE 某拼接点位于非循环、单次拼接的上下文，THE Production_Hardening SHALL 允许保留原拼接而不强制替换。

### Requirement 2: 日志真实 I/O 落地与运行时调级

**User Story:** 作为使用日志库的开发者，我想要日志能真正写到控制台或交给我的回调，并能在运行时调整级别，以便在真实程序中观测运行状态。

#### Acceptance Criteria

1. WHEN 一条日志记录的级别不低于当前生效级别且被派发到 ConsoleSink，THE Logging_Sink_Layer SHALL 通过 `println` 将该记录的格式化文本写入标准输出。
2. WHEN 一条日志记录被派发到 CallbackSink，THE Logging_Sink_Layer SHALL 以该记录为参数恰好调用一次调用方提供的回调函数。
3. WHILE BufferedSink 的缓冲未达到配置阈值，THE Logging_Sink_Layer SHALL 暂存记录而不交付下游。
4. WHEN BufferedSink 的缓冲达到配置阈值或收到显式 flush，THE Logging_Sink_Layer SHALL 按记录到达顺序将全部已缓冲记录交付下游 Sink 并清空缓冲。
5. WHEN 调用方调用 `set_level` 设置新的生效级别，THE Logging_Sink_Layer SHALL 使其后派发的、级别低于新生效级别的记录不被输出。
6. IF 一条日志记录的级别低于当前生效级别，THEN THE Logging_Sink_Layer SHALL 不将该记录交付任何 Sink。

### Requirement 3: 构建工具动作执行框架与持久化

**User Story:** 作为构建工具用户，我想要构建图中的节点能真正被执行（或干跑），并支持并行与增量，以便把它当作真实构建系统使用。

#### Acceptance Criteria

1. THE Build_Executor_Framework SHALL 提供 `Action` 类型以声明式描述一个可执行单元的输入、输出与命令标识。
2. WHEN 以 DryRunExecutor 执行一个 Action，THE Build_Executor_Framework SHALL 记录该 Action 而不产生任何外部副作用。
3. WHEN 以 CallbackExecutor 执行一个 Action，THE Build_Executor_Framework SHALL 将该 Action 交付调用方回调并采用回调返回的结果。
4. THE Build_Executor_Framework SHALL 依据依赖图产生 ParallelSchedule，使同一波次内的任意两个 Action 之间不存在依赖路径。
5. WHEN 执行一组 Action 后查询 BuildLog，THE Build_Executor_Framework SHALL 返回每个已执行 Action 的输入指纹与结果。
6. IF 一个 Action 的输入指纹与 BuildLog 中记录的指纹相同，THEN THE Build_Executor_Framework SHALL 将该 Action 标记为可跳过（up-to-date）。
7. THE Build_Executor_Framework SHALL 使 ParallelSchedule 的全部波次按序展开后包含且仅包含构建图中的全部 Action 各一次。

### Requirement 4: 序列化 proto3 增强、结构化代码生成与流式编解码

**User Story:** 作为序列化库用户，我想要更完整的 proto3 支持、可读的结构化代码生成与流式编解码，以便处理真实的 `.proto` 定义与数据流。

#### Acceptance Criteria

1. THE Serialization_Enhancer SHALL 解析含 `service`/`rpc` 定义、`import` 与 `package` 声明的 proto3 源文本为对应的结构化模型。
2. THE Serialization_Enhancer SHALL 支持 `Any` 类型的编码与解码。
3. THE Serialization_Enhancer SHALL 通过 Structured_Codegen_AST 构造代码并经 pretty-printer 物化为目标源码，而非直接字符串拼接。
4. FOR ALL 合法的 proto3 模型，THE Serialization_Enhancer SHALL 满足解析后打印再解析得到等价模型（往返一致性）。
5. THE Serialization_Enhancer SHALL 提供流式编码接口 `encode_to` 与流式解码接口 `decode_from`。
6. FOR ALL 可编码的消息值，THE Serialization_Enhancer SHALL 满足 `decode_from(encode_to(message))` 与原消息值相等（编解码往返一致性）。
7. IF proto3 源文本不符合 proto3 语法，THEN THE Serialization_Enhancer SHALL 返回含位置的描述性错误。

### Requirement 5: 正则引擎 Unicode 类别、混合执行与实用 API

**User Story:** 作为正则引擎用户，我想要 Unicode 类别匹配、更快的判定与更丰富的搜索 API，以便在真实文本处理中使用本引擎。

#### Acceptance Criteria

1. THE Regex_Engine SHALL 支持按 Unicode_General_Category 进行字符类匹配。
2. WHEN 仅需判定输入是否存在匹配，THE Regex_Engine SHALL 通过 `is_match` API 返回布尔判定，且其判定与 `find` 是否产出匹配一致。
3. WHILE 惰性 DFA 的状态缓存达到容量上限，THE Regex_Engine SHALL 按淘汰策略移除状态，且匹配结果与未受缓存限制的 NFA/Pike VM 路径一致。
4. WHEN 惰性 DFA 因缓存压力无法继续扩展，THE Hybrid_Matcher SHALL 切换到 NFA/Pike VM 路径继续匹配并产出与 DFA 路径一致的结果。
5. THE Regex_Engine SHALL 提供 `find_at`（指定起点查找）、`split_n`（限定份数切分）与 `replace_fn`（以回调计算替换文本）API。
6. THE Regex_Engine SHALL 以二分查找在 `CharSet` 区间数组中判定字符成员关系，且其判定结果与线性扫描判定一致。
7. WHEN `find_at` 以起点 `k` 调用，THE Regex_Engine SHALL 仅返回 `start` 不小于 `k` 的匹配或在无此类匹配时返回无匹配。

### Requirement 6: 解析器组合子增量解析、错误恢复与有界缓存

**User Story:** 作为解析器组合子用户，我想要真正的增量流式解析、错误恢复与有界缓存，以便高效解析持续到达的大输入并从局部错误中恢复。

#### Acceptance Criteria

1. WHEN 输入分多块到达，THE Parser_Combinator SHALL 基于续延就新增输入推进解析，而不重新解析先前已消费的输入。
2. FOR ALL 输入与其任意分块方式，THE Parser_Combinator SHALL 使 Incremental_Streaming_Parse 的结果与一次性解析整段输入的结果相等。
3. WHEN 被 withRecovery 包裹的子解析失败，THE Parser_Combinator SHALL 按恢复策略同步到指定标记并产出占位结果以继续后续解析。
4. WHILE Packrat 缓存的条目数达到配置上限，THE Parser_Combinator SHALL 按淘汰策略移除缓存条目，且解析结果与无淘汰时相等。
5. THE Parser_Combinator SHALL 使有界 Packrat 缓存的内存占用不超过配置上限对应的条目数。

### Requirement 7: 代码生成基础设施类型化 IR、验证器与解释器

**User Story:** 作为编译基础设施用户，我想要类型化的 IR、能验证其正确性并能解释执行，以便在 IR 上做可靠的分析与变换。

#### Acceptance Criteria

1. THE Codegen_IR SHALL 以 Typed_IR_Instruction 枚举（至少含 `Add`/`Sub`/`Mul`/`Load`/`Store`/`Call`/`Ret`/`Br`/`Phi`）与 `Operand` 类型（`Reg`/`Imm`/`Mem`）表示指令，替代字符串化指令。
2. WHEN 给定满足 SSA 的合法 IR，THE IR_Validator SHALL 报告验证通过。
3. IF 某虚拟寄存器在 IR 中被定义超过一次，THEN THE IR_Validator SHALL 报告 SSA 违例。
4. IF 某指令的操作数类型与该指令要求不一致，THEN THE IR_Validator SHALL 报告类型不一致错误。
5. IF 某基本块的控制流不完整（缺少终结指令或跳转到不存在的块），THEN THE IR_Validator SHALL 报告控制流完整性错误。
6. WHEN IR_Interpreter 对通过验证的 IR 求值，THE Codegen_IR SHALL 产出由该 IR 语义确定的结果。

### Requirement 8: 确定性仿真可执行任务、模拟网络与不变量

**User Story:** 作为分布式系统测试者，我想要可执行的任务、可控的模拟网络与不变量检查，以便在确定性仿真中复现并发与故障场景。

#### Acceptance Criteria

1. THE Dst_Simulator SHALL 支持以 TaskBody（签名 `(SimContext) -> TaskResult`）定义可执行任务，取代仅含标识与名称的占位任务。
2. THE Dst_Simulator SHALL 通过 NetworkSim 在节点间传递消息，并支持配置确定性延迟、丢失、乱序与网络分区。
3. WHEN 以相同种子与相同任务集运行仿真两次，THE Dst_Simulator SHALL 产出逐事件相同的执行轨迹（确定性可复现）。
4. THE SimClock SHALL 仅按仿真内事件推进逻辑时间，不依赖真实墙钟时间。
5. IF 在任一可观测仿真状态下某 `invariant` 断言不成立，THEN THE Dst_Simulator SHALL 报告该不变量违例及其发生时的状态。
6. IF 某 `eventually` 断言在仿真终止时仍未成立，THEN THE Dst_Simulator SHALL 报告该最终性断言失败。

### Requirement 9: 迷你编译器语言特性与字节码优化

**User Story:** 作为迷你编译器用户，我想要模式匹配、元组与列表字面量以及更优的字节码与更清晰的类型错误，以便编写并高效运行更真实的程序。

#### Acceptance Criteria

1. THE Mini_Compiler SHALL 支持 `match` 模式匹配表达式、元组类型与列表字面量的解析、类型检查与求值。
2. WHEN 字节码中存在可被 peephole 规则消除的相邻冗余指令，THE Mini_Compiler SHALL 产出语义等价且指令数不增加的优化字节码。
3. WHEN 一个调用处于尾位置，THE Mini_Compiler SHALL 以 TCO 复用调用帧执行，使深度为 N 的尾递归所用调用帧数不随 N 线性增长。
4. FOR ALL 可成功编译的程序，THE Mini_Compiler SHALL 使优化前后字节码的求值结果相等。
5. IF 表达式存在类型不匹配，THEN THE Mini_Compiler SHALL 报告同时含期望类型（expected）与实际类型（actual）的类型错误。

### Requirement 10: LSP 协议鲁棒性与增量同步

**User Story:** 作为 LSP 客户端开发者，我想要严格的 JSON-RPC 2.0、稳健的成帧与真正增量的文档同步，以便在真实编辑器中稳定接入。

#### Acceptance Criteria

1. THE Lsp_Server SHALL 完整实现 JSON-RPC 2.0 的请求、响应、通知与错误对象语义。
2. WHEN 接收以 `Content-Length` 成帧、且头部使用 `\r\n` 或 `\n` 换行的消息，THE Lsp_Server SHALL 正确解析出完整消息体。
3. FOR ALL 合法 JSON-RPC 消息，THE Lsp_Server SHALL 满足成帧编码后再解码得到等价消息（成帧往返一致性）。
4. WHEN 接收基于范围的增量文档变更，THE Lsp_Server SHALL 仅对受影响范围应用变更并使文档镜像与全量替换结果一致。
5. WHEN 对长度为 N 的文档应用一次增量变更，THE Lsp_Server SHALL 以对 N 呈次平方级（优于 O(n²)）的时间完成同步。
6. IF 接收的消息不符合 JSON-RPC 2.0 结构，THEN THE Lsp_Server SHALL 返回相应的 JSON-RPC 错误对象。

### Requirement 11: PBT 框架 shrink、生成器组合子与统计

**User Story:** 作为属性测试编写者，我想要失败时自动收缩反例、丰富的生成器组合子与样本统计，以便更快定位问题并理解测试分布。

#### Acceptance Criteria

1. WHEN 一个属性测试失败，THE Pbt_Framework SHALL 输出经 Shrink 收缩后的最小失败反例。
2. THE Pbt_Framework SHALL 使 Shrink 产出的反例仍使被测属性失败。
3. THE Pbt_Framework SHALL 提供 `one_of`、`frequency` 与 `sized` 生成器组合子。
4. WHEN 以 `frequency` 配置权重生成大量样本，THE Pbt_Framework SHALL 使各分支的样本占比随样本量增大趋近其配置权重比例。
5. WHEN 启用统计收集运行属性测试，THE Pbt_Framework SHALL 报告各样本分类的计数或占比。

### Requirement 12: 横切质量门禁与向后兼容约束

**User Story:** 作为仓库维护者，我想要所有加固都在不破坏现有 API 与测试的前提下、跨三后端一致并经充分属性测试地完成，以便安全地演进项目。

#### Acceptance Criteria

1. THE Production_Hardening SHALL 仅以新增类型、函数或重载（bypass 新增）的方式扩展能力，不修改或删除任何既有公开 API 签名。
2. THE Production_Hardening SHALL 使每个受影响包的 `.mbti` 接口文件相对加固前只增不减（既有条目保持不变）。
3. THE Production_Hardening SHALL 使既有测试在不被修改的前提下全部通过。
4. THE Production_Hardening SHALL 使全部新增属性测试在 `wasm-gc`、`js` 与 `native` 三个后端上结果一致。
5. THE Production_Hardening SHALL 使每个新增属性测试运行不少于 100 次迭代。
6. WHEN 完成任一方向的加固修改，THE Production_Hardening SHALL 通过 `moon info`、`moon fmt` 与 `moon test` 校验。
