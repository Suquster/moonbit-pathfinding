# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **LSP 方向（方向五：LSP_Binding / LSP_Server）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有两个子包的公开类型与 API——协议层 `lsp_binding`（最小 JSON 值模型 `Json`、消息标识 `Id`、错误对象 `RpcError` 与标准错误码、消息枚举 `JsonRpcMessage`、方法路由 `Router`，以及 `decode_message`/`encode_message`/`dispatch`），与能力层 `lsp_server`（`Position`/`Range`/`Location`/`TextDocument`/`Diagnostic`/`CompletionItem`/`Hover`/`ServerCapabilities`/`InitializeParams`，五个纯函数处理器 `on_initialize`/`on_did_change`/`on_completion`/`on_definition`/`on_hover`，key=value DSL 静态分析器 `analyze` 与 `capabilities_to_json`/`publish_diagnostics_notification`/`position_from_json`），并在既有「字节 → JSON-RPC 消息 → 分发」与「DSL 文档 → 分析 → 诊断/补全/定义/悬停」两条流水线之上，扩展为一套对标 Microsoft Language Server Protocol、JSON-RPC 2.0 规范与主流语言服务器实现的旗舰级 LSP 消息与文档模型库。

旗舰目标聚焦十条主线：

- **完整 LSP 生命周期状态机**：`initialize → initialized → shutdown → exit` 的握手与状态转移；`shutdown` 后拒绝一切非 `exit` 请求（返回 InvalidRequest）；服务端能力按客户端声明的 `capabilities` 协商裁剪。
- **JSON-RPC 协议层增强**：`Content-Length` 头部帧（header framing）的读写、批量请求（batch array）、请求取消（`$/cancelRequest`）、请求—响应的 `id` 关联；在不改变既有 `decode`/`encode`/`dispatch` 往返与错误码语义的前提下旁路扩展。
- **增量文档同步**：`TextDocumentSyncKind`（Full / Incremental），将 `range + text` 的 `contentChanges` 应用到文档并维护文档版本号；增量应用结果与等价的全量替换逐字符一致。
- **位置编码与坐标换算**：UTF-16（LSP 默认）/ UTF-8 / UTF-32 三种位置编码的协商与换算；行列 `Position` 与字节/码元 `offset` 的双向换算且往返一致；多字节与代理对字符的列号计算正确。
- **更多语言能力**：在 DSL 分析器之上扩展 `documentSymbol`、`workspace/symbol`、`textDocument/references`、`rename`（产出 `WorkspaceEdit`）、`formatting`、`codeAction`、`signatureHelp`、`semanticTokens`、`foldingRange`、`documentHighlight`。
- **诊断模型**：push（`textDocument/publishDiagnostics`）与 pull（`textDocument/diagnostic`）两种模型并存，且诊断对同一文档具有确定性。
- **性能基准**：`benches/` 覆盖 decode/encode/dispatch、大文档 analyze、增量同步应用、references/rename，含回归基线 guard，native 后端前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
- **可解释性**：paper-to-code 可追溯（LSP 规范、JSON-RPC 2.0 规范、UTF-16 位置编码），并与 rust-analyzer、gopls、tower-lsp 与 vscode-languageserver-node 的协议/能力模型对比，显式声明实现边界。
- **端到端实战 demo**：一段贯穿文档与基准的会话脚本，驱动 DSL 文档完整走一遍。
- **质量门禁**：完整属性测试、三后端（`wasm-gc`/`js`/`native`）一致性、`README.mbt.md` 可执行文档扩充、自 `0.1.0` 起的独立 SemVer 推进与 `release_info_with_gates` 发布门禁。

本规格承袭仓库统一质量基线（见 Requirement 11），并复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。本方向区分 `lsp_binding`（协议层）与 `lsp_server`（能力层）两个子包，二者各自推进独立 SemVer，并继续作为单一发布单元以 "lsp" 名义统一登记发布元数据。

---

## 术语表（Glossary）

