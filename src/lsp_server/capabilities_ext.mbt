// capabilities_ext.mbt —— 扩展能力声明与初始化参数（旗舰深化，任务 5.2 旁路新增）。
//
// 旁路扩展说明（design.md §3.5 / 数据模型）：
//   本文件**不修改**既有 `ServerCapabilities`（types.mbt 中的四项 provider）与
//   `InitializeParams`（仅 `root_uri`）的字段与语义；而是新增两个并存的扩展结构：
//     * `ServerCapabilitiesExt` —— 在既有四项（诊断/补全/定义/悬停）之上旁路追加
//       documentSymbol / references / rename / formatting / codeAction /
//       signatureHelp / semanticTokens / foldingRange / documentHighlight 各 provider 位；
//     * `InitializeParamsExt` —— 旁路携带客户端声明的能力名集合与位置编码名集合，
//       不改既有 `InitializeParams.root_uri`。
//
// 实现边界：客户端 capabilities 以 `Array[String]`（能力名集合）表示；位置编码以
// `Array[String]`（encoding 名）承载——`PositionEncoding` 在任务 6 才定义，这里用
// 字符串名规避跨任务依赖。
//
// 注意：能力协商函数 `negotiate(client) -> ServerCapabilitiesExt` 由**任务 5.2** 补充，
// 本文件仅定义所需数据类型与构造器，供任务 5.1（lifecycle.mbt）的会话句柄使用。

// ───────────────────────────── 扩展服务端能力 ─────────────────────────

///|
/// 扩展服务端能力声明（design.md §3.5）：在既有 `ServerCapabilities` 四项 provider
/// 之上旁路追加九个扩展语言能力的 provider 位。全部为 `Bool`，便于按客户端声明裁剪。
pub(all) struct ServerCapabilitiesExt {
  // 既有四项（与 ServerCapabilities 对齐）
  diagnostic_provider : Bool
  completion_provider : Bool
  definition_provider : Bool
  hover_provider : Bool
  // 旗舰扩展九项
  document_symbol_provider : Bool
  references_provider : Bool
  rename_provider : Bool
  formatting_provider : Bool
  code_action_provider : Bool
  signature_help_provider : Bool
  semantic_tokens_provider : Bool
  folding_range_provider : Bool
  document_highlight_provider : Bool
} derive(Eq, Debug)

///|
/// 全 `false` 的扩展能力（不声明任何能力）。作为能力协商的累积起点。
pub fn ServerCapabilitiesExt::none() -> ServerCapabilitiesExt {
  {
    diagnostic_provider: false,
    completion_provider: false,
    definition_provider: false,
    hover_provider: false,
    document_symbol_provider: false,
    references_provider: false,
    rename_provider: false,
    formatting_provider: false,
    code_action_provider: false,
    signature_help_provider: false,
    semantic_tokens_provider: false,
    folding_range_provider: false,
    document_highlight_provider: false,
  }
}

///|
/// 全 `true` 的扩展能力（声明全部能力）。表示服务端对全部语言能力的最大支持集，
/// 能力协商（任务 5.2）将以此为上界、按客户端声明裁剪。
pub fn ServerCapabilitiesExt::all() -> ServerCapabilitiesExt {
  {
    diagnostic_provider: true,
    completion_provider: true,
    definition_provider: true,
    hover_provider: true,
    document_symbol_provider: true,
    references_provider: true,
    rename_provider: true,
    formatting_provider: true,
    code_action_provider: true,
    signature_help_provider: true,
    semantic_tokens_provider: true,
    folding_range_provider: true,
    document_highlight_provider: true,
  }
}

///|
/// 默认扩展能力：声明服务端支持的全部语言能力（等价 `all()`）。
/// `LspSession` 在未经协商时以此回报 `initialize` 响应的 capabilities。
pub fn ServerCapabilitiesExt::default() -> ServerCapabilitiesExt {
  ServerCapabilitiesExt::all()
}

// ───────────────────────────── 扩展初始化参数 ─────────────────────────

