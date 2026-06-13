# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 **方向五 LSP 骨架（`lsp_binding 0.1.0` + `lsp_server 0.1.0`）** 之上，做**增量式、严格向后兼容**的旗舰级深化，目标对标 Microsoft **Language Server Protocol（LSP）** 规范、**JSON-RPC 2.0** 规范与主流语言服务器实现（rust-analyzer、gopls、tower-lsp、vscode-languageserver-node）。

核心原则一句话：**既有两个子包的全部公开类型与函数（`Json`/`Id`/`RpcError`/`JsonRpcMessage`/`Router` 与 `decode_message`/`encode_message`/`dispatch`/`error_response`；`Position`/`Range`/`Location`/`TextDocument`/`Diagnostic`/`CompletionItem`/`Hover`/`ServerCapabilities`/`InitializeParams`/`Symbol`/`Reference`/`Analysis` 与 `on_initialize`/`on_did_change`/`on_completion`/`on_definition`/`on_hover`/`analyze`/`capabilities_to_json`/`publish_diagnostics_notification`/`position_from_json`）签名与运行时行为一律冻结；尤其是既有「裸 JSON 正文（无头部帧）的 decode/encode/dispatch」往返与错误码语义保持逐字节不变。所有旗舰新能力以旁路扩展（新增类型、新增 `.mbt` 文件、新增方法、新增子包）方式提供，绝不改写既有调用方语义。**

既有两条流水线保持不变：

```
协议层： bytes ─ decode_message ─▶ JsonRpcMessage ─ dispatch(Router) ─▶ JsonRpcMessage?
能力层： TextDocument ─ analyze ─▶ Analysis ─▶ {on_completion / on_definition / on_hover / on_did_change}
```

旗舰深化在其旁侧新增「会话编排」骨架，把生命周期、传输帧、批量/取消、增量同步、位置编码与扩展语言能力串成一条完备会话流水线，并通过「旁路而非替换」与既有管线桥接：

```
                       ┌──────────────────────── lsp_binding（协议层） ────────────────────────┐
  字节流 ─ FrameReader ─▶ frame(Content-Length) ─ decode_message ─▶ JsonRpcMessage
                       │                                  │                                     │
                       │                       batch[]（顶层数组）逐条 ─ dispatch ─▶ 响应数组    │
                       │                       $/cancelRequest ─▶ CancelRegistry 标记取消         │
                       └───────────────────────────────────────────────────────────────────────┘
                                                   │ JsonRpcMessage
                       ┌──────────────────────── lsp_server（能力层） ─────────────────────────┐
   JsonRpcMessage ─▶ LspSession（Lifecycle 状态机 + DocumentStore + 能力协商）
                       │   ├─ initialize/initialized/shutdown/exit       （R1）
                       │   ├─ didOpen/didChange（Full|Incremental）+ version（R3）
                       │   ├─ PositionEncoding（UTF-16/8/32）⇄ offset      （R4）
                       │   └─ 扩展能力：documentSymbol / workspace symbol / references /
                       │        rename(WorkspaceEdit) / formatting / codeAction /
                       │        signatureHelp / semanticTokens / foldingRange /
                       │        documentHighlight / pull diagnostic         （R5/R6）
                       └───────────────────────────────────────────────────────────────────────┘
```

旗舰能力分八条主线落地：①完整 LSP 生命周期状态机；②JSON-RPC 协议层增强（头部帧 / 批量 / 取消 / id 关联）；③增量文档同步；④位置编码与坐标换算；⑤扩展语言能力；⑥诊断 push+pull 模型；⑦性能基准；⑧端到端会话 demo。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、开源对标、三后端一致性、错误处理与正确性属性。

### 实现边界（Implementation Boundaries）

本方向**刻意停留在「消息与文档模型层」**，显式声明以下边界（对应 Requirement 8.5）：

- **无真实传输**：不实现真实 stdio / socket / pipe 收发与异步事件循环。`FrameReader`/`FrameWriter` 只做**纯函数式**的「字节缓冲 ⇄ 消息」帧切分与拼装；会话编排以「事件序列驱动纯状态机」表达，不绑定任何 IO 运行时。
- **分析针对内置 DSL**：语言能力建立在既有 **极简 `key = value` 配置 DSL**（含 `${key}` 引用、`#` 注释）之上，而非通用编程语言的语义分析。这保证全部能力可纯函数化、可属性化、三后端逐位一致。
- **取消为协作式语义模型**：`$/cancelRequest` 以「取消登记表 + 进行中请求标记」的纯数据模型表达取消「应当」发生的结果（返回取消错误响应），不涉及抢占式中断真实线程。
- **单工作区、内存多文档**：`workspace/symbol` 在内存中的多文档集合上检索，不做磁盘扫描或多根工作区管理。

这些边界与既有骨架 `moon.pkg` 顶部声明一致，是「可验证、可复现、三后端一致」的前提，而非能力缺失——LSP 协议契约的正确性恰恰落在这一层。

---

## 架构（Architecture）

### 设计原则与向后兼容契约

