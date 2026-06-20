# 实施计划（Implementation Plan）：LSP 方向旗舰深化（lsp_binding + lsp_server）

## 概述（Overview）

本计划将 `design.md` 的旗舰深化拆解为一系列**增量、可执行、聚焦编码**的 MoonBit 任务，严格遵循「既有契约冻结、新能力旁路扩展」原则，并覆盖协议层 `src/lsp_binding/` 与能力层 `src/lsp_server/` 两个子包：

- **冻结即契约（严格向后兼容）**：
  - `lsp_binding`：`json.mbt`（`Json`）、`types.mbt`（`Id`/`RpcError`/`JsonRpcMessage`/`Router` 与五个错误码 `parse_error_code`/`invalid_request_code`/`method_not_found_code`/`invalid_params_code`/`internal_error_code`）、`binding.mbt`（`decode_message`/`encode_message`/`dispatch`/`error_response`、`Router::new`/`register`/`lookup`、`RpcError::new`/`with_data`）的现有 `pub`/`pub(all)` 签名、字段、变体与运行时行为一律不动；**既有裸 JSON 正文（无头部帧）的 decode/encode/dispatch 往返与错误码语义保持逐字节不变**。
  - `lsp_server`：`types.mbt`（`Position`/`Range`/`Location`/`TextDocument`/`DiagnosticSeverity`/`Diagnostic`/`CompletionItemKind`/`CompletionItem`/`Hover`/`ServerCapabilities`/`InitializeParams`）、`dsl.mbt`（`Symbol`/`Reference`/`Analysis`/`analyze`）、`server.mbt`（`on_initialize`/`on_did_change`/`on_completion`/`on_definition`/`on_hover`/`capabilities_to_json`/`publish_diagnostics_notification`/`position_from_json`）、`release.mbt`（除 `lsp_version` 字面量外）的现有声明签名与语义一律不动。
  - **错误模型不扩容**：`RpcError` 与五个标准错误码冻结；取消语义仅新增公开常量 `request_cancelled_code`（-32800），不改既有五码的值与语义。
