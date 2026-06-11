// types.mbt —— LSP_Server 能力处理器涉及的核心数据模型（任务 14.2）。
//
// 设计依据（design.md §「方向五：LSP_Server / LSP_Binding」流水线签名）：
//
//   pub fn on_initialize(params : InitializeParams) -> ServerCapabilities
//   pub fn on_did_change(doc : TextDocument) -> Array[Diagnostic]
//   pub fn on_completion(pos : Position) -> Array[CompletionItem]
//   pub fn on_definition(pos : Position) -> Location?
//   pub fn on_hover(pos : Position) -> Hover?
//
// design.md 仅给出上述签名而未展开各类型字段，故本文件按 LSP 规范的常用形态
// 给出精简、纯数据的定义（Position/Range/TextDocument/Diagnostic/
// CompletionItem/Location/Hover/ServerCapabilities/InitializeParams）。
//
// 坐标约定：遵循 LSP 规范，`Position` 的 line / character 均为 **0 基**，
// `Range` 的 `end` 为**排他**（half-open）。

// ───────────────────────────── 位置与范围 ─────────────────────────────

///|
/// 文档位置：行号 `line` 与列号 `character`，均为 0 基（LSP 约定）。
pub(all) struct Position {
  line : Int
  character : Int
} derive(Eq)

///|
/// 文档范围：闭开区间 `[start, end)`（`end` 排他）。
pub(all) struct Range {
  start : Position
  end : Position
} derive(Eq)

///|
/// 文档定位：资源标识 `uri` + 范围 `range`，用于「跳转定义」返回符号定义处。
pub(all) struct Location {
  uri : String
  range : Range
} derive(Eq)

// ───────────────────────────── 文档 ───────────────────────────────────

///|
/// 一份文本文档：资源标识 `uri` + 全文 `text`。`didChange` 通知携带变更后的
/// 全文，服务端据此重分析（Requirement 5.5）。
pub(all) struct TextDocument {
  uri : String
  text : String
} derive(Eq)

// ───────────────────────────── 诊断 ───────────────────────────────────

///|
/// 诊断严重级别（LSP 规范的四档）。
pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Information
  Hint
} derive(Eq)

///|
/// 一条诊断：范围 `range` + 级别 `severity` + 人类可读 `message`
/// （Requirement 5.5 publishDiagnostics 的元素）。
pub(all) struct Diagnostic {
  range : Range
  severity : DiagnosticSeverity
  message : String
} derive(Eq)

// ───────────────────────────── 补全 ───────────────────────────────────

///|
/// 补全项类别（取 LSP 规范常用子集）。
pub(all) enum CompletionItemKind {
  Variable
  Keyword
  Value
} derive(Eq)

///|
/// 一个补全候选：展示标签 `label` + 类别 `kind` + 详情 `detail`
/// （Requirement 5.6）。
pub(all) struct CompletionItem {
  label : String
  kind : CompletionItemKind
  detail : String
} derive(Eq)

// ───────────────────────────── 悬停 ───────────────────────────────────

///|
/// 悬停信息：描述文本 `contents` + 可选作用范围 `range`（Requirement 5.8）。
pub(all) struct Hover {
  contents : String
  range : Range?
} derive(Eq)

// ───────────────────────────── 初始化与能力 ───────────────────────────

///|
/// `initialize` 请求参数（精简）：可选的工作区根 `root_uri`。
pub(all) struct InitializeParams {
  root_uri : String?
} derive(Eq)

///|
/// 服务端能力声明（Requirement 5.4）：在 `initialize` 响应中声明所支持的
/// 诊断 / 补全 / 跳转定义 / 悬停 四项能力。
pub(all) struct ServerCapabilities {
  diagnostic_provider : Bool
  completion_provider : Bool
  definition_provider : Bool
  hover_provider : Bool
} derive(Eq)