1. **冻结即契约**：`lsp_binding` 的 `types.mbt`/`json.mbt`/`binding.mbt` 与 `lsp_server` 的 `types.mbt`/`dsl.mbt`/`server.mbt`/`release.mbt` 中现有 `pub`/`pub(all)` 声明，其签名、字段、变体与运行时行为一律不改。两包 `pkg.generated.mbti` 现有条目保持稳定，新增条目仅追加。
2. **旁路扩展**：生命周期状态机、头部帧、批量分发、取消登记、增量同步、位置编码换算、扩展语言能力、pull 诊断全部为**新增**。新增方法挂在既有类型上（如为 `Analysis` 增补查询方法、为 `TextDocument` 旁路构造新版本文档）只增不改既有字段。
3. **既有裸 JSON 行为不变**：`decode_message(bytes)`/`encode_message(msg)` 继续按「无头部帧的裸 JSON 正文」工作；头部帧能力由**新函数** `decode_framed`/`encode_framed`/`FrameReader` 提供。`dispatch(msg, router)` 单条分发语义不变；批量由**新函数** `dispatch_batch` 提供。
4. **错误模型不扩容**：`RpcError` 与五个标准错误码常量冻结。取消语义复用一个**新增**常量 `request_cancelled_code`（LSP 规范定义为 `-32800`），它是新增公开常量，不改既有五个常量的值与语义。
5. **infra 复用**：全部新增属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`（每条属性 ≥100 迭代）；发布元数据复用 `@release_meta`，`release_info`/`release_info_with_gates`/`lsp_version`/`lsp_name`/`lsp_changelog_path` 语义不变（次/主版本推进仅改 `lsp_version` 字面量与 CHANGELOG）。
6. **纯函数优先**：状态机、文档存储、位置换算、扩展能力一律实现为「输入 → 输出」纯函数或「状态 + 事件 → 新状态 + 输出」纯转移，无全局可变状态、无 IO，确保 `wasm-gc`/`js`/`native` 三后端逐位一致。

### 模块 / 文件划分

下表为两个子包下的文件规划。**既有文件**保持冻结（仅可追加新方法所需的 `import`）；**新增文件**承载旗舰能力。

#### `src/lsp_binding/`（协议层）

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `json.mbt` | 冻结 | 最小 JSON 值模型 `Json` 与解析/打印器 | R10.1 |
| `types.mbt` | 冻结 | `Id`/`RpcError`/`JsonRpcMessage`/`Router` + 五个错误码 | R10.1 |
| `binding.mbt` | 冻结 | `decode_message`/`encode_message`/`dispatch`/`error_response`（裸 JSON 语义不变） | R10.2 |
| `framing.mbt` | 新增 | `Content-Length` 头部帧编解码：`encode_framed`/`decode_framed`/`FrameReader` | R2.1/2.2/2.3 |
| `batch.mbt` | 新增 | 批量请求：`decode_batch`/`dispatch_batch`/`encode_batch` | R2.4/2.10 |
| `cancel.mbt` | 新增 | 取消登记表 `CancelRegistry` + `request_cancelled_code` + `cancel_id_of` | R2.5 |
| `correlate.mbt` | 新增 | id 关联工具：`id_of`/`correlate`（响应 id ⇄ 请求 id 校验） | R2.6/2.7 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖帧/批量/取消/分发 | R11.4 |
| `prop_*_test.mbt` | 新增/既有 | 属性测试（往返/分发/批量/帧/取消/错误条件） | R11.2 |

#### `src/lsp_server/`（能力层）

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `types.mbt` | 冻结 | `Position`/`Range`/`Location`/`TextDocument`/`Diagnostic`/`CompletionItem`/`Hover`/`ServerCapabilities`/`InitializeParams` | R10.3 |
| `dsl.mbt` | 冻结 | `Symbol`/`Reference`/`Analysis` 与 `analyze`（DSL 静态分析，行为不变） | R10.3/10.4/10.8 |
| `server.mbt` | 冻结 | 五处理器 + JSON 适配（`on_*`/`capabilities_to_json`/`publish_diagnostics_notification`/`position_from_json`） | R10.4 |
| `release.mbt` | 冻结 | 发布元数据登记（`release_info`/`release_info_with_gates`） | R10.7/11.6 |
| `lifecycle.mbt` | 新增 | 生命周期状态机 `LifecycleState`/`LifecycleEvent`/`step`/`LspSession` | R1 |
| `capabilities_ext.mbt` | 新增 | 扩展能力声明 `ServerCapabilitiesExt` + 能力协商 `negotiate` | R1.7/R5 |
| `sync.mbt` | 新增 | 文档同步 `TextDocumentSyncKind`/`ContentChange`/`apply_changes`/`VersionedDocument` | R3 |
| `position_encoding.mbt` | 新增 | `PositionEncoding`/`position_to_offset`/`offset_to_position`/`convert_position` | R4 |
| `references.mbt` | 新增 | `documentSymbol`/`workspace_symbol`/`references`/`document_highlight` | R5.1/5.2/5.3/5.7/5.8 |
| `rename.mbt` | 新增 | `WorkspaceEdit`/`TextEdit`/`rename`/`apply_workspace_edit` | R5.4 |
| `format.mbt` | 新增 | `formatting`（`key = value` 规范化）/`code_action` | R5.5/5.6 |
| `semantic.mbt` | 新增 | `signature_help`/`semantic_tokens`/`folding_ranges` | R5.7 |
| `diagnostics.mbt` | 新增 | pull 诊断 `pull_diagnostics` + push/pull 等价 + `diagnostic_to_json`（规范严重码） | R6 |
| `demo.mbt` | 新增 | 端到端会话脚本 `run_session_demo`（initialize→…→exit） | R9 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖生命周期/同步/编码/各能力/诊断/demo | R11.4 |
| `prop_*_test.mbt` | 新增/既有 | 属性测试（生命周期/增量=全量/编码往返/引用-定义/重命名/确定性/既有不变） | R11.2 |

#### `benches/`（基准）

| 包 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `benches/lsp_bench/` | 新增 | 覆盖 decode/encode/dispatch、大文档 analyze、增量同步应用、references/rename 五类负载；产出 `benches/results/` 工件并接入 guard | R7 |

`benches/lsp_bench/` 结构对齐既有 `benches/astar_bench`（`lsp_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`）。native 后端运行前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

### 里程碑依赖（构建顺序）

```
lsp_binding: framing → batch → cancel/correlate          （协议层，先行）
lsp_server : lifecycle → sync → position_encoding         （会话基础设施）
           → references → rename → format → semantic       （扩展能力，依赖 analyze + position_encoding）
           → diagnostics（pull/push 等价）                  （依赖 analyze）
           → demo（串联全部）                                 → benches/lsp_bench → README.mbt.md