- **复用而非重写**：扩展语言能力一律建立在既有 `analyze` 投影之上（不重写解析）；属性测试复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）；发布元数据复用 `@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）。
- **任务依赖顺序**：协议层 `framing → batch → cancel/correlate` → 会话基础设施 `lifecycle/capabilities_ext → position_encoding → sync` → 扩展能力 `references → rename → format → semantic → diagnostics` → 既有兼容回归 → `demo` → `benches/lsp_bench` → 两包 `README.mbt.md` → 两包发布推进，并设阶段检查点。
- **实现语言**：MoonBit（仅 `.mbt` / `.mbt.md` / `.md`，不写其他语言）。源文件位于 `src/lsp_binding/` 与 `src/lsp_server/`，基准位于 `benches/lsp_bench/`。
- **属性测试**：Property 1–18 每条独立成一个 `*` 可选子任务，统一以 `@infra_pbt` 的 `holds_for_all`/`round_trip` 实现，每条至少 100 次迭代，标注 `Feature: lsp, Property N`。
- **native 前置约束**：凡在 native 后端运行测试、运行基准、或校验 `README.mbt.md` 可执行文档的环节，**必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（见各检查点、任务 17.2、18.3、18.4 与末尾 Notes）。

---

## 任务（Tasks）

- [x] 1. 协议层头部帧处理（`src/lsp_binding/framing.mbt`，旁路新增）
  - [x] 1.1 实现 `Content-Length` 头部帧编解码与流式读取器
    - 在 `src/lsp_binding/framing.mbt` 实现 `encode_framed(msg) -> Bytes`（输出 `Content-Length: <正文字节数>\r\n\r\n` 头部后接既有 `encode_message` 的裸 JSON 正文字节）、`decode_framed(bytes) -> Result[JsonRpcMessage, RpcError]`（按头部声明字节数切出正文并交既有 `decode_message` 解码）、`FrameReader`（`new`/`push`/`next`，在累积缓冲上纯函数式反复切出完整帧）
    - 缺 `Content-Length`、值非非负整数或正文长度不足时返回 `Err(parse_error_code, ..)` 且不产出半成品消息；缓冲保持可继续
    - 文件头注释标注 paper-to-code 来源（LSP Base Protocol 帧约定）；与既有 `decode_message`/`encode_message` 正交，既有裸 JSON 行为不变
    - _Requirements: 2.1, 2.2, 2.3, 10.2_

  - [x] 1.2 帧处理单元测试（畸形帧/正文不足/多帧切分）
    - 在 `src/lsp_binding/framing_test.mbt` 覆盖缺头/值非法/正文不足返回 `parse_error_code`、单帧与连续多帧由 `FrameReader` 逐条切出的具体见证
    - _Requirements: 2.2, 2.3_

  - [x] 1.3 编写属性测试：头部帧往返
    - **Property 12: 头部帧往返（`decode_framed(encode_framed(m)) == m`；多消息依次写帧后由 `FrameReader` 逐条切出与原序列按序相等）**
    - **Validates: Requirements 2.1, 2.2**
    - 文件 `src/lsp_binding/prop_framing_roundtrip_test.mbt`，以 `@infra_pbt` 生成随机 `JsonRpcMessage` 序列，`round_trip` ≥100 迭代

- [x] 2. 协议层批量请求（`src/lsp_binding/batch.mbt`，旁路新增）
  - [x] 2.1 实现批量解码、逐条分发与编码
    - 在 `src/lsp_binding/batch.mbt` 实现 `decode_batch(bytes) -> Result[Array[Result[JsonRpcMessage, RpcError]], RpcError]`（顶层数组按出现顺序逐元素解码，元素非法就地标记为该元素 `Err`，不影响其余元素）、`dispatch_batch(msgs, router) -> Array[JsonRpcMessage]`（逐条复用冻结 `dispatch`，按序汇集请求响应、略去通知）、`encode_batch(responses) -> Bytes`
    - 文件头注释标注 JSON-RPC 2.0 Batch；不改既有单条 `dispatch` 语义
    - _Requirements: 2.4, 2.10_

  - [x] 2.2 批量单元测试（顺序保持/通知略去/单元素失败隔离）
    - 在 `src/lsp_binding/batch_test.mbt` 覆盖混合请求/通知的响应按序汇集、通知不产生响应、单个非法元素被隔离标记的具体见证
    - _Requirements: 2.4_

  - [x] 2.3 编写属性测试：批量逐条处理
    - **Property 3: 批量逐条处理（`dispatch_batch` 响应数组与对各元素逐条 `dispatch` 所得响应（略去通知）按序一一相等）**
    - **Validates: Requirements 2.4, 2.10**
    - 文件 `src/lsp_binding/prop_batch_test.mbt`，生成随机请求/通知序列与路由表，`holds_for_all` ≥100 迭代

- [x] 3. 协议层取消与 id 关联（`src/lsp_binding/cancel.mbt` + `correlate.mbt`，旁路新增）
  - [x] 3.1 实现取消登记表与取消响应
    - 在 `src/lsp_binding/cancel.mbt` 新增公开常量 `request_cancelled_code : Int = -32800`（不改既有五个错误码）、`CancelRegistry`（`new`/`cancel`/`is_cancelled`，以 `Id` 规范字符串键标记）、`cancel_id_of(params) -> Id?`（从 `$/cancelRequest` 通知 params 取出待取消 id）、`cancelled_response(id) -> JsonRpcMessage`（合成携带 `request_cancelled_code` 且 id 与请求一致的错误响应）
    - 文件头注释标注 LSP `$/cancelRequest` 与协作式取消纯数据模型
    - _Requirements: 2.5_

  - [x] 3.2 实现 id 关联工具
    - 在 `src/lsp_binding/correlate.mbt` 实现 `id_of(msg) -> Id?`（请求/响应取 id，通知为 None）与 `correlate(request, response) -> Bool`（响应 id 与请求 id 相等校验）
    - _Requirements: 2.6, 2.7_

  - [x] 3.3 编写属性测试：取消产生取消响应
    - **Property 13: 取消产生取消响应（被 `CancelRegistry::cancel` 标记的 id，其进行中请求合成响应携带 `request_cancelled_code` 且 id 一致；未被取消的 id 不受影响）**
    - **Validates: Requirements 2.5**
    - 文件 `src/lsp_binding/prop_cancel_test.mbt`，生成随机请求 id 集合与待取消 id，`holds_for_all` ≥100 迭代

  - [x] 3.4 编写属性测试：分发正确性
    - **Property 2: 分发正确性（method 命中时 `dispatch` 调用对应处理器返回其结果；未命中时返回携带 `method_not_found_code` 且 id 与请求一致的错误响应）**
    - **Validates: Requirements 2.6, 2.7, 2.9**
    - 文件 `src/lsp_binding/prop_dispatch_test.mbt`，生成随机请求消息与路由表，`holds_for_all` ≥100 迭代

  - [x] 3.5 编写属性测试：JSON-RPC 消息往返
    - **Property 1: JSON-RPC 消息往返（`decode_message(encode_message(m)) == m`）**
    - **Validates: Requirements 2.8, 10.2**
    - 在既有 `src/lsp_binding/prop_roundtrip_test.mbt` 扩充全形态 `JsonRpcMessage` 生成器（Request/Response/Notification、各 `Id` 变体、嵌套 `Json`），`round_trip` ≥100 迭代

- [x] 4. 检查点 —— 确保协议层（framing/batch/cancel/correlate）全部测试通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行 `src/lsp_binding` 至此为止的单元与属性测试；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. 生命周期状态机与能力协商（`src/lsp_server/lifecycle.mbt` + `capabilities_ext.mbt`，旁路新增）
  - [x] 5.1 实现生命周期纯状态机与会话句柄
    - 在 `src/lsp_server/lifecycle.mbt` 实现 `LifecycleState`（`Uninitialized`/`Initializing`/`Initialized`/`ShuttingDown`/`Exited`）、`LifecycleEvent`、`StepResult`、纯转移 `step(state, shutdown_seen, event, reply_id) -> StepResult` 与 `LspSession`（`new`/`handle`/`state`），实现转移：`initialize` 回协商能力并入 `Initializing`、`initialized` 入 `Initialized`、`Uninitialized` 非 initialize 请求回 `invalid_request_code` 且状态不变、`Initialized --shutdown-->` `ShuttingDown` 回 `result=null`、`ShuttingDown` 非 exit 请求回 `invalid_request_code` 且状态不变、`exit` 入 `Exited` 且退出码 `if shutdown_seen {0} else {1}`
    - 文件头注释标注 LSP Lifecycle Messages；依赖 `capabilities_ext.mbt` 的 `ServerCapabilitiesExt`/`InitializeParamsExt`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.8_

  - [x] 5.2 实现扩展能力声明与能力协商
    - 在 `src/lsp_server/capabilities_ext.mbt` 实现 `ServerCapabilitiesExt`（在既有 `ServerCapabilities` 四项之上旁路扩展声明 documentSymbol/references/rename/formatting/codeAction/signatureHelp/semanticTokens/foldingRange/documentHighlight 各 provider 位）、`InitializeParamsExt`（旁路携带客户端 `capabilities` 与 `positionEncodings`，不改既有 `InitializeParams.root_uri`）、`negotiate(client) -> ServerCapabilitiesExt`（仅声明客户端所声明能力的子集）
    - 不修改既有 `ServerCapabilities`/`InitializeParams` 字段与 `on_initialize`/`capabilities_to_json` 行为
    - _Requirements: 1.7, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

  - [x] 5.3 生命周期单条转移单元测试
    - 在 `src/lsp_server/lifecycle_test.mbt` 覆盖 initialize→Initializing、initialized→Initialized、shutdown→ShuttingDown 回 null、exit 退出码 0/1 的具体见证
    - _Requirements: 1.1, 1.2, 1.4, 1.6_

  - [x] 5.4 编写属性测试：生命周期合法转移
    - **Property 4: 生命周期合法转移（状态仅经声明的合法转移变化；shutdown 后对任何非 exit 请求均以 `invalid_request_code` 拒绝且不改变状态）**
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.8**
    - 文件 `src/lsp_server/prop_lifecycle_test.mbt`，生成随机生命周期事件序列，`holds_for_all` ≥100 迭代

  - [x] 5.5 编写属性测试：能力协商子集
    - **Property 14: 能力协商子集（`negotiate` 后声明的能力集是客户端所声明能力的子集，对未声明能力不予声明）**
    - **Validates: Requirements 1.7**
    - 文件 `src/lsp_server/prop_capabilities_test.mbt`，生成随机客户端能力声明，`holds_for_all` ≥100 迭代

- [x] 6. 位置编码与坐标换算（`src/lsp_server/position_encoding.mbt`，旁路新增）
  - [x] 6.1 实现位置编码协商与 Position↔offset 换算
    - 在 `src/lsp_server/position_encoding.mbt` 实现 `PositionEncoding`（`Utf16`/`Utf8`/`Utf32`）、`negotiate_encoding(client)`（取共同支持首选，无声明回退 `Utf16`）、`code_units(cp, enc)`（UTF-16: BMP=1/非 BMP=2；UTF-8: 1..4；UTF-32: 1）、`position_to_offset`/`offset_to_position`（行起点 offset + 行内按编码累计码元，纯按码位计算不依赖后端字符串长度语义）、`convert_position(text, pos, from~, to~)`
    - 文件头注释标注 LSP PositionEncodingKind 与 Unicode 码元约定
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [x] 6.2 位置编码单元测试（协商回退/代理对列号）
    - 在 `src/lsp_server/position_encoding_test.mbt` 覆盖无声明回退 UTF-16、emoji/CJK 扩展区代理对在三编码下分别占 2 码元 / 其字节数 / 1 码元的具体见证
    - _Requirements: 4.1, 4.4_

  - [x] 6.3 编写属性测试：Position↔offset 往返
    - **Property 6: Position↔offset 往返（`offset_to_position(position_to_offset(p)) == p`）**
    - **Validates: Requirements 4.2, 4.3, 4.6**
    - 文件 `src/lsp_server/prop_position_offset_test.mbt`，生成随机（文本, 位置编码, 文本内有效位置），`round_trip` ≥100 迭代

  - [x] 6.4 编写属性测试：跨编码换算往返
    - **Property 7: 跨编码换算往返（位置从源编码换算到目标编码再换算回源编码得到与原位置相等的结果；代理对在各编码按规定码元计入列号）**
    - **Validates: Requirements 4.4, 4.5, 4.7**
    - 文件 `src/lsp_server/prop_cross_encoding_test.mbt`，生成随机含多字节/代理对字符文本与文本内有效位置，`round_trip` ≥100 迭代

- [x] 7. 增量文档同步（`src/lsp_server/sync.mbt`，旁路新增）
  - [x] 7.1 实现文档同步类别与变更应用
    - 在 `src/lsp_server/sync.mbt` 实现 `TextDocumentSyncKind`（`Full`/`Incremental`）、`ContentChange`（`range : Range?`/`text : String`）、`VersionedDocument`（`uri`/`text`/`version`，旁路不改既有 `TextDocument`）、`apply_changes(text, changes, encoding) -> Result[String, RpcError]`（Full 全文替换；Incremental 按各变更范围依出现顺序应用；越界 range 返回携带定位信息的 `Err(invalid_params_code)` 且不返回部分应用结果）、`VersionedDocument::apply`（成功则文本更新且 `version` = 通知携带版本）
    - 复用任务 6 的 `PositionEncoding` 解释 `range` 列号
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 7.2 同步单元测试（多变更顺序/版本号更新/越界不改文本）
    - 在 `src/lsp_server/sync_test.mbt` 覆盖同一通知多条 `contentChanges` 按序应用、变更后 `version` 更新、越界变更返回错误且文本不变的具体见证
    - _Requirements: 3.3, 3.4, 3.5_

  - [x] 7.3 编写属性测试：增量与全量等价
    - **Property 5: 增量与全量等价（依次应用增量变更所得文本与以变更后全文做全量替换所得文本逐字符相等；该等价在诊断上的投影同样成立）**
    - **Validates: Requirements 3.2, 3.4, 3.6, 9.3**
    - 文件 `src/lsp_server/prop_sync_equiv_test.mbt`，生成随机（初始文本, 增量变更序列）对，`holds_for_all` ≥100 迭代

- [x] 8. 检查点 —— 确保会话基础设施（lifecycle/capabilities/position_encoding/sync）全部测试通过
  - 在三后端运行 `src/lsp_server` 至此为止的单元与属性测试；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. 引用查找、文档/工作区符号与高亮（`src/lsp_server/references.mbt`，旁路新增）
  - [x] 9.1 在 `analyze` 投影之上实现符号/引用/高亮能力
    - 在 `src/lsp_server/references.mbt` 实现 `DocumentSymbol`（`name`/`range`）、`document_symbols(a) -> Array[DocumentSymbol]`（当前文档全部键定义）、`workspace_symbols(docs, query) -> Array[Location]`（内存多文档按查询子串匹配）、`references(a, name) -> Array[Location]`（定义 + 全部引用）、`document_highlights(a, pos) -> Array[Range]`（当前文档相关符号高亮）
    - 全部复用既有 `Analysis` 的 `symbols`/`references`，不改 `analyze` 行为；输出顺序由源文本出现顺序决定（确定性）
    - _Requirements: 5.1, 5.2, 5.3, 5.7, 5.8_

  - [x] 9.2 编写属性测试：引用—定义自洽
    - **Property 8: 引用—定义自洽（键的定义位置 ∈ `references(a, k)`，且 `references` 中每个位置都落在该键的某次出现上）**
    - **Validates: Requirements 5.1, 5.3, 5.8, 5.9**
    - 文件 `src/lsp_server/prop_references_test.mbt`，生成随机 DSL 文档与其中某已定义键，`holds_for_all` ≥100 迭代

  - [x] 9.3 编写属性测试：工作区符号可靠性
    - **Property 15: 工作区符号可靠性（`workspace_symbols` 返回的每个符号名称都包含查询子串，且都来自工作区内某文档的已定义符号）**
    - **Validates: Requirements 5.2**
    - 文件 `src/lsp_server/prop_workspace_symbol_test.mbt`，生成随机多文档工作区与查询字符串，`holds_for_all` ≥100 迭代

- [x] 10. 重命名（`src/lsp_server/rename.mbt`，旁路新增）
  - [x] 10.1 实现 WorkspaceEdit 与重命名
    - 在 `src/lsp_server/rename.mbt` 实现 `TextEdit`（`range`/`new_text`）、`WorkspaceEdit`（`changes : Array[(String, Array[TextEdit])]`）、`rename(a, name, new_name) -> WorkspaceEdit`（将某符号全部出现改名）、`apply_workspace_edit(text, edits) -> String`（供完整性属性验证）
    - 复用 `analyze` 的符号/引用位置，不重写解析
    - _Requirements: 5.4_

  - [x] 10.2 编写属性测试：重命名完整性
    - **Property 9: 重命名完整性（应用 `rename` 的 `WorkspaceEdit` 后原名全部出现变为新名、其余文本不变，且重分析后新名出现数 = 原名原出现数）**
    - **Validates: Requirements 5.4, 5.10**
    - 文件 `src/lsp_server/prop_rename_test.mbt`，生成随机 DSL 文档、某已定义键与未被占用新名，`holds_for_all` ≥100 迭代

- [x] 11. 格式化与代码动作（`src/lsp_server/format.mbt`，旁路新增）
  - [x] 11.1 实现格式化与代码动作
    - 在 `src/lsp_server/format.mbt` 实现 `formatting(doc) -> Array[TextEdit]`（规范化 `key = value` 等号周边空白）、`CodeAction`（`title`/`edit`）、`code_actions(a, d) -> Array[CodeAction]`（针对某条诊断的快速修复）
    - _Requirements: 5.5, 5.6_

  - [x] 11.2 代码动作单元测试（针对诊断的修复动作典型输出）
    - 在 `src/lsp_server/format_test.mbt` 覆盖某条诊断产出可用代码动作列表、空白规范化文本编辑的具体见证
    - _Requirements: 5.6_

  - [x] 11.3 编写属性测试：格式化幂等
    - **Property 17: 格式化幂等（`format(format(x)) == format(x)`：对规范化文本再次应用 `formatting` 不再产生改变文本的编辑）**
    - **Validates: Requirements 5.5**
    - 文件 `src/lsp_server/prop_format_idempotence_test.mbt`，生成随机 DSL 文档，`holds_for_all` ≥100 迭代

- [x] 12. 签名帮助、语义着色与折叠（`src/lsp_server/semantic.mbt`，旁路新增）
  - [x] 12.1 实现 signatureHelp/semanticTokens/foldingRange
    - 在 `src/lsp_server/semantic.mbt` 实现 `SignatureInfo`（`label`）、`signature_help(a, pos) -> SignatureInfo?`、`semantic_tokens(a) -> Array[Int]`（LSP 5-tuple 增量编码）、`folding_ranges(doc) -> Array[Range]`
    - 复用 `analyze` 投影，输出顺序由源文本出现顺序决定（确定性）
    - _Requirements: 5.7_

  - [x] 12.2 语义能力单元测试（典型输出）
    - 在 `src/lsp_server/semantic_test.mbt` 覆盖 signatureHelp / semanticTokens 5-tuple / foldingRange 的具体见证
    - _Requirements: 5.7_

- [x] 13. 诊断模型 push + pull（`src/lsp_server/diagnostics.mbt`，旁路新增）
  - [x] 13.1 实现 pull 诊断与诊断 JSON 编码
    - 在 `src/lsp_server/diagnostics.mbt` 实现 `pull_diagnostics(doc) -> Array[Diagnostic]`（`textDocument/diagnostic` 请求 → 当前分析诊断）、`diagnostic_to_json(d) -> Json`（输出范围 + 规范严重级别码 Error=1/Warning=2/Information=3/Hint=4 + 消息）；push 路径复用既有 `publish_diagnostics_notification`
    - _Requirements: 6.1, 6.2, 6.4_

  - [x] 13.2 诊断单元测试（严重码映射/push 通知构造/pull 响应）
    - 在 `src/lsp_server/diagnostics_test.mbt` 覆盖严重级别码映射、`publishDiagnostics` 通知携带 uri 与诊断数组、pull 请求返回当前诊断的具体见证
    - _Requirements: 6.1, 6.2, 6.4_

  - [x] 13.3 编写属性测试：诊断确定性
    - **Property 10: 诊断确定性（对同一文档多次分析得到逐条相同——顺序与内容一致——的诊断序列）**
    - **Validates: Requirements 6.5, 9.2**
    - 文件 `src/lsp_server/prop_diagnostic_determinism_test.mbt`，生成随机 DSL 文档，`holds_for_all` ≥100 迭代

  - [x] 13.4 编写属性测试：push/pull 诊断等价
    - **Property 18: push/pull 诊断等价（push 路径 `on_did_change`/`publish_diagnostics_notification` 与 pull 路径 `pull_diagnostics` 得到的诊断集合彼此相等）**
    - **Validates: Requirements 6.3**
    - 文件 `src/lsp_server/prop_push_pull_test.mbt`，生成随机 DSL 文档，`holds_for_all` ≥100 迭代

- [x] 14. 检查点 —— 确保扩展能力（references/rename/format/semantic/diagnostics）全部测试通过
  - 在三后端运行 `src/lsp_server` 至此为止的全部单元与属性测试；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 15. 既有兼容回归与非法输入错误条件（向后兼容硬约束）
  - [x] 15.1 编写属性测试：既有分析不变
    - **Property 11: 既有分析不变（深化后 `analyze` 对既有 DSL 文法文档产出的符号、引用与诊断与 `0.1.0` 行为相等，以冻结黄金基线对照）**
    - **Validates: Requirements 10.8**
    - 文件 `src/lsp_server/prop_legacy_analyze_test.mbt`，生成随机既有文法文档，`holds_for_all` ≥100 迭代

  - [x] 15.2 编写属性测试：非法输入错误条件
    - **Property 16: 非法输入错误条件（畸形 `Content-Length` 帧、非法 JSON 正文、越界增量变更均返回携带恰当标准错误码的 `RpcError`，不 panic/abort，不产生部分构造消息或部分应用文本）**
    - **Validates: Requirements 2.3, 3.5, 11.3**
    - 文件 `src/lsp_server/prop_error_conditions_test.mbt`（导入 `@lsp_binding` 覆盖帧/JSON 错误，结合 `sync.apply_changes` 越界），`holds_for_all` ≥100 迭代

  - [x] 15.3 协议层既有裸 JSON 行为回归
    - 在 `src/lsp_binding/binding_test.mbt` 补充回归断言：既有裸 JSON 正文的 `decode_message`/`encode_message`/`dispatch`/`error_response` 行为与 `0.1.0` 逐字段一致，五个错误码常量与 `RpcError` 形态不变
    - _Requirements: 10.1, 10.2_

  - [x] 15.4 能力层既有 API 回归
    - 在 `src/lsp_server/server_test.mbt` 补充回归断言：`on_initialize`/`on_did_change`/`on_completion`/`on_definition`/`on_hover`/`capabilities_to_json`/`publish_diagnostics_notification`/`position_from_json` 与既有类型字段行为与 `0.1.0` 一致
    - _Requirements: 10.3, 10.4, 10.5_

- [x] 16. 端到端会话 demo（`src/lsp_server/demo.mbt`，旁路新增）
  - [x] 16.1 实现贯穿全流程的会话脚本
    - 在 `src/lsp_server/demo.mbt` 实现 `SessionStep`（`label`/`output`）与 `run_session_demo() -> Array[SessionStep]`，驱动一份内置 DSL 文档依次走过 `initialize` → `didOpen` → 增量 `didChange` → `diagnostics`/`completion`/`definition`/`references`/`rename`/`hover` → `shutdown`/`exit`，产出确定性结果；脚本内断言增量 `didChange` 后请求的诊断与对变更后全文做全量替换后的诊断相等
    - 串联任务 5/6/7/9/10/13 的能力与协议层 `dispatch`
    - _Requirements: 9.1, 9.2, 9.3_

  - [x] 16.2 demo 单元测试（增量后诊断 == 全量诊断；确定性）
    - 在 `src/lsp_server/demo_test.mbt` 断言会话各步骤输出确定、增量后诊断与全量替换诊断逐条相等
    - _Requirements: 9.2, 9.3_

- [x] 17. 性能基准（`benches/lsp_bench/`，新增包）
  - [x] 17.1 创建基准包骨架
    - 新增 `benches/lsp_bench/moon.pkg` 与 `benches/lsp_bench/pkg.generated.mbti`，结构对齐既有 `benches/astar_bench`，声明对 `lsp_binding` 与 `lsp_server` 的依赖
    - _Requirements: 7.1_

  - [x] 17.2 实现五类工作负载基准与回归工件
    - 在 `benches/lsp_bench/lsp_bench.mbt` 实现五类负载：(1) decode/encode 往返吞吐；(2) `dispatch` 路由吞吐；(3) 大文档 `analyze`；(4) 增量同步 `apply_changes`；(5) `references`/`rename`；输出含机器标识、后端目标、输入规模与计时统计的 JSON / Markdown 工件至 `benches/results/`，并接入 guard 与基线中位数比较、超容差给出可审计失败报告
    - 在基准文档 / 脚本注明：运行 native 基准前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`，并记录可复现运行命令与规模参数
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [x] 18. 集成、文档与双包发布推进
  - [x] 18.1 同步 `lsp_binding` 公开接口签名文件
    - 重新生成并提交 `src/lsp_binding/pkg.generated.mbti`，追加全部新增 `pub` 声明（`encode_framed`/`decode_framed`/`FrameReader`、`decode_batch`/`dispatch_batch`/`encode_batch`、`request_cancelled_code`/`CancelRegistry`/`cancel_id_of`/`cancelled_response`、`id_of`/`correlate`），既有条目保持稳定不删改
    - _Requirements: 10.1, 10.2, 10.5_

  - [x] 18.2 同步 `lsp_server` 公开接口签名文件
    - 重新生成并提交 `src/lsp_server/pkg.generated.mbti`，追加全部新增 `pub` 声明（`LifecycleState`/`LifecycleEvent`/`StepResult`/`LspSession`/`step`、`ServerCapabilitiesExt`/`InitializeParamsExt`/`negotiate`、`TextDocumentSyncKind`/`ContentChange`/`VersionedDocument`/`apply_changes`、`PositionEncoding`/`position_to_offset`/`offset_to_position`/`convert_position`/`negotiate_encoding`/`code_units`、`DocumentSymbol`/`document_symbols`/`workspace_symbols`/`references`/`document_highlights`、`TextEdit`/`WorkspaceEdit`/`rename`/`apply_workspace_edit`、`formatting`/`CodeAction`/`code_actions`、`SignatureInfo`/`signature_help`/`semantic_tokens`/`folding_ranges`、`pull_diagnostics`/`diagnostic_to_json`、`SessionStep`/`run_session_demo`），既有条目保持稳定不删改
    - _Requirements: 10.3, 10.4, 10.5_

  - [x] 18.3 扩充 `lsp_binding` 可执行文档
    - 在 `src/lsp_binding/README.mbt.md`（若不存在则新建）串联头部帧编解码、批量与取消、单条/批量分发、id 关联的可运行示例（经 `moon test *.mbt.md` 验证），并补充：JSON-RPC 2.0 与 LSP Base Protocol 追溯、与 vscode-languageserver-node/tower-lsp 的传输与帧处理对比、实现边界声明（纯函数式帧切分、无真实 IO 运行时）
    - 注明：校验 native 后端可执行文档前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 8.1, 8.2, 8.4, 8.5, 11.4_

  - [x] 18.4 扩充 `lsp_server` 可执行文档
    - 在 `src/lsp_server/README.mbt.md` 串联生命周期、增量同步、位置编码换算、扩展语言能力（documentSymbol/references/rename/formatting/codeAction/signatureHelp/semanticTokens/foldingRange/documentHighlight）、push+pull 诊断与端到端 `run_session_demo` 的可运行示例（经 `moon test *.mbt.md` 验证），并补充：LSP 规范与位置编码追溯、与 rust-analyzer/gopls/tower-lsp/vscode-languageserver-node 的能力协商/文档同步/诊断模型对比、实现边界声明（消息与文档模型层、分析针对内置 DSL、单工作区内存多文档）
    - 注明：校验 native 后端可执行文档前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 9.4, 11.4_

  - [x] 18.5 推进 `lsp_binding` 独立 SemVer 与 CHANGELOG
    - 新增 `src/lsp_binding/release.mbt`，旁路新增本子包独立 SemVer 版本常量 `lsp_binding_version`（自 `0.1.0` 起做次/主版本推进），不影响 `lsp_server` 中以 "lsp" 名义登记的单一发布单元语义；新建 `src/lsp_binding/CHANGELOG.md` 记录协议层旗舰深化（帧/批量/取消/关联）的新增能力与版本条目
    - _Requirements: 11.6_

  - [x] 18.6 推进 `lsp_server` SemVer 与 CHANGELOG
    - 在 `src/lsp_server/release.mbt` 仅更新 `lsp_version` 字符串（自 `0.1.0` 起做次/主版本推进），保持 `release_info`/`release_info_with_gates`/`lsp_name`/`lsp_changelog_path` 语义不变；在 `src/lsp_server/CHANGELOG.md` 追加本次旗舰深化（生命周期/同步/编码/扩展能力/诊断/demo）的新增能力与版本条目，仍以 "lsp" 单一发布单元登记
    - _Requirements: 11.6_

  - [x] 18.7 发布门禁真值表测试
    - 在 `src/lsp_server/release_test.mbt` 补充覆盖 `release_info_with_gates`：三后端测试 / 属性测试 / 可执行文档任一未过即阻止本方向进入 release-ready
    - _Requirements: 11.7_

