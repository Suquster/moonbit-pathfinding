# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Logging_Library（方向七）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开类型与 API（级别模型 `Level` 及其 `rank`/`is_enabled`/`label`/`from_label`、结构化取值 `Value`、事件 `Event`、跨度 `Span`、标识 `SpanId`/`TraceId`、上下文 `TraceContext`，以及函数 `log`/`set_threshold`/`current_threshold`/`enter_span`/`exit_span`/`span_duration`/`begin_trace`/`capture_context`/`child_context`/`with_context`/`format_json`/`parse_json_log`/`captured_events`/`finished_spans`/`current_span`/`current_trace`/`reset_logger`），并在既有「结构化字段 → 级别过滤 → span 树与时长 → trace 上下文传播 → JSON 往返」流水线之上，扩展为一套对标 Rust `tracing`、`slog`、Uber `zap` 与 OpenTelemetry SDK 的旗舰级结构化日志与分布式追踪库。

旗舰目标聚焦以下主线：

- **嵌套结构化取值**：在既有标量取值 `VStr`/`VInt`/`VBool`/`VFloat` 之上扩展嵌套对象与数组取值，并使 JSON 往返覆盖嵌套结构。
- **多 sink 与多 formatter**：可插拔输出汇（sink）与格式器（JSON、logfmt、人类可读 pretty），同一事件经不同 formatter 确定性渲染，且 formatter 与 parser 构成往返。
- **采样与限流**：确定性可复现的概率采样与按级别/字段的限流，且采样决策在同一 trace 内一致。
- **过滤与路由**：按级别、目标（target/module）与字段谓词过滤，按级别或字段路由到不同 sink，并支持 EnvFilter 风格指令。
- **OpenTelemetry 风格 span 语义**：span 属性、span 事件、span 状态与 span kind，与既有 span 树兼容。
- **分布式上下文传播**：W3C Trace Context `traceparent` 的注入（inject）与提取（extract），跨进程边界保持 trace 关联。
- **脱敏 / PII 过滤**：按字段名或谓词对敏感字段做掩码，保证脱敏后不残留原值且字段集合结构不变。
- **指标派生**：从事件流派生计数与直方图等聚合，确定性可复现。
- **可解释性**：paper-to-code 可追溯（Google Dapper、OpenTelemetry 规范、W3C Trace Context、结构化日志 / logfmt），与 Rust `tracing`、`slog`、Uber `zap`、OpenTelemetry SDK 的模型对比，并显式声明实现边界。
- **质量门禁**：完整属性测试、三后端（`wasm-gc`/`js`/`native`）一致性、`README.mbt.md` 可执行文档扩充、性能基准与回归基线 guard，以及独立 SemVer 版本推进。