```

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt`/`.mbti` 风格（`pub(all)` 暴露可构造数据，`pub` 暴露只读结构与函数）。全部新增类型 `derive(Eq, Show)` 以支撑属性测试断言与确定性打印。

### 3.1 生命周期状态机（R1）

对标 LSP 规范「Lifecycle Messages」与 JSON-RPC 会话语义。状态机为纯转移函数 `step`，`LspSession` 在其上叠加文档存储与协商能力。

```moonbit
// lifecycle.mbt
pub(all) enum LifecycleState {
  Uninitialized
  Initializing
  Initialized
  ShuttingDown
  Exited
} derive(Eq, Show)

pub(all) enum LifecycleEvent {
  EvInitialize(InitializeParamsExt)     // initialize 请求
  EvInitialized                         // initialized 通知
  EvShutdown                            // shutdown 请求
  EvExit                                // exit 通知
  EvRequest(method~ : String)           // 任意其他请求（按当前状态裁决）
  EvNotification(method~ : String)      // 任意其他通知
} derive(Eq, Show)

// 一步转移的结果：新状态 + 应答（请求才有）+ 若 EvExit 则给出退出码。
pub(all) struct StepResult {
  state : LifecycleState
  reply : @lsp_binding.JsonRpcMessage?   // 请求的响应；通知为 None
  exit_code : Int?                       // 仅 EvExit 给出（shutdown 前=0，否则=1）
} derive(Eq, Show)

// 纯状态转移（Requirement 1.1-1.8）。reply_id 用于为请求合成带 id 的响应。
pub fn step(
  state : LifecycleState,
  shutdown_seen : Bool,
  event : LifecycleEvent,
  reply_id : @lsp_binding.Id,
) -> StepResult

// 会话句柄：封装状态 + 是否已收到 shutdown + 协商后能力 + 文档存储。
pub struct LspSession {
  state : LifecycleState
  shutdown_seen : Bool
  caps : ServerCapabilitiesExt
  docs : DocumentStore
}
pub fn LspSession::new() -> Self                 // 初始 Uninitialized
pub fn LspSession::handle(Self, @lsp_binding.JsonRpcMessage)
  -> (Self, @lsp_binding.JsonRpcMessage?)        // 驱动一条消息，返回新会话 + 可选响应
pub fn LspSession::state(Self) -> LifecycleState
```

**转移规则（与验收标准一一对应）**：`Uninitialized --EvInitialize--> Initializing`（回 capabilities，1.1）；`Initializing --EvInitialized--> Initialized`（1.2）；`Uninitialized --EvRequest(非 initialize)-->` 状态不变，回 `invalid_request_code`（1.3）；`Initialized --EvShutdown--> ShuttingDown`，回 `result=null`（1.4）；`ShuttingDown --EvRequest(非 exit)-->` 状态不变，回 `invalid_request_code`（1.5）；任意状态 `--EvExit--> Exited`，`exit_code = if shutdown_seen {0} else {1}`（1.6）。任何未声明的转移保持当前状态并对请求回 `invalid_request_code`（健全性，1.8）。

### 3.2 JSON-RPC 协议层增强（R2）

#### 头部帧（framing.mbt）

对标 LSP「Base Protocol」的 `Content-Length` 帧。**与既有 `decode_message`/`encode_message` 正交**：帧函数负责「字节流 ⇄ 正文字节」，正文仍交给既有裸 JSON 编解码。