- [x] 19. 最终检查点 —— 确保三后端全部测试与文档校验通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行两个子包的全部单元测试、18 条属性测试（各 ≥100 迭代）与 `moon test *.mbt.md`；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。任一后端输出分歧即判失败。
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- 标记 `*` 的子任务为可选测试任务（单元 / 属性 / 集成回归 / 门禁），可为加速 MVP 跳过，但 Property 1–18 属性测试是 Requirement 11.2 的质量门禁，发布前应全部补齐。
- 每个任务引用具体需求条款（`_Requirements: X.Y_`）以保证可追溯；每条属性子任务标注 `Property N` 与 `**Validates: Requirements X.Y**`，并以 `@infra_pbt` 实现、每条 ≥100 迭代（标签 `Feature: lsp, Property N`）。
- 检查点（任务 4 / 8 / 14 / 19）用于增量验证；属性测试验证通用不变量，单元测试锁定具体见证与边界 / 错误条件。
- **既有契约冻结**：两包 `types.mbt` / `json.mbt` / `binding.mbt` / `dsl.mbt` / `server.mbt` / `release.mbt`（除 `lsp_version` 字面量）既有 `pub`/`pub(all)` 声明不改；新能力一律以新增 `.mbt` 文件旁路扩展；`RpcError` 与五个错误码不扩容，取消语义经新增常量 `request_cancelled_code` 承载；扩展能力复用 `analyze` 投影，不重写解析；既有裸 JSON decode/encode/dispatch 行为逐字节不变。
- **跨文件依赖提示**：`sync.apply_changes`（任务 7）依赖 `PositionEncoding`（任务 6），`lifecycle`（任务 5.1）依赖 `capabilities_ext`（任务 5.2），故依赖图中令二者类型先行可用；同一波次内各叶子子任务写入互不相同的文件，无并行写同文件冲突。
- **native 前置**：凡涉及 native 后端测试、基准运行、`README.mbt.md` 文档校验的任务（含任务 4、8、14、17.2、18.3、18.4、19），均须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "3.1", "3.2", "5.2", "6.1"] },
    { "id": 1, "tasks": ["5.1", "7.1", "1.2", "1.3", "2.2", "2.3", "3.3", "3.4", "3.5", "6.2", "6.3", "6.4"] },
    { "id": 2, "tasks": ["5.3", "5.4", "5.5", "7.2", "7.3", "9.1", "10.1", "11.1", "12.1", "13.1"] },
    { "id": 3, "tasks": ["9.2", "9.3", "10.2", "11.2", "11.3", "12.2", "13.2", "13.3", "13.4", "15.1", "15.2", "15.3", "15.4", "16.1"] },
    { "id": 4, "tasks": ["16.2", "17.1", "18.1", "18.2"] },
    { "id": 5, "tasks": ["17.2", "18.3", "18.4", "18.5", "18.6", "18.7"] }
  ]
}
```