- **LSP 方向（LSP Direction）**：方向五整体，由协议层 `lsp_binding` 与能力层 `lsp_server` 两个子包构成。
- **LSP_Binding**：协议层子包系统（`src/lsp_binding`），承载 JSON-RPC 2.0 的消息类型、编解码与分发框架，是本文档协议层验收标准的主体系统。
- **LSP_Server**：能力层子包系统（`src/lsp_server`），构建于 LSP_Binding 之上，承载生命周期、文档同步、位置换算与语言能力，是本文档能力层验收标准的主体系统。
- **LSP_Suite**：作为单一发布单元的方向五整体（LSP_Binding + LSP_Server），是基准、可解释性、端到端 demo、向后兼容与质量门禁等横切验收标准的主体系统。
- **LSP（Language Server Protocol）**：Microsoft 定义的语言服务器协议，规定编辑器与语言服务器之间基于 JSON-RPC 2.0 的消息交互。
- **JSON-RPC 2.0**：本协议层遵循的远程过程调用规范，定义请求（Request）、响应（Response）、通知（Notification）三类消息及标准错误码。
- **Json（JSON 值模型）**：LSP_Binding 内最小、自包含的 JSON 值类型（`JNull`/`JBool`/`JNum`/`JStr`/`JArr`/`JObj`），`JNum` 保留原始字面量文本以保证往返无损。
- **JsonRpcMessage（消息）**：JSON-RPC 消息枚举，含 `Request(id, method, params)`、`Response(id, result?, error?)`、`Notification(method, params)`。
- **Id（消息标识）**：JSON-RPC 消息标识，含 `IdNum(Int)`/`IdStr(String)`/`IdNull` 三个变体。
- **RpcError（错误对象）**：JSON-RPC 错误对象，含 `code`/`message`/`data?`。
- **标准错误码（Standard Error Codes）**：JSON-RPC 2.0 预定义错误码，含 `parse_error_code`(-32700)、`invalid_request_code`(-32600)、`method_not_found_code`(-32601)、`invalid_params_code`(-32602)、`internal_error_code`(-32603)。
- **Router（方法路由）**：按 `method` 名将消息分发到能力处理器的路由表，提供 `register`/`lookup`。
- **decode_message / encode_message / dispatch**：协议层既有高层接口——字节解码为消息、消息编码为字节、按 method 分发；本规格冻结其既有签名与语义。
- **Content-Length 头部帧（Header Framing）**：LSP 传输约定，每条消息前置 `Content-Length: <字节数>\r\n\r\n` 头部后接 JSON 正文，用于在字节流中切分消息边界。
- **批量请求（Batch Request）**：JSON-RPC 顶层为数组的请求，承载多条请求/通知，按出现顺序逐条处理并将各响应汇集为响应数组。
- **请求取消（`$/cancelRequest`）**：LSP 通知，携带待取消请求的 `id`，请求该 `id` 对应的进行中请求被取消。
- **id 关联（Request-Response Correlation）**：响应的 `id` 必与触发它的请求 `id` 相等，用于将响应匹配回请求。
- **生命周期状态机（Lifecycle State Machine）**：服务端会话状态的有限状态机，状态含 `Uninitialized`/`Initializing`/`Initialized`/`ShuttingDown`/`Exited`，由 `initialize`/`initialized`/`shutdown`/`exit` 驱动转移。
- **能力协商（Capability Negotiation）**：`initialize` 时服务端依据客户端声明的 `capabilities` 裁剪并回报自身支持的能力集。
- **TextDocument（文本文档）**：一份文档，含资源标识 `uri` 与全文 `text`；深化后附带文档版本号 `version`。
- **文档版本号（Document Version）**：随每次文档变更单调递增的整数，标识文档的某一具体版本。
- **TextDocumentSyncKind（文档同步类别）**：文档同步策略，含 `Full`（每次发送全文）与 `Incremental`（每次发送变更区间）。
- **contentChanges（内容变更）**：`didChange` 通知携带的变更列表；增量模式下每条含变更范围 `range` 与替换文本 `text`。
- **增量同步（Incremental Sync）**：按 `contentChanges` 将变更应用到文档现有文本得到新文本的过程。
- **全量替换（Full Replacement）**：以变更后全文整体替换文档文本的过程，作为增量同步的等价参照。
- **位置编码（Position Encoding）**：`Position.character` 列号所采用的码元单位，含 `UTF-16`（LSP 默认）/`UTF-8`/`UTF-32`。
- **Position（位置）**：文档位置，含 0 基行号 `line` 与 0 基列号 `character`（列号单位由位置编码决定）。
- **Range（范围）**：闭开区间 `[start, end)`（`end` 排他）的文档范围。
- **offset（偏移）**：从文档起始计的线性位置，单位由位置编码对应的码元决定。
- **代理对（Surrogate Pair）**：UTF-16 中以两个码元表示的、码位超出基本多文种平面（BMP）的字符。
- **documentSymbol（文档符号）**：当前文档内符号的列表（DSL 中即各键定义）。
- **workspace/symbol（工作区符号）**：按查询字符串在工作区（多文档）内检索匹配符号。
- **references（引用查找）**：查找某符号的全部出现（定义与引用）。
- **rename（重命名）**：将某符号的全部出现一致改名，产出 `WorkspaceEdit`。
- **WorkspaceEdit（工作区编辑）**：一组按文档归类的文本编辑（每条含 `range` 与替换 `newText`），描述重命名/代码动作的结果。
- **formatting（格式化）**：对文档文本按规范化规则重排，产出文本编辑列表。
- **codeAction（代码动作）**：针对诊断或选区提供的快速修复/重构动作。
- **signatureHelp（签名帮助）**：在调用位置展示可调用项的签名信息。
- **semanticTokens（语义着色标记）**：文档内 token 的语义分类序列，用于编辑器语义高亮。
- **foldingRange（折叠区间）**：文档内可折叠的区间（如块级结构）。
- **documentHighlight（文档内高亮）**：当前文档内与光标处符号相关的全部出现的高亮范围。
- **push 诊断（Push Diagnostics）**：服务端主动经 `textDocument/publishDiagnostics` 通知推送诊断的模型。
- **pull 诊断（Pull Diagnostics）**：客户端经 `textDocument/diagnostic` 请求拉取诊断的模型。
- **诊断确定性（Diagnostic Determinism）**：对同一文档的分析产出逐条相同（顺序与内容一致）的诊断序列。
- **Analysis（分析结果）**：DSL 文档的分析产物，含 `uri`、符号表 `symbols`、引用表 `references` 与诊断列表 `diagnostics`。
- **Symbol / Reference（符号 / 引用）**：DSL 中的键定义（名称/范围/值）与值中的 `${key}` 引用（名称/范围）。
- **往返（Round-Trip）**：互逆操作的复合为恒等，如消息 `decode(encode(m)) == m`、位置 `offset ↔ Position` 互转后不变、增量与全量等价。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：完整 LSP 生命周期状态机