```moonbit
// framing.mbt
// 编码：输出 `Content-Length: <len>\r\n\r\n` + 正文字节（Requirement 2.1）。
pub fn encode_framed(msg : @lsp_binding.JsonRpcMessage) -> Bytes

// 解码单帧：读取头部声明的字节数切出正文并解码（Requirement 2.2）。
// 失败（缺头/值非非负整数/正文不足）→ Err(parse_error_code,..)，不产出半成品（Requirement 2.3）。
pub fn decode_framed(bytes : Bytes) -> Result[JsonRpcMessage, RpcError]

// 流式读取器：在累积缓冲上反复切出完整帧（纯函数式，无 IO）。
pub struct FrameReader {
  buf : Bytes
}
pub fn FrameReader::new() -> Self
pub fn FrameReader::push(Self, Bytes) -> Self                 // 追加字节（返回新 reader）
// 切出下一条完整消息：Some((msg, rest)) 或 None（数据不足）；非法帧以 Err 承载。
pub fn FrameReader::next(Self)
  -> Result[(JsonRpcMessage, FrameReader)?, RpcError]
```

#### 批量请求（batch.mbt）

对标 JSON-RPC 2.0「Batch」。顶层为数组时按出现顺序逐条解码与分发，响应按对应顺序汇集为数组（通知不产生响应，按规范从响应数组中略去）。

```moonbit
// batch.mbt
// 顶层数组 → 逐元素解码（请求或通知）；元素非法以 Err 标记该元素。
pub fn decode_batch(bytes : Bytes)
  -> Result[Array[Result[JsonRpcMessage, RpcError]], RpcError]

// 对一批消息逐条 dispatch，按序汇集请求响应（通知略去）（Requirement 2.4/2.10）。
pub fn dispatch_batch(
  msgs : Array[JsonRpcMessage],
  router : Router,
) -> Array[JsonRpcMessage]

pub fn encode_batch(responses : Array[JsonRpcMessage]) -> Bytes
```

#### 取消与 id 关联（cancel.mbt / correlate.mbt）

```moonbit
// cancel.mbt
pub let request_cancelled_code : Int = -32800   // LSP 规范定义；新增常量，不改既有五个错误码

pub struct CancelRegistry {
  cancelled : Map[String, Bool]   // 以 id 的规范字符串键标记
}
pub fn CancelRegistry::new() -> Self
pub fn CancelRegistry::cancel(Self, Id) -> Self          // 标记某 id 取消
pub fn CancelRegistry::is_cancelled(Self, Id) -> Bool
// 从 $/cancelRequest 通知的 params 中取出待取消 id（Requirement 2.5）。
pub fn cancel_id_of(params : @lsp_binding.Json) -> Id?
// 对已取消的进行中请求合成取消错误响应（id 与请求一致）。
pub fn cancelled_response(id : Id) -> @lsp_binding.JsonRpcMessage

// correlate.mbt
pub fn id_of(msg : JsonRpcMessage) -> Id?                // 请求/响应的 id；通知为 None
pub fn correlate(request : JsonRpcMessage, response : JsonRpcMessage) -> Bool  // id 相等校验
```

### 3.3 增量文档同步（R3）

对标 LSP `textDocument/didChange` 与 `TextDocumentSyncKind`。`apply_changes` 为纯函数：`(旧文本, 变更序列) → 新文本`。

```moonbit
// sync.mbt
pub(all) enum TextDocumentSyncKind {
  Full          // 每次发送全文
  Incremental   // 每次发送变更区间
} derive(Eq, Show)

// 一条内容变更：Incremental 时 range=Some(..)，Full 时 range=None（text 即全文）。
pub(all) struct ContentChange {
  range : Range?
  text : String
} derive(Eq, Show)

// 带版本号的文档（旁路扩展，不改既有 TextDocument 字段）。
pub(all) struct VersionedDocument {
  uri : String
  text : String
  version : Int
} derive(Eq, Show)

// 按序应用变更得到新文本（Requirement 3.1/3.2/3.4）。
// 越界 range → Err(携带定位信息)，且不返回部分应用结果（Requirement 3.5）。
pub fn apply_changes(
  text : String,
  changes : Array[ContentChange],
  encoding : PositionEncoding,
) -> Result[String, RpcError]

// 把 didChange 应用到带版本文档：成功则文本更新且 version=通知携带版本（Requirement 3.3）。
pub fn VersionedDocument::apply(
  Self, changes : Array[ContentChange], new_version : Int, encoding : PositionEncoding,
) -> Result[VersionedDocument, RpcError]
```

**增量=全量等价**：对同一初始文本与变更序列，`apply_changes(Incremental 变更)` 的结果与「以变更后全文做一次 Full 替换」逐字符相等（Property 5）。范围越界时不改变文本（3.5），从而不破坏等价基线。

### 3.4 位置编码与坐标换算（R4）

对标 LSP「Position Encoding」（默认 UTF-16）。列号单位随编码而变；换算以「行起点 offset + 行内按编码累计码元」实现。

```moonbit
// position_encoding.mbt
pub(all) enum PositionEncoding {
  Utf16   // LSP 默认：BMP 外字符按 2 码元计
  Utf8    // 按 UTF-8 字节数计
  Utf32   // 按 Unicode 码位计（每字符 1）
} derive(Eq, Show)

// 协商：取客户端与服务端共同支持的首个编码；客户端无声明 → 回退 Utf16（Requirement 4.1）。
pub fn negotiate_encoding(client : Array[PositionEncoding]) -> PositionEncoding

// Position → 线性 offset（该编码下的码元偏移）（Requirement 4.2）。
pub fn position_to_offset(text : String, pos : Position, enc : PositionEncoding) -> Int?
// 线性 offset → Position（Requirement 4.3）。
pub fn offset_to_position(text : String, offset : Int, enc : PositionEncoding) -> Position?
// 同一字符边界在两编码间换算（Requirement 4.5）。
pub fn convert_position(
  text : String, pos : Position, from~ : PositionEncoding, to~ : PositionEncoding,
) -> Position?
// 单个码位在某编码下对列号的贡献（UTF-16: BMP=1/非 BMP=2；UTF-8: 1..4；UTF-32: 1）（Requirement 4.4）。
pub fn code_units(cp : Int, enc : PositionEncoding) -> Int
```