///|
/// 扩展 `initialize` 请求参数（design.md §3.5）：旁路携带客户端声明的能力名集合
/// `capabilities` 与客户端支持的位置编码名集合 `position_encodings`。
/// 不改既有 `InitializeParams.root_uri`；二者并存。
pub(all) struct InitializeParamsExt {
  capabilities : Array[String]
  position_encodings : Array[String]
} derive(Eq, Debug)

///|
/// 构造一个空的扩展初始化参数（客户端未声明任何能力或位置编码）。
pub fn InitializeParamsExt::empty() -> InitializeParamsExt {
  { capabilities: [], position_encodings: [] }
}

///|
/// 由能力名集合与位置编码名集合构造扩展初始化参数。
pub fn InitializeParamsExt::new(
  capabilities : Array[String],
  position_encodings : Array[String],
) -> InitializeParamsExt {
  { capabilities, position_encodings }
}

// ───────────────────────────── 能力协商 ─────────────────────────────

///|
/// 规范能力名 → provider 位的对应关系（design.md §3.5 / 数据模型）。
/// 客户端 `capabilities : Array[String]` 以这些规范名声明其所支持的能力。
/// 能力协商在服务端能力集（全部支持）与客户端声明集之间取交集。
const CAP_DIAGNOSTIC : String = "diagnostic"

///|
const CAP_COMPLETION : String = "completion"

///|
const CAP_DEFINITION : String = "definition"

///|
const CAP_HOVER : String = "hover"

///|
const CAP_DOCUMENT_SYMBOL : String = "documentSymbol"

///|
const CAP_REFERENCES : String = "references"

///|
const CAP_RENAME : String = "rename"

///|
const CAP_FORMATTING : String = "formatting"

///|
const CAP_CODE_ACTION : String = "codeAction"

///|
const CAP_SIGNATURE_HELP : String = "signatureHelp"

///|
const CAP_SEMANTIC_TOKENS : String = "semanticTokens"

///|
const CAP_FOLDING_RANGE : String = "foldingRange"

///|
const CAP_DOCUMENT_HIGHLIGHT : String = "documentHighlight"

///|
/// 检查某规范能力名是否被客户端声明（在 `client.capabilities` 中线性查找）。
fn declares(client : InitializeParamsExt, name : String) -> Bool {
  for cap in client.capabilities {
    if cap == name {
      return true
    }
  }
  false
}

///|
/// 能力协商（Requirement 1.7、5.1–5.7）：以 `ServerCapabilitiesExt::none()`（全 false）
/// 为起点，对客户端 `capabilities` 中声明的每个规范能力名，若服务端支持（本实现支持
/// 全部已知能力），则将结果中对应 provider 位置为 `true`；客户端未声明的能力保持 `false`。
///
/// 因此返回的能力集恰为「客户端声明能力集 ∩ 服务端能力集」，在服务端支持全部已知能力的
/// 前提下等于客户端所声明能力的子集（限于已知规范能力名），满足子集裁剪不变量。
/// 纯函数，三后端一致。
pub fn negotiate(client : InitializeParamsExt) -> ServerCapabilitiesExt {
  {
    diagnostic_provider: declares(client, CAP_DIAGNOSTIC),
    completion_provider: declares(client, CAP_COMPLETION),
    definition_provider: declares(client, CAP_DEFINITION),
    hover_provider: declares(client, CAP_HOVER),
    document_symbol_provider: declares(client, CAP_DOCUMENT_SYMBOL),
    references_provider: declares(client, CAP_REFERENCES),
    rename_provider: declares(client, CAP_RENAME),
    formatting_provider: declares(client, CAP_FORMATTING),
    code_action_provider: declares(client, CAP_CODE_ACTION),
    signature_help_provider: declares(client, CAP_SIGNATURE_HELP),
    semantic_tokens_provider: declares(client, CAP_SEMANTIC_TOKENS),
    folding_range_provider: declares(client, CAP_FOLDING_RANGE),
    document_highlight_provider: declares(client, CAP_DOCUMENT_HIGHLIGHT),
  }
}