**用户故事（User Story）：** 作为对接编辑器的开发者，我想要服务端实现完整的 `initialize → initialized → shutdown → exit` 生命周期并按客户端能力协商裁剪服务端能力，以便会话握手与关闭遵循 LSP 规范且行为可预测。

#### 验收标准（Acceptance Criteria）

1. WHEN 在 `Uninitialized` 状态收到 `initialize` 请求，THE LSP_Server SHALL 转入 `Initializing` 状态并返回携带协商后服务端能力的 `initialize` 响应。
2. WHEN 在 `Initializing` 状态收到 `initialized` 通知，THE LSP_Server SHALL 转入 `Initialized` 状态。
3. IF 在 `Uninitialized` 状态收到除 `initialize` 之外的任何请求，THEN THE LSP_Server SHALL 返回携带 `invalid_request_code` 的错误响应且不改变会话状态。
4. WHEN 在 `Initialized` 状态收到 `shutdown` 请求，THE LSP_Server SHALL 转入 `ShuttingDown` 状态并返回结果为 null 的成功响应。
5. IF 在 `ShuttingDown` 状态收到除 `exit` 之外的任何请求，THEN THE LSP_Server SHALL 返回携带 `invalid_request_code` 的错误响应且不改变会话状态。
6. WHEN 收到 `exit` 通知，THE LSP_Server SHALL 转入 `Exited` 状态，并在先前已收到 `shutdown` 时报告退出码 `0`、否则报告退出码 `1`。
7. WHEN 处理 `initialize` 的能力协商，THE LSP_Server SHALL 仅声明客户端 `capabilities` 所支持的能力子集，对客户端未声明的能力不予声明。
8. FOR ALL 由生成器产生的生命周期事件序列，THE LSP_Server SHALL 满足状态机合法转移性质：状态仅经声明的合法转移变化，且在 `shutdown` 之后对任何非 `exit` 请求均以 `invalid_request_code` 拒绝（lifecycle legal-transition，以 PBT 验证）。