**往返**：`offset_to_position(position_to_offset(p)) == p`（Property 6）；`convert(convert(p, U16→U8), U8→U16) == p`（Property 7）。代理对（如 emoji、CJK 扩展区）在 UTF-16 下占 2 列、UTF-8 下占 4 字节、UTF-32 下占 1 列，三者指向同一字符边界。

### 3.5 扩展语言能力（R5）

全部建立在既有 `analyze : TextDocument -> Analysis` 之上，**复用其 `symbols`/`references`/`diagnostics`**，不改 `analyze` 行为（R10.8 既有分析不变）。

```moonbit
// references.mbt
pub(all) struct DocumentSymbol { name : String; range : Range } derive(Eq, Show)
// 当前文档全部键定义符号（Requirement 5.1）。
pub fn document_symbols(a : Analysis) -> Array[DocumentSymbol]
// 工作区按查询子串匹配（Requirement 5.2）。返回 (符号, 所属文档定位)。
pub fn workspace_symbols(docs : Array[Analysis], query : String) -> Array[Location]
// 某符号的全部出现（定义 + 引用），即 references（Requirement 5.3/5.8）。
pub fn references(a : Analysis, name : String) -> Array[Location]
// 当前文档内与某符号相关的全部出现高亮范围（Requirement 5.7）。
pub fn document_highlights(a : Analysis, pos : Position) -> Array[Range]

// rename.mbt
pub(all) struct TextEdit { range : Range; new_text : String } derive(Eq, Show)
pub(all) struct WorkspaceEdit {
  changes : Array[(String, Array[TextEdit])]   // (uri, edits)
} derive(Eq, Show)
// 将某符号全部出现改名（Requirement 5.4）。
pub fn rename(a : Analysis, name : String, new_name : String) -> WorkspaceEdit
// 把 WorkspaceEdit 应用到文档文本（供重命名完整性属性验证）。
pub fn apply_workspace_edit(text : String, edits : Array[TextEdit]) -> String

// format.mbt
// 规范化 key = value 等号周边空白，产出文本编辑列表（Requirement 5.5）。
pub fn formatting(doc : TextDocument) -> Array[TextEdit]
// 针对某条诊断的快速修复动作（Requirement 5.6）。
pub(all) struct CodeAction { title : String; edit : WorkspaceEdit } derive(Eq, Show)
pub fn code_actions(a : Analysis, d : Diagnostic) -> Array[CodeAction]

// semantic.mbt
pub(all) struct SignatureInfo { label : String } derive(Eq, Show)
pub fn signature_help(a : Analysis, pos : Position) -> SignatureInfo?       // （Requirement 5.7）
pub fn semantic_tokens(a : Analysis) -> Array[Int]                          // LSP 5-tuple 增量编码
pub fn folding_ranges(doc : TextDocument) -> Array[Range]
```

**引用-定义自洽**（Property 8）：键 `k` 的定义位置 ∈ `references(a, k)`，且 `references` 中每个位置都落在 `k` 的某次出现上。**重命名完整性**（Property 9）：应用 `rename` 后原名全部出现变新名、其余文本不变，且重分析后新名出现数 = 原名原出现数。

### 3.6 诊断模型 push + pull（R6）

```moonbit
// diagnostics.mbt
// pull：textDocument/diagnostic 请求 → 当前分析诊断作为响应结果（Requirement 6.2）。
pub fn pull_diagnostics(doc : TextDocument) -> Array[Diagnostic]
// push：复用既有 publish_diagnostics_notification（Requirement 6.1）。
// 规范严重码编码：Error=1/Warning=2/Information=3/Hint=4（Requirement 6.4）。
pub fn diagnostic_to_json(d : Diagnostic) -> @lsp_binding.Json
```

**push/pull 等价**（Property 18）：同一文档经 push 路径（`on_did_change`/`publish_diagnostics_notification`）与 pull 路径（`pull_diagnostics`）得到的诊断集合相等。**诊断确定性**（Property 10）：同一文档多次 `analyze` 产出逐条相同的诊断序列。

### 3.7 性能基准（R7）

`benches/lsp_bench/lsp_bench.mbt` 定义五类工作负载：(1) decode/encode round-trip 吞吐；(2) dispatch 路由吞吐；(3) 大文档 `analyze`；(4) 增量同步 `apply_changes`；(5) `references`/`rename`。输出含 `machine`/`backend`/`input_size`/计时统计的 JSON 工件至 `benches/results/`，并由 guard 与基线中位数比较、超容差给出可审计失败报告。运行命令记入文档；native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

### 3.8 端到端会话 demo（R9）