本规格承袭仓库统一质量基线（见 Requirement 13），并复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **Logging_Library**：本方向的结构化日志与分布式追踪库系统（子包 `src/logging`），是本文档所有验收标准的主体系统。
- **Level（级别）**：日志严重程度，自低到高为 `Trace` < `Debug` < `Info` < `Warn` < `Error`，由 `rank` 给出严重程度序数。
- **Event（事件）**：一条日志记录，含逻辑时间戳 `ts`、级别 `level` 与结构化字段集合 `fields : Map[String, Value]`。
- **Value（结构化取值）**：日志字段取值；既有标量变体为 `VStr`/`VInt`/`VBool`/`VFloat`。
- **嵌套取值（Nested Value）**：本规格新增的复合取值，含对象型 `VMap`（键值映射）与数组型 `VList`（有序元素序列），可任意层级嵌套标量与复合取值。
- **Span（跨度）**：一段有起止的操作区间，含唯一 `SpanId`、可选父 `SpanId`、起止逻辑时间戳；子 span 关联父 span 形成 **span 树**。
- **SpanId / TraceId**：分别为 span 与 trace 的进程内标识，由单调递增的 `Int64` 承载。
- **TraceContext（trace 上下文）**：一次逻辑链路的上下文快照，含 `trace` 与可选激活 `span`，用于跨任务边界传播。
- **逻辑时钟（Logical Clock）**：不依赖墙钟的单调递增时间戳源，保证三后端对同一调用序列产出逐位一致的时间戳。
- **Sink（输出汇）**：接收已发射事件并将其落地（如累积到内存缓冲）的可插拔输出端点；本库以内存模型表达，不接真实 IO。
- **Formatter（格式器）**：把一条 `Event` 渲染为文本表示的纯函数；本规格提供 JSON、logfmt 与 pretty 三种内置格式器。
- **JSON formatter（JSON 格式器）**：将事件渲染为 JSON 文本、字段按键名升序稳定排序的格式器，即既有 `format_json` 的能力扩展。
- **logfmt formatter（logfmt 格式器）**：将事件渲染为 `key=value` 空格分隔行的格式器，对应 logfmt 约定。
- **pretty formatter（人类可读格式器）**：将事件渲染为面向终端阅读的对齐文本的格式器。
- **Parser（解析器）**：把某 formatter 的文本表示还原为等价 `Event` 的逆函数；JSON 解析器即既有 `parse_json_log` 的能力扩展，logfmt 解析器为本规格新增。
- **Formatter↔Parser 往返（Format Round-Trip）**：对同一事件先格式化再解析，所得事件与原事件在该 formatter 表示域内逐字段等价。
- **Sampling（采样）**：依据采样率与确定性 `Rng` 对事件或 trace 做保留/丢弃判定的机制；同一采样配置与种子下结果可复现。
- **采样率（Sampling Rate）**：取值区间为 `[0.0, 1.0]` 的概率参数，`0.0` 表示全弃、`1.0` 表示全采。
- **trace 内采样一致性（Trace-Coherent Sampling）**：同一 trace 的采样判定一致——该 trace 的全部事件要么全部被采样、要么全部被丢弃。
- **Rate limiting（限流）**：在给定逻辑时间窗内限制某级别或某字段键所允许通过的事件条数的机制，超出配额的事件被丢弃。
- **Filter（过滤器）**：对事件给出保留/丢弃判定的谓词，可基于级别、目标或字段。
- **target（目标 / 模块）**：标注事件来源模块/子系统的字段，用于 EnvFilter 风格的分模块级别控制。
- **EnvFilter 指令（EnvFilter Directive）**：形如 `target=level` 的过滤指令集合，为各 target 指定独立的最低级别阈值，并提供未匹配 target 的全局兜底阈值。
- **Router（路由器）**：依据级别或字段谓词将事件分发到一个或多个 sink 的机制。
- **span 属性（Span Attribute）**：附加在 span 上的键值字段（`Map[String, Value]`），描述该 span 的静态/半静态特征，对应 OpenTelemetry 的 span attributes。
- **span 事件（Span Event）**：在 span 生命周期内某时刻记录的带名称、时间戳与字段的标注点，对应 OpenTelemetry 的 span events。
- **span 状态（Span Status）**：span 结束时的结果状态，取值为 `Unset`/`Ok`/`Error`，对应 OpenTelemetry 的 span status。
- **span kind（span 类别）**：span 的角色类别，取值为 `Internal`/`Server`/`Client`/`Producer`/`Consumer`，对应 OpenTelemetry 的 span kind。
- **W3C Trace Context（W3C 追踪上下文）**：W3C 标准的跨进程追踪上下文传播规范，核心载体为 `traceparent` 头。
- **traceparent**：W3C Trace Context 的核心字段，文本形如 `00-<trace-id>-<parent-id>-<flags>`，含版本、16 字节 trace-id、8 字节 span-id 与 1 字节 trace-flags（其最低位为 sampled 标志）。
- **inject（注入）**：将当前 trace 上下文序列化为 `traceparent` 文本的操作。
- **extract（提取）**：将 `traceparent` 文本解析回 trace 上下文的操作。
- **Redaction（脱敏 / PII 过滤）**：依据字段名集合或字段谓词，将敏感字段取值替换为掩码标记的处理，PII 即个人可识别信息。
- **掩码标记（Redaction Mask）**：脱敏后替换原值的固定占位取值（如字符串 `"[REDACTED]"`），不泄露原值任何片段。
- **Metrics derivation（指标派生）**：从已发射事件流计算聚合度量的处理，含按级别计数（counter）与按字段数值分桶的直方图（histogram）。
- **counter（计数器）**：对满足条件的事件计数所得的非负整数聚合。
- **histogram（直方图）**：按声明的边界把数值字段分入若干桶并计数所得的聚合。
- **确定性（Deterministic）**：给定相同输入（含相同 `Rng` 种子）产出逐位相同结果，且三后端一致。
- **往返（Round-Trip）**：序列化与解析互逆，或注入与提取互逆，使结果在对应表示域内与原值等价。
- **向后兼容（Backward Compatibility）**：既有 `0.1.0` 公开 API 的签名与行为保持不变，新能力以旁路新增 API 提供。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip`/`gen_bool`/`gen_int_range`/`rng_new` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：嵌套结构化取值与 JSON 往返

**用户故事（User Story）：** 作为记录复杂业务上下文的开发者，我想要日志字段取值支持嵌套对象与数组，以便我能以结构化方式表达层级数据，而不必把对象展平为字符串。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 在既有标量取值 `VStr`、`VInt`、`VBool`、`VFloat` 之外提供对象型嵌套取值 `VMap`（键值映射）与数组型嵌套取值 `VList`（有序元素序列）。
2. WHERE 某字段取值为 `VMap` 或 `VList`，THE Logging_Library SHALL 允许其元素为任意 `Value`（含标量取值与进一步嵌套的 `VMap`/`VList`）。
3. WHEN JSON 格式器渲染含嵌套取值的事件，THE Logging_Library SHALL 将 `VMap` 渲染为 JSON 对象、将 `VList` 渲染为 JSON 数组，且对象成员按键名升序稳定排序。
4. WHEN JSON 解析器解析含嵌套对象或数组的结构化日志文本，THE Logging_Library SHALL 将其还原为对应的 `VMap` 与 `VList` 取值。
5. THE Logging_Library SHALL 保留既有标量取值 `VStr`、`VInt`、`VBool`、`VFloat` 的现有 JSON 渲染与解析行为不变。
6. FOR ALL 由生成器产生的含任意嵌套深度取值的事件，THE Logging_Library SHALL 满足嵌套 JSON 往返性质：先 JSON 格式化再 JSON 解析所得事件与原事件逐字段相等（nested JSON round-trip，以 PBT 验证）。

---

### Requirement 2：多 sink 与多 formatter

**用户故事（User Story）：** 作为需要将日志以不同格式输出到不同目的地的开发者，我想要可插拔的 sink 与 formatter，以便我能用同一套事件同时产出 JSON、logfmt 与人类可读三种表示。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 提供 JSON、logfmt 与 pretty 三种内置格式器，每种格式器将一条 `Event` 渲染为对应文本表示。
2. WHEN 同一事件分别由不同格式器渲染，THE Logging_Library SHALL 对每种格式器产出由事件内容唯一确定的文本，且三后端逐字节一致。
3. WHEN logfmt 格式器渲染事件，THE Logging_Library SHALL 输出由 `key=value` 对以空格分隔构成的单行文本，并对含空格或特殊字符的取值施加引号与转义。
4. THE Logging_Library SHALL 提供可插拔 sink 抽象，使调用方能注册一个或多个 sink 接收已发射事件，并指定各 sink 使用的格式器。
5. WHEN 一条事件通过过滤进入输出阶段，THE Logging_Library SHALL 将该事件交付给全部已注册且其路由条件匹配的 sink。
6. THE Logging_Library SHALL 提供 logfmt 解析器，将 logfmt 文本还原为等价 `Event`。
7. FOR ALL 由生成器产生的标量字段事件，THE Logging_Library SHALL 满足 logfmt 往返性质：先 logfmt 格式化再 logfmt 解析所得事件与原事件逐字段相等（logfmt round-trip，以 PBT 验证）。

---

### Requirement 3：采样与限流

**用户故事（User Story）：** 作为在高吞吐服务中控制日志量的开发者，我想要确定性可复现的概率采样与按级别/字段的限流，以便我能在保留代表性样本的同时约束输出规模，并保证同一请求链路的采样结果一致。

#### 验收标准（Acceptance Criteria）

1. WHERE 配置了采样率，THE Logging_Library SHALL 依据该采样率与确定性 `Rng` 对事件做保留或丢弃判定。
2. WHEN 采样率为 `0.0`，THE Logging_Library SHALL 丢弃全部受采样约束的事件；WHEN 采样率为 `1.0`，THE Logging_Library SHALL 保留全部受采样约束的事件。
3. WHILE 多条事件归属同一 trace，THE Logging_Library SHALL 对该 trace 做一致的采样判定，使这些事件要么全部被采样、要么全部被丢弃。
4. WHEN 以相同采样配置与相同 `Rng` 种子重放同一事件序列，THE Logging_Library SHALL 产出逐条相同的采样判定结果。
5. WHERE 配置了限流，THE Logging_Library SHALL 在给定逻辑时间窗内限制指定级别或指定字段键所允许通过的事件条数，并丢弃超出配额的事件。
6. FOR ALL 由生成器产生的 trace 内事件集合，THE Logging_Library SHALL 满足 trace 内采样一致性：同一 trace 的全部事件采样判定相同（trace-coherent sampling，以 PBT 验证）。
7. FOR ALL 由生成器产生的采样率与事件流，THE Logging_Library SHALL 满足采样比例有界性质：被保留事件占比不超过采样率所允许的上界（sampling-ratio bound，以 PBT 验证）。

---

### Requirement 4：过滤与路由

**用户故事（User Story）：** 作为需要按模块与级别精细控制日志的开发者，我想要按级别、目标与字段谓词过滤并将事件路由到不同 sink，以便我能为不同子系统设定独立的可见性与去向。

#### 验收标准（Acceptance Criteria）

1. WHEN 事件级别低于其所属 target 的配置阈值，THE Logging_Library SHALL 丢弃该事件。
2. WHERE 提供了字段谓词过滤器，THE Logging_Library SHALL 仅保留其字段满足该谓词的事件。
3. WHEN 解析 EnvFilter 风格指令集合，THE Logging_Library SHALL 为每个 `target=level` 指令登记该 target 的最低级别阈值，并为未匹配任何指令的 target 应用全局兜底阈值。
4. IF EnvFilter 指令文本语法非法，THEN THE Logging_Library SHALL 返回携带定位信息的错误且不登记任何阈值。
5. WHEN 路由器依据级别或字段谓词分发一条事件，THE Logging_Library SHALL 将该事件交付给其条件匹配的全部 sink，并对无匹配 sink 的事件不做交付。
6. FOR ALL 由生成器产生的（EnvFilter 指令集, 事件）对，THE Logging_Library SHALL 满足过滤判定一致性：事件被保留当且仅当其级别不低于其 target 的有效阈值（filter-decision consistency，以 PBT 验证）。

---

### Requirement 5：OpenTelemetry 风格 span 语义

**用户故事（User Story）：** 作为构建可观测系统的开发者，我想要 span 支持属性、事件、状态与 kind，以便我能以 OpenTelemetry 兼容的语义描述操作区间，而仍复用既有 span 树与时长能力。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 允许为一个激活 span 设置键值属性（`Map[String, Value]`），并在该 span 结束记录中保留这些属性。
2. WHEN 在激活 span 上记录一个 span 事件，THE Logging_Library SHALL 为该事件保留其名称、逻辑时间戳与字段，并将其归属于当前 span。
3. THE Logging_Library SHALL 允许为一个 span 设置状态，取值为 `Unset`、`Ok` 或 `Error`，默认状态为 `Unset`。
4. THE Logging_Library SHALL 允许为一个 span 设置 kind，取值为 `Internal`、`Server`、`Client`、`Producer` 或 `Consumer`，默认 kind 为 `Internal`。
5. THE Logging_Library SHALL 保持既有 `enter_span`/`exit_span`/`span_duration` 的 span 树构建与时长计算行为不变，使属性、事件、状态与 kind 作为旁路扩展叠加其上。
6. FOR ALL 由生成器产生的 span 进入/退出序列，THE Logging_Library SHALL 满足 span 树父子不变量：每个非根 span 的父标识等于其进入时刻的激活 span 标识，且每个已结束 span 的时长非负（span-tree invariant，以 PBT 验证）。

---

### Requirement 6：W3C Trace Context 分布式上下文传播

**用户故事（User Story）：** 作为跨服务追踪请求的开发者，我想要将 trace 上下文注入与提取为 W3C `traceparent`，以便我能在跨进程边界保持同一 trace 的关联。

#### 验收标准（Acceptance Criteria）

1. WHEN 注入当前 trace 上下文，THE Logging_Library SHALL 产出形如 `00-<trace-id>-<parent-id>-<flags>` 的 `traceparent` 文本，其中 trace-id 为 32 位十六进制、parent-id 为 16 位十六进制、flags 为 2 位十六进制。
2. WHEN 提取一个语法合法的 `traceparent` 文本，THE Logging_Library SHALL 还原出其 trace-id、span-id 与 trace-flags 三个分量。
3. WHILE trace-flags 的最低位为 1，THE Logging_Library SHALL 将该上下文标记为已采样（sampled）。
4. IF `traceparent` 文本字段数量、分隔符或各分量长度不符合规范，THEN THE Logging_Library SHALL 返回提取失败且不产生部分构造的上下文。
5. THE Logging_Library SHALL 使提取所得上下文与既有 `TraceContext` 模型兼容，从而可经 `with_context` 在该上下文下继续记录事件并保持 trace 关联。
6. FOR ALL 由生成器产生的合法 trace 上下文，THE Logging_Library SHALL 满足 traceparent 往返性质：注入再提取所得 trace-id、span-id 与 flags 与原上下文相等（traceparent inject/extract round-trip，以 PBT 验证）。

---

### Requirement 7：脱敏 / PII 过滤

**用户故事（User Story）：** 作为处理含敏感信息日志的开发者，我想要按字段名或谓词对敏感字段做掩码，以便我能在保留日志结构的同时避免泄露 PII。

#### 验收标准（Acceptance Criteria）

1. WHERE 配置了敏感字段名集合，THE Logging_Library SHALL 在事件输出前将这些字段的取值替换为固定掩码标记。
2. WHERE 配置了字段谓词，THE Logging_Library SHALL 将满足该谓词的字段取值替换为固定掩码标记。
3. WHEN 对一条事件施加脱敏，THE Logging_Library SHALL 保持其字段键集合不变，仅替换被判定为敏感的字段取值。
4. WHEN 某敏感字段取值为嵌套 `VMap` 或 `VList`，THE Logging_Library SHALL 对该字段整体施加掩码，使其内部任何原始取值片段均不出现在输出中。
5. FOR ALL 由生成器产生的（敏感字段集, 事件）对，THE Logging_Library SHALL 满足脱敏完整性：脱敏后输出不包含任何敏感字段的原始取值，且字段键集合与脱敏前一致（redaction-completeness，以 PBT 验证）。

---

### Requirement 8：指标派生

**用户故事（User Story）：** 作为希望从日志直接得到聚合度量的开发者，我想要从事件流派生计数与直方图，以便我能在不接入独立指标系统时也获得确定性可复现的聚合视图。

#### 验收标准（Acceptance Criteria）

1. WHEN 对一组事件按级别派生计数，THE Logging_Library SHALL 为每个级别输出该级别事件的非负计数。
2. WHEN 对一组事件就某数值字段按声明的边界派生直方图，THE Logging_Library SHALL 将每条该字段为数值取值的事件计入其对应桶并输出各桶计数。
3. WHILE 某事件缺失目标数值字段或该字段非数值取值，THE Logging_Library SHALL 在直方图派生中跳过该事件而不计入任何桶。
4. FOR ALL 由生成器产生的事件流，THE Logging_Library SHALL 满足计数守恒性质：各级别计数之和等于输入事件总数（counter-conservation，以 PBT 验证）。
5. FOR ALL 由生成器产生的事件流与边界集，THE Logging_Library SHALL 满足派生确定性：对同一输入两次派生所得计数与直方图逐桶相等（metrics-determinism，以 PBT 验证）。

---

### Requirement 9：性能基准（benches/）

**用户故事（User Story）：** 作为关心日志开销的开发者，我想要可复现的基准证据，以便我能度量高频记录、格式化、采样判定与 span 进出等负载下的表现并防止性能回归。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 在 `benches/` 下提供基准包，覆盖高频 `log`、格式化（JSON 与 logfmt）、采样判定与 span 进入/退出四类工作负载。
2. WHEN 运行基准，THE Logging_Library SHALL 输出包含机器标识、后端目标、输入规模与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE Logging_Library SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告。
4. THE Logging_Library SHALL 在基准文档中记录运行命令，且在 native 后端要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

### Requirement 10：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键追踪与日志机制可追溯到规范并与主流方案对比，以便我能理解设计依据与取舍。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 在文档中将分布式追踪的 span 树与上下文传播模型追溯到 Google Dapper 论文。
2. THE Logging_Library SHALL 在文档中将 span 属性、span 事件、span 状态与 span kind 语义追溯到 OpenTelemetry 规范。
3. THE Logging_Library SHALL 在文档中将 `traceparent` 的格式与字段语义追溯到 W3C Trace Context 规范。
4. THE Logging_Library SHALL 在文档中将 logfmt 文本表示追溯到结构化日志 / logfmt 约定。
5. THE Logging_Library SHALL 在文档中提供与 Rust `tracing`、`slog`、Uber `zap` 及 OpenTelemetry SDK 的模型与权衡对比，覆盖结构化字段、span/scope 模型、采样与导出管线的差异。
6. WHERE 本库不实现某类能力（如真实网络/文件导出器、与 `moonbitlang/async` 的异步运行时耦合，仅停留在内存与字符串模型并以显式上下文传播模型替代异步任务局部存储），THE Logging_Library SHALL 在文档中显式声明该实现边界及其理由，而非隐式留白。

---

### Requirement 11：端到端实战 demo

**用户故事（User Story）：** 作为评估该库可用性的开发者，我想要一份贯穿文档与基准的实战追踪场景，以便我能看到从 span 嵌套到采样、脱敏、多格式输出与跨进程传播的端到端用法。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 提供一份贯穿文档与基准的实战请求处理链路 demo，至少覆盖嵌套 span 与属性、采样、脱敏、JSON 与 logfmt 输出以及 `traceparent` 的跨进程注入/提取。
2. WHEN 对该 demo 运行端到端流程，THE Logging_Library SHALL 依次完成 `begin_trace` → 嵌套 `enter_span`/`exit_span` 与属性/事件标注 → 采样与脱敏 → 多格式渲染 → `traceparent` 注入并由下游提取，并产出一致结果。
3. WHEN 该 demo 在父进程注入 `traceparent` 并在模拟下游进程提取后继续记录，THE Logging_Library SHALL 使下游事件与父进程事件归属同一 trace-id。
4. THE Logging_Library SHALL 在 `README.mbt.md` 可执行文档中以该 demo 演示上述端到端流程，且全部示例通过 `moon test *.mbt.md` 验证。

---

### Requirement 12：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有代码在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 保留既有公开类型 `Level`、`Value`、`Event`、`Span`、`SpanId`、`TraceId`、`TraceContext` 及其现有公开方法（`Level::rank`/`is_enabled`/`label`/`from_label`、`Event::new`）的签名与语义。
2. THE Logging_Library SHALL 保留既有函数 `log`、`set_threshold`、`current_threshold`、`enter_span`、`exit_span`、`span_duration`、`begin_trace`、`capture_context`、`child_context`、`with_context`、`format_json`、`parse_json_log`、`captured_events`、`finished_spans`、`current_span`、`current_trace`、`reset_logger` 的现有公开签名与行为。
3. WHERE 新增能力需要扩展行为，THE Logging_Library SHALL 以新增 API（如嵌套取值、多 sink/formatter、采样、限流、过滤路由、span 语义、traceparent、脱敏、指标派生）的方式提供，而不破坏既有 API 的调用方。
4. THE Logging_Library SHALL 保持既有 `format_json`/`parse_json_log` 对仅含标量字段事件的现有逐字节输出与解析行为不变。
5. THE Logging_Library SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板。
6. THE Logging_Library SHALL 复用 `@release_meta` 的 `DirectionRelease`/`QualityGates`/SemVer 模型登记本方向发布元数据，并保持 `release_info`/`release_info_with_gates` 的现有语义。
7. FOR ALL 由生成器产生的仅含标量字段事件，THE Logging_Library SHALL 满足既有 JSON 往返性质：`parse_json_log(format_json(e))` 得到与 `e` 相等的事件（legacy JSON round-trip，以 PBT 验证）。

---

### Requirement 13：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Logging_Library SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Logging_Library SHALL 为本规格的核心正确性属性（嵌套 JSON 往返、logfmt 往返、trace 内采样一致性、采样比例有界、过滤判定一致性、span 树父子不变量、span 时长非负、traceparent 注入/提取往返、脱敏完整性、计数守恒、指标派生确定性、既有 JSON 往返）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. IF 解析非法的结构化日志文本、非法的 `traceparent` 或非法的 EnvFilter 指令，THEN THE Logging_Library SHALL 返回失败结果且不产生部分构造的对象。
4. THE Logging_Library SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖嵌套取值、多 formatter、采样与限流、过滤与路由、span 语义、traceparent、脱敏、指标派生与端到端 demo，且全部示例通过 `moon test *.mbt.md` 验证。
5. WHEN 运行三后端测试中的 native 后端，THE Logging_Library SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
6. THE Logging_Library SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
7. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE Logging_Library SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