---

### Requirement 2：JSON-RPC 协议层增强

**用户故事（User Story）：** 作为实现传输层的开发者，我想要 `Content-Length` 头部帧、批量请求、请求取消与请求—响应 id 关联，以便在字节流上正确切分消息、批量处理并管理进行中的请求。

#### 验收标准（Acceptance Criteria）

1. WHEN 对一条消息做带帧编码，THE LSP_Binding SHALL 输出 `Content-Length: <正文字节数>\r\n\r\n` 头部后接 JSON 正文字节。
2. WHEN 从含 `Content-Length` 头部帧的字节流读取消息，THE LSP_Binding SHALL 按头部声明的字节数切分出正文并将其解码为 `JsonRpcMessage`。
3. IF 头部帧缺少 `Content-Length` 字段、其值非非负整数或正文长度不足，THEN THE LSP_Binding SHALL 返回携带 `parse_error_code` 的错误且不产生部分构造的消息。
4. WHEN 解码顶层为数组的批量请求，THE LSP_Binding SHALL 按出现顺序将每个元素解码为请求或通知，并将各请求的响应按对应顺序汇集为响应数组。
5. WHEN 收到携带某 `id` 的 `$/cancelRequest` 通知，THE LSP_Binding SHALL 将该 `id` 标记为已取消并对相应进行中请求返回携带请求取消错误码的错误响应。
6. WHEN `dispatch` 将一条请求路由到已注册处理器，THE LSP_Binding SHALL 返回该处理器的结果，且其响应 `id` 与请求 `id` 相等。
7. IF `dispatch` 收到 `method` 未注册的请求，THEN THE LSP_Binding SHALL 合成携带 `method_not_found_code` 的错误响应且其 `id` 与请求 `id` 相等。
8. FOR ALL 由生成器产生的 `JsonRpcMessage`，THE LSP_Binding SHALL 满足消息往返性质：`decode_message(encode_message(m))` 得到与 `m` 相等的消息（message round-trip，以 PBT 验证）。
9. FOR ALL 由生成器产生的请求消息与路由表，THE LSP_Binding SHALL 满足分发正确性性质：method 命中时调用对应处理器并返回其结果，未命中时返回 `id` 一致的 `method_not_found_code` 错误响应（dispatch correctness，以 PBT 验证）。
10. FOR ALL 由生成器产生的请求/通知序列，THE LSP_Binding SHALL 满足批量逐条处理性质：批量请求的响应数组与对各元素逐条分发所得响应按序一一相等（batch per-element processing，以 PBT 验证）。

---

### Requirement 3：增量文档同步

**用户故事（User Story）：** 作为编辑大文档的用户，我想要服务端支持 Full 与 Incremental 两种文档同步并维护版本号，以便编辑器只发送变更区间即可让服务端文档与客户端保持一致。

#### 验收标准（Acceptance Criteria）

1. WHERE 文档同步类别为 `Full`，WHEN 收到 `didChange` 通知，THE LSP_Server SHALL 以通知携带的全文整体替换文档文本。
2. WHERE 文档同步类别为 `Incremental`，WHEN 收到含 `range` 与替换文本的 `contentChanges`，THE LSP_Server SHALL 按各变更范围将替换文本应用到文档现有文本得到新文本。
3. WHEN 一份文档被成功变更，THE LSP_Server SHALL 将该文档版本号更新为变更通知携带的版本号。
4. WHEN 同一 `didChange` 通知携带多条 `contentChanges`，THE LSP_Server SHALL 按其在通知中出现的先后顺序依次应用各变更。
5. IF 某条增量变更的范围越出文档当前文本边界，THEN THE LSP_Server SHALL 报告携带定位信息的错误且不改变文档文本。
6. FOR ALL 由生成器产生的（初始文本, 增量变更序列）对，THE LSP_Server SHALL 满足增量与全量等价性质：依次应用增量变更所得文本与以变更后全文做全量替换所得文本逐字符相等（incremental/full equivalence，以 PBT 验证）。