```moonbit
// demo.mbt
pub(all) struct SessionStep { label : String; output : @lsp_binding.Json } derive(Eq, Show)
// 驱动一份内置 DSL 文档：initialize → didOpen → 增量 didChange →
// diagnostics/completion/definition/references/rename/hover → shutdown/exit。
pub fn run_session_demo() -> Array[SessionStep]
```

**断言（Requirement 9.3）**：会话中增量 `didChange` 后请求的诊断，与对变更后全文做全量替换后的诊断相等（增量=全量在诊断上的投影，归入 Property 5）。结果确定性由 Property 10 保证。该脚本在 `README.mbt.md` 中以可执行文档演示并通过 `moon test *.mbt.md`。

---

## 数据模型（Data Models）

- **协议层（新增）**：`FrameReader`（字节缓冲）、`CancelRegistry`（id→取消标记）。复用既有 `Json`/`Id`/`RpcError`/`JsonRpcMessage`/`Router`。
- **会话层（新增）**：`LifecycleState`/`LifecycleEvent`/`StepResult`/`LspSession`/`DocumentStore`、`ServerCapabilitiesExt`（在既有 `ServerCapabilities` 四项之上旁路扩展声明 documentSymbol/references/rename/formatting/… 各 provider 位）、`InitializeParamsExt`（旁路携带客户端 `capabilities` 与 `positionEncodings`，不改既有 `InitializeParams.root_uri`）。
- **同步层（新增）**：`TextDocumentSyncKind`/`ContentChange`/`VersionedDocument`。
- **编码层（新增）**：`PositionEncoding`。
- **能力层（新增）**：`DocumentSymbol`/`TextEdit`/`WorkspaceEdit`/`CodeAction`/`SignatureInfo`。复用既有 `Position`/`Range`/`Location`/`Diagnostic`/`Symbol`/`Reference`/`Analysis`。
- **发布元数据（复用）**：`@release_meta.DirectionRelease`/`QualityGates`；`release_info`/`release_info_with_gates`/`lsp_version`/`lsp_name`/`lsp_changelog_path` 语义不变，旗舰深化仅推进 `lsp_version` 并更新两包各自 `CHANGELOG.md`，仍以 "lsp" 单一发布单元登记。

---

## 错误处理（Error Handling）

统一遵循「**返回结构化 `RpcError`、绝不 panic/abort、绝不产出半成品消息**」（R11.3）：

| 场景 | 错误码 | 处理 |
|---|---|---|
| 非法 JSON 正文 | `parse_error_code`(-32700) | 既有 `decode_message` 行为，冻结 |
| 缺 `Content-Length`/值非非负整数/正文不足 | `parse_error_code` | `decode_framed`/`FrameReader::next` 返回 `Err`，缓冲保持可继续 |
| 顶层结构非法 / `jsonrpc`≠"2.0" / id 非法 | `invalid_request_code`(-32600) | 既有语义，冻结 |
| 生命周期非法请求（Uninitialized 非 initialize、ShuttingDown 非 exit） | `invalid_request_code` | `step` 状态不变并回错误响应（R1.3/1.5） |
| method 未注册 | `method_not_found_code`(-32601) | 既有 `dispatch` 合成响应，id 一致，冻结 |
| 增量变更范围越界 | `invalid_params_code`(-32602) | `apply_changes` 返回 `Err` 且文本不变（R3.5） |
| 进行中请求被取消 | `request_cancelled_code`(-32800) | `cancelled_response` 合成响应，id 一致（R2.5） |

批量中单元素失败被就地标记为该元素的 `Err`，不影响其余元素处理（R2.4 的稳健性）。

---

## paper-to-code 可追溯与开源对标（R8）

### 规范追溯

- **LSP 规范**：消息结构、生命周期（initialize/initialized/shutdown/exit）、能力协商、文档同步类别、位置与位置编码、各语言能力请求形态——逐条在文档注释标注「LSP §...」。
- **JSON-RPC 2.0 规范**：请求/响应/通知三类消息、批量数组、标准错误码（-32700/-32600/-32601/-32602/-32603）与 `-32800` 取消码——标注「JSON-RPC 2.0 §...」。
- **位置编码**：UTF-16/UTF-8/UTF-32 列号计量与代理对处理，追溯到 LSP 的 PositionEncodingKind 定义与 Unicode 码元约定。

### 开源对标（Requirement 8.4）

| 维度 | 本库（LSP_Suite） | rust-analyzer | gopls | tower-lsp | vscode-languageserver-node |
|---|---|---|---|---|---|
| 传输/帧 | 纯函数 `Content-Length` 帧切分，无 IO 运行时 | 真实 stdio + 异步 | 真实 stdio + 并发 | 基于 tokio 的异步传输 | Node IPC/stdio |
| 能力协商 | 客户端 capabilities 子集裁剪 | 完整动态注册 | 完整 | 完整 | 完整 |
| 文档同步 | Full + Incremental（纯函数等价验证） | Incremental | Incremental | 由用户实现 | 框架托管 |
| 位置编码 | UTF-16/8/32 协商 + 往返属性 | UTF-8 优先协商 | UTF-16/8 | 由用户实现 | UTF-16 默认 |
| 诊断模型 | push + pull，二者等价（属性验证） | push + pull | push + pull | 由用户实现 | push + pull |
| 分析对象 | 内置 key=value DSL | Rust 语义 | Go 语义 | 不限（框架） | 不限（框架） |