---

### Requirement 4：位置编码与坐标换算

**用户故事（User Story）：** 作为处理含多字节字符文档的开发者，我想要在 UTF-16/UTF-8/UTF-32 位置编码间协商与换算、并在行列 `Position` 与线性 `offset` 间双向换算，以便光标位置在含代理对的文本中仍被正确解释。

#### 验收标准（Acceptance Criteria）

1. WHEN `initialize` 时客户端声明其支持的位置编码集，THE LSP_Server SHALL 选定客户端与服务端共同支持的某一位置编码，并在无显式声明时回退到 `UTF-16`。
2. WHEN 给定文本与某 `Position`，THE LSP_Server SHALL 在该位置编码下将该 `Position` 换算为对应的线性 `offset`。
3. WHEN 给定文本与某线性 `offset`，THE LSP_Server SHALL 在该位置编码下将该 `offset` 换算为对应的行列 `Position`。
4. WHEN 某行包含基本多文种平面外（含代理对）的字符，THE LSP_Server SHALL 在 `UTF-16` 下按 2 个码元、在 `UTF-8` 下按其字节数、在 `UTF-32` 下按 1 个码元计入该字符对列号的贡献。
5. WHEN 在两种位置编码间换算同一文本中的同一位置，THE LSP_Server SHALL 产出在两种编码下指向同一字符边界的等价 `Position`。
6. FOR ALL 由生成器产生的（文本, 位置编码, 文本内有效位置）三元组，THE LSP_Server SHALL 满足 Position↔offset 往返性质：`offset_to_position(position_to_offset(p)) == p`（position/offset round-trip，以 PBT 验证）。
7. FOR ALL 由生成器产生的（含多字节字符文本, 文本内有效位置）对，THE LSP_Server SHALL 满足跨编码换算往返性质：将位置从源编码换算到目标编码再换算回源编码，得到与原位置相等的结果（cross-encoding round-trip，以 PBT 验证）。

---

### Requirement 5：扩展语言能力

**用户故事（User Story）：** 作为使用语言服务器的开发者，我想要在 DSL 分析器之上获得文档符号、工作区符号、引用查找、重命名、格式化、代码动作、签名帮助、语义着色、折叠区间与文档内高亮，以便我能在编辑 DSL 文档时获得完整的编辑器智能能力。

#### 验收标准（Acceptance Criteria）

1. WHEN 请求 `documentSymbol`，THE LSP_Server SHALL 返回当前文档中全部键定义符号，各项含其名称与定义范围。
2. WHEN 以查询字符串请求 `workspace/symbol`，THE LSP_Server SHALL 返回工作区内名称匹配该查询的符号及其所属文档定位。
3. WHEN 在某符号处请求 `textDocument/references`，THE LSP_Server SHALL 返回该符号的全部出现（含其定义与对其的全部引用）的位置集合。
4. WHEN 在某符号处请求 `rename` 并给定新名，THE LSP_Server SHALL 返回一个将该符号全部出现替换为新名的 `WorkspaceEdit`。
5. WHEN 请求 `formatting`，THE LSP_Server SHALL 返回一组将文档规范化（如统一 `key = value` 的等号周边空白）的文本编辑。
6. WHEN 在某条诊断处请求 `codeAction`，THE LSP_Server SHALL 返回针对该诊断的可用代码动作列表。
7. WHEN 请求 `signatureHelp`、`semanticTokens`、`foldingRange` 或 `documentHighlight`，THE LSP_Server SHALL 分别返回签名信息、语义着色标记序列、折叠区间集合与当前文档内相关符号的高亮范围集合。
8. WHEN 在某符号处请求 `textDocument/definition`，THE LSP_Server SHALL 返回该符号定义所在的位置，且该位置应包含于同一符号的 `references` 结果中。
9. FOR ALL 由生成器产生的 DSL 文档与其中某已定义键，THE LSP_Server SHALL 满足引用—定义自洽性质：该键的定义位置必属于其 `references` 结果，且 `references` 结果中的每个位置都位于该键的某次出现上（reference/definition consistency，以 PBT 验证）。
10. FOR ALL 由生成器产生的 DSL 文档、其中某已定义键与一个未被占用的新名，THE LSP_Server SHALL 满足重命名完整性性质：应用 `rename` 的 `WorkspaceEdit` 后，原名的全部出现均变为新名、其余符号文本不变，且对结果再次分析时新名的出现数等于原名原出现数（rename completeness，以 PBT 验证）。

---

### Requirement 6：诊断模型（push 与 pull）

**用户故事（User Story）：** 作为依赖实时反馈的用户，我想要服务端同时支持主动推送（publishDiagnostics）与按需拉取（textDocument/diagnostic）两种诊断模型，且诊断结果稳定可复现，以便不同客户端策略下都能获得一致的诊断。

#### 验收标准（Acceptance Criteria）

1. WHEN 文档变更后发布诊断，THE LSP_Server SHALL 构造携带文档 `uri` 与诊断数组的 `textDocument/publishDiagnostics` 通知。
2. WHEN 收到 `textDocument/diagnostic` 拉取请求，THE LSP_Server SHALL 返回对应文档当前分析所得的诊断集合作为响应结果。
3. WHEN 对同一文档分别经 push 与 pull 两种模型获取诊断，THE LSP_Server SHALL 产出彼此相等的诊断集合。
4. WHEN 将一条诊断编码为 JSON，THE LSP_Server SHALL 输出其范围、规范严重级别码（Error=1/Warning=2/Information=3/Hint=4）与消息。
5. FOR ALL 由生成器产生的 DSL 文档，THE LSP_Server SHALL 满足诊断确定性性质：对同一文档多次分析得到逐条相同（顺序与内容一致）的诊断序列（diagnostic determinism，以 PBT 验证）。

---

### Requirement 7：性能基准（benches/）

**用户故事（User Story）：** 作为关心消息处理与分析吞吐的开发者，我想要可复现的基准证据，以便我能度量编解码、分发、大文档分析、增量同步与引用/重命名等负载下的表现并防止性能回归。

#### 验收标准（Acceptance Criteria）

1. THE LSP_Suite SHALL 在 `benches/` 下提供基准包，覆盖 decode/encode/dispatch、大文档 `analyze`、增量同步应用与 references/rename 五类工作负载。
2. WHEN 运行基准，THE LSP_Suite SHALL 输出包含机器标识、后端目标、输入规模与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE LSP_Suite SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告。
4. THE LSP_Suite SHALL 在基准文档中记录运行命令，且在 native 后端要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

### Requirement 8：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键协议与坐标规则可追溯到规范并与主流语言服务器实现对比，以便我能理解设计依据与取舍。

#### 验收标准（Acceptance Criteria）

1. THE LSP_Suite SHALL 在文档中将消息结构、生命周期与能力协商追溯到 Microsoft Language Server Protocol 规范。
2. THE LSP_Suite SHALL 在文档中将请求/响应/通知模型与标准错误码追溯到 JSON-RPC 2.0 规范。
3. THE LSP_Suite SHALL 在文档中将列号计量与 UTF-16/UTF-8/UTF-32 位置编码换算追溯到 LSP 的位置编码定义。
4. THE LSP_Suite SHALL 在文档中提供与 rust-analyzer、gopls、tower-lsp 及 vscode-languageserver-node 的协议/能力模型对比，覆盖传输与帧处理、能力协商、文档同步策略与诊断模型的差异。
5. WHERE 本库不支持某类构造（如真实 stdio/socket 传输、通用语言分析或工作区多根管理），THE LSP_Suite SHALL 在文档中显式声明该实现边界及其理由——本方向停留在消息与文档模型层，分析针对内置 DSL 而非通用语言。

---

### Requirement 9：端到端实战 demo

**用户故事（User Story）：** 作为评估该库可用性的开发者，我想要一段贯穿文档与基准的实战会话脚本，以便我能看到从握手到各项语言能力再到关闭的端到端用法。

#### 验收标准（Acceptance Criteria）