**显式边界（Requirement 8.5）**：本库不支持真实 stdio/socket 传输、通用语言语义分析与多根工作区管理；专注「协议正确性 + 文档模型 + 坐标换算」这一可形式化验证的层面，并以属性测试给出强保证——这是与上述完整语言服务器的定位差异，亦是本方向的可解释性价值所在。

---

## 三后端一致性（Three-Backend Consistency）

- 全部新增逻辑为纯函数 / 纯状态转移，无浮点、无平台相关 API、无全局可变状态；数值统一用 `Int`，JSON 数值沿用既有 `JNum(String)`「保留原始字面量文本」策略，规避后端浮点格式化差异。
- 字符串/字符处理沿用既有 `dsl.mbt`/`json.mbt` 的逐字符遍历约定；位置编码换算显式按码位计算 `code_units`，不依赖任何后端内建字符串长度语义。
- `Map` 遍历不渗入可观察输出：批量、符号、引用、诊断等输出顺序由「源文本出现顺序」决定（确定性），不由哈希顺序决定。
- 同一属性测试套件在 `wasm-gc`/`js`/`native` 三后端运行，任一后端输出分歧判定为构建失败（R11.1）。native 运行前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R11.5）。

---

## 测试策略（Testing Strategy）

**双轨测试**：属性测试（覆盖全称性质，≥100 迭代，复用 `@infra_pbt`）+ 单元/示例测试（覆盖具体转移、边界与错误条件）。

- **属性测试**：见下「正确性属性」18 条，每条标注其校验的需求子句，标签格式 `Feature: lsp, Property {N}: {text}`。
- **示例测试**：生命周期单条转移（1.1/1.2/1.4/1.6）、能力协商回退（4.1）、codeAction/signatureHelp/semanticTokens/foldingRange 典型输出（5.6/5.7）、push/pull 诊断构造（6.1/6.2）、诊断严重码映射（6.4）、门禁阻断（11.7）。
- **边界/错误条件**：畸形帧、越界增量、非法 JSON——统一并入 Property 16 与少量定向用例。
- **基准回归**：guard 对比基线中位数（R7.3）。
- **可执行文档**：`README.mbt.md` 通过 `moon test *.mbt.md`（R11.4），native 前置 `LIBRARY_PATH`。
- **向后兼容**：两包 `pkg.generated.mbti` 既有条目稳定 + 既有测试全过 + Property 11 既有分析不变。

---

## 正确性属性（Correctness Properties）

*属性是对系统在所有合法执行下都应成立的特征或行为的形式化陈述，是「人类可读规格」与「机器可验证正确性保证」之间的桥梁。以下属性基于上文 prework 分析提炼，已做冗余消解（单条转移并入状态机性质、命中/未命中并入分发性质、双向换算并入往返性质、错误条件统一并入 Property 16）。每条属性以 `@infra_pbt` 实现、至少运行 100 次迭代。*

### Property 1：JSON-RPC 消息往返

对任意（for all）由生成器产生的 `JsonRpcMessage` `m`，`decode_message(encode_message(m))` 得到与 `m` 相等的消息。

**Validates: Requirements 2.8, 10.2**

### Property 2：分发正确性

对任意（for all）请求消息与路由表，当 `method` 在路由表中命中时，`dispatch` 调用对应处理器并返回其结果；当未命中时，返回携带 `method_not_found_code` 且 `id` 与请求 `id` 相等的错误响应。

**Validates: Requirements 2.6, 2.7, 2.9**

### Property 3：批量逐条处理

对任意（for all）请求/通知序列，批量分发 `dispatch_batch` 所得响应数组，与对各元素逐条 `dispatch` 所得响应（略去通知）按序一一相等。

**Validates: Requirements 2.4, 2.10**

### Property 4：生命周期合法转移

对任意（for all）由生成器产生的生命周期事件序列，会话状态仅经声明的合法转移变化；且在收到 `shutdown` 之后，对任何非 `exit` 请求均以 `invalid_request_code` 拒绝且不改变状态。

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.8**

### Property 5：增量与全量等价

对任意（for all）由生成器产生的（初始文本, 增量变更序列）对，依次应用增量变更所得文本，与以变更后全文做一次全量替换所得文本逐字符相等；该等价在诊断上的投影同样成立（增量 didChange 后的诊断等于全量替换后的诊断）。

**Validates: Requirements 3.2, 3.4, 3.6, 9.3**

### Property 6：Position↔offset 往返

对任意（for all）由生成器产生的（文本, 位置编码, 文本内有效位置）三元组，`offset_to_position(position_to_offset(p)) == p`。

**Validates: Requirements 4.2, 4.3, 4.6**

### Property 7：跨编码换算往返

对任意（for all）由生成器产生的（含多字节/代理对字符文本, 文本内有效位置）对，将位置从源编码换算到目标编码再换算回源编码，得到与原位置相等的结果；且代理对字符在各编码下按 UTF-16=2 码元、UTF-8=其字节数、UTF-32=1 码元计入列号。

**Validates: Requirements 4.4, 4.5, 4.7**

### Property 8：引用—定义自洽