1. THE LSP_Suite SHALL 提供一段贯穿文档与基准的实战会话脚本，依次覆盖 `initialize` → `didOpen` → 增量 `didChange` → 请求 `diagnostics`/`completion`/`definition`/`references`/`rename`/`hover` → `shutdown`/`exit`。
2. WHEN 运行该会话脚本，THE LSP_Suite SHALL 驱动一份内置 DSL 文档完整走过上述全部步骤并产出确定性结果。
3. WHEN 该会话脚本执行增量 `didChange` 后再请求诊断，THE LSP_Suite SHALL 使所得诊断与对变更后全文做全量替换后的诊断相等。
4. THE LSP_Suite SHALL 在 `README.mbt.md` 可执行文档中以该会话脚本演示端到端流程，且全部示例通过 `moon test *.mbt.md` 验证。

---

### Requirement 10：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有代码在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE LSP_Binding SHALL 保留既有公开类型 `Json`、`Id`、`RpcError`、`JsonRpcMessage`、`Router` 与既有标准错误码常量（`parse_error_code`/`invalid_request_code`/`method_not_found_code`/`invalid_params_code`/`internal_error_code`）的现有签名与语义。
2. THE LSP_Binding SHALL 保留既有函数 `decode_message`、`encode_message`、`dispatch` 与 `Router::new`/`register`/`lookup`、`error_response`、`RpcError::new`/`with_data` 的现有公开签名与行为，使既有裸 JSON 正文（无头部帧）的解码、编码与分发结果不变。
3. THE LSP_Server SHALL 保留既有公开类型 `Position`、`Range`、`Location`、`TextDocument`、`DiagnosticSeverity`、`Diagnostic`、`CompletionItemKind`、`CompletionItem`、`Hover`、`InitializeParams`、`ServerCapabilities`、`Symbol`、`Reference`、`Analysis` 及其现有字段与语义。
4. THE LSP_Server SHALL 保留既有函数 `on_initialize`、`on_did_change`、`on_completion`、`on_definition`、`on_hover`、`analyze`、`capabilities_to_json`、`publish_diagnostics_notification`、`position_from_json` 的现有公开签名与行为。
5. WHERE 新增能力需要扩展行为，THE LSP_Suite SHALL 以新增 API（如头部帧编解码、批量分发、生命周期状态机、增量同步、位置编码换算、扩展语言能力、pull 诊断）的方式提供，而不破坏既有 API 的调用方。
6. THE LSP_Suite SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板。
7. THE LSP_Suite SHALL 复用 `@release_meta` 的 `DirectionRelease`/`QualityGates`/SemVer 模型登记本方向发布元数据，并保持 `release_info`/`release_info_with_gates`/`lsp_version`/`lsp_name`/`lsp_changelog_path` 的现有语义。
8. FOR ALL 由生成器产生的、既有 DSL 文法下的文档，THE LSP_Server SHALL 满足既有分析不变性质：深化后 `analyze` 对既有文法文档产出的符号、引用与诊断与 `0.1.0` 行为相等（legacy analyze invariance，以 PBT 验证）。

---

### Requirement 11：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE LSP_Suite SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE LSP_Suite SHALL 为本规格的核心正确性属性（JSON-RPC 消息往返、分发正确性、批量逐条处理、生命周期合法转移、增量与全量等价、Position↔offset 往返、跨编码换算往返、引用—定义自洽、重命名完整性、诊断确定性、既有分析不变）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. WHEN 对非法字节或非法消息解码，THE LSP_Binding SHALL 返回携带恰当标准错误码的 `RpcError` 且不通过 panic/abort 终止进程，也不产生部分构造的消息。
4. THE LSP_Suite SHALL 扩充两个子包的 `README.mbt.md` 可执行文档，使其覆盖头部帧编解码、批量与取消、生命周期、增量同步、位置编码换算、扩展语言能力、诊断模型与端到端 demo，且全部示例通过 `moon test *.mbt.md` 验证。
5. WHEN 运行三后端测试中的 native 后端，THE LSP_Suite SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
6. THE LSP_Suite SHALL 使 `lsp_binding`（协议层）与 `lsp_server`（能力层）各自推进独立 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新各自独立的 `CHANGELOG.md`，同时继续作为单一发布单元以 "lsp" 名义登记发布元数据。
7. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE LSP_Suite SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