对任意（for all）由生成器产生的 DSL 文档与其中某已定义键，该键的定义位置必属于其 `references` 结果，且 `references` 结果中的每个位置都位于该键的某次出现上。

**Validates: Requirements 5.1, 5.3, 5.8, 5.9**

### Property 9：重命名完整性

对任意（for all）由生成器产生的 DSL 文档、其中某已定义键与一个未被占用的新名，应用 `rename` 的 `WorkspaceEdit` 后，原名的全部出现均变为新名、其余符号文本不变，且对结果再次分析时新名的出现数等于原名原出现数。

**Validates: Requirements 5.4, 5.10**

### Property 10：诊断确定性

对任意（for all）由生成器产生的 DSL 文档，对同一文档多次分析得到逐条相同（顺序与内容一致）的诊断序列。

**Validates: Requirements 6.5, 9.2**

### Property 11：既有分析不变

对任意（for all）由生成器产生的、既有 DSL 文法下的文档，深化后 `analyze` 产出的符号、引用与诊断与 `0.1.0` 行为相等（以冻结黄金基线对照）。

**Validates: Requirements 10.8**

### Property 12：头部帧往返

对任意（for all）由生成器产生的 `JsonRpcMessage` `m`，`decode_framed(encode_framed(m))` 得到与 `m` 相等的消息；且对任意消息序列，依次写入帧后由 `FrameReader` 逐条切出的消息序列与原序列按序相等。

**Validates: Requirements 2.1, 2.2**

### Property 13：取消产生取消响应

对任意（for all）由生成器产生的请求 `id` 集合与待取消 `id`，将其经 `CancelRegistry::cancel` 标记后，对该 `id` 对应的进行中请求合成的响应携带 `request_cancelled_code` 且其 `id` 与请求 `id` 相等；未被取消的 `id` 不受影响。

**Validates: Requirements 2.5**

### Property 14：能力协商子集

对任意（for all）由生成器产生的客户端能力声明，服务端 `negotiate` 后声明的能力集是客户端所声明能力的子集——对客户端未声明的能力不予声明。

**Validates: Requirements 1.7**

### Property 15：工作区符号可靠性

对任意（for all）由生成器产生的多文档工作区与查询字符串，`workspace_symbols` 返回的每个符号其名称都包含该查询子串，且都来自工作区内某文档的已定义符号。

**Validates: Requirements 5.2**

### Property 16：非法输入错误条件

对任意（for all）由生成器产生的非法输入（畸形 `Content-Length` 帧、非法 JSON 正文、越界增量变更），相应解码/应用函数均返回携带恰当标准错误码的 `RpcError`，不通过 panic/abort 终止进程，也不产生部分构造的消息或部分应用的文本。

**Validates: Requirements 2.3, 3.5, 11.3**

### Property 17：格式化幂等

对任意（for all）由生成器产生的 DSL 文档，对其应用 `formatting` 编辑得到规范化文本后再次应用 `formatting`，不再产生任何改变文本的编辑（`format(format(x)) == format(x)`）。

**Validates: Requirements 5.5**

### Property 18：push/pull 诊断等价

对任意（for all）由生成器产生的 DSL 文档，经 push 路径（`on_did_change`/`publish_diagnostics_notification`）与 pull 路径（`pull_diagnostics`）获取的诊断集合彼此相等。

**Validates: Requirements 6.3**

---

## 设计权衡（Design Trade-offs）

1. **帧/批量旁路而非改写既有 decode**：选择新增 `decode_framed`/`dispatch_batch` 而非在既有 `decode_message`/`dispatch` 中内联帧与批量逻辑。代价是 API 略多，收益是既有「裸 JSON」调用方零影响、且单条与批量职责清晰、可独立属性化（R10.2 硬约束）。
2. **取消码用新增常量 `-32800` 而非扩展 `RpcError` 形态**：`RpcError`/五个错误码冻结，取消语义仅新增一个公开常量。代价是取消不是一个枚举变体；收益是错误模型形态稳定、既有匹配代码不受影响。
3. **位置编码显式三选一并以码位计算**：不依赖后端字符串长度语义，全部按 `code_units` 显式累计。代价是换算稍繁；收益是三后端逐位一致且代理对正确（R4.4），并使往返属性可严格成立。
4. **取消为协作式纯数据模型**：以登记表表达「应当被取消」的结果而非抢占真实执行。与「无真实传输」边界一致，使取消行为可纯函数化、可属性化。
5. **扩展能力全部复用 `analyze`**：references/rename/documentSymbol/highlight 不重写解析，只在 `Analysis` 上投影。代价是能力受 DSL 文法约束；收益是天然满足「既有分析不变」（R10.8）且避免双解析器漂移。
6. **`InitializeParamsExt`/`ServerCapabilitiesExt` 旁路扩展参数与能力**：不改既有 `InitializeParams.root_uri` 与 `ServerCapabilities` 四字段，新增结构承载客户端 capabilities 与扩展 provider 位。代价是两套能力结构并存；收益是 `on_initialize`/`capabilities_to_json` 签名与行为冻结。
7. **会话以「事件序列驱动纯状态机」建模**：不引入异步运行时。代价是不演示真实并发；收益是状态机合法转移可被属性测试穷尽式覆盖（Property 4），契合本方向「协议正确性」定位。
