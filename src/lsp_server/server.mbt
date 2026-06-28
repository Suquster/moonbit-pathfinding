// server.mbt —— LSP_Server 五个能力处理器 + 与 @lsp_binding 的 JSON-RPC 适配
// （任务 14.2）。
//
// 五个处理器（design.md §「方向五」流水线）：
//   on_initialize / on_did_change / on_completion / on_definition / on_hover。
//
// design.md 的 on_completion / on_definition / on_hover 仅以 `Position` 为参，
// 隐含「服务端持有当前文档分析」。为保持处理器为**纯函数**（利于三后端逐位
// 一致与可测试性），本实现将分析结果 `Analysis` 显式作为首参传入；`Analysis`
// 由 `on_did_change`（或 `analyze`）产出，等价于服务端缓存的文档状态。
//
// 与 @lsp_binding 的协作：本文件提供若干适配器，将能力结果序列化为
// @lsp_binding 的 JSON 值（Json）与 JSON-RPC 消息（JsonRpcMessage），
// 例如 initialize 响应的 capabilities 与 publishDiagnostics 通知。

// ───────────────────────────── 能力处理器 ─────────────────────────────

///|
/// 处理 `initialize` 请求：声明本服务端支持的四项能力（Requirement 5.4）。
/// 参数当前未参与能力裁剪（恒定声明全部四项），保留以贴合 LSP 流水线签名。
pub fn on_initialize(params : InitializeParams) -> ServerCapabilities {
  // 忽略 root_uri 内容，但显式读取以表明参数语义（避免未使用告警语义）。
  let _ = params.root_uri
  {
    diagnostic_provider: true,
    completion_provider: true,
    definition_provider: true,
    hover_provider: true,
  }
}

///|
/// 处理 `didChange` 通知：重分析文档并返回诊断列表，供发布
/// `publishDiagnostics`（Requirement 5.5）。
pub fn on_did_change(doc : TextDocument) -> Array[Diagnostic] {
  analyze(doc).diagnostics
}

///|
/// 处理 `completion` 请求：返回基于上下文的补全候选（Requirement 5.6）。
///
/// 策略：返回当前文档中所有**已定义键**作为候选（kind = Variable，detail 给出
/// 该键的值），帮助在编写 `${...}` 引用或重新赋值时补全键名。按键名去重并保持
/// 定义出现顺序。`pos` 当前用于上下文判断的占位（始终返回全部已定义键）。
pub fn on_completion(
  analysis : Analysis,
  pos : Position,
) -> Array[CompletionItem] {
  let _ = pos
  let items : Array[CompletionItem] = []
  let seen : Map[String, Bool] = Map([])
  for s in analysis.symbols {
    match seen.get(s.name) {
      Some(_) => ()
      None => {
        seen[s.name] = true
        items.push({ label: s.name, kind: Variable, detail: "= " + s.value })
      }
    }
  }
  items
}

///|
/// 处理 `definition` 请求：若 `pos` 落在某个 `${key}` 引用上且该键已定义，
/// 返回该键定义所在的位置（Requirement 5.7）。若 `pos` 落在键定义自身，则
/// 返回其自身位置（go-to-definition 的自洽行为）。否则返回 `None`。
pub fn on_definition(analysis : Analysis, pos : Position) -> Location? {
  match reference_at(analysis, pos) {
    Some(r) =>
      match lookup_symbol(analysis, r.name) {
        Some(s) => Some({ uri: analysis.uri, range: s.range })
        None => None // 引用了未定义的键：无定义可跳转。
      }
    None =>
      match symbol_at(analysis, pos) {
        Some(s) => Some({ uri: analysis.uri, range: s.range })
        None => None
      }
  }
}

///|
/// 处理 `hover` 请求：当 `pos` 位于已知符号（键定义或对已定义键的引用）上，
/// 返回该符号的描述信息（Requirement 5.8）。否则返回 `None`。
pub fn on_hover(analysis : Analysis, pos : Position) -> Hover? {
  match symbol_at(analysis, pos) {
    Some(s) =>
      Some({
        contents: "(键) " + s.name + " = " + s.value,
        range: Some(s.range),
      })
    None =>
      match reference_at(analysis, pos) {
        Some(r) =>
          match lookup_symbol(analysis, r.name) {
            Some(s) =>
              Some({
                contents: "(引用) " + r.name + " = " + s.value,
                range: Some(r.range),
              })
            None =>
              Some({
                contents: "(引用) " + r.name + "（未定义）",
                range: Some(r.range),
              })
          }
        None => None
      }
  }
}

// ───────────────── 与 @lsp_binding 的 JSON-RPC 序列化适配 ─────────────

///|
/// 将整数编码为 @lsp_binding 的 JSON 数值（保留原始字面量文本）。
fn jint(n : Int) -> @lsp_binding.Json {
  @lsp_binding.JNum(n.to_string())
}

///|
/// 将 `Position` 编码为 LSP JSON 对象 `{ "line", "character" }`。
fn position_to_json(p : Position) -> @lsp_binding.Json {
  @lsp_binding.JObj([("line", jint(p.line)), ("character", jint(p.character))])
}

///|
/// 将 `Range` 编码为 LSP JSON 对象 `{ "start", "end" }`。
fn range_to_json(r : Range) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("start", position_to_json(r.start)),
    ("end", position_to_json(r.end)),
  ])
}

///|
/// LSP 诊断严重级别 → 规范数值码（Error=1, Warning=2, Information=3, Hint=4）。
fn severity_code(s : DiagnosticSeverity) -> Int {
  match s {
    Error => 1
    Warning => 2
    Information => 3
    Hint => 4
  }
}

///|
/// 将一条 `Diagnostic` 编码为 LSP JSON 对象：输出其范围、规范严重级别码
/// （Error=1 / Warning=2 / Information=3 / Hint=4）与消息（Requirement 6.4）。
///
/// 任务 13.1（pull 诊断与诊断 JSON 编码）需要本编码能力作为公开 API。该函数自
/// `0.1.0` 起即以等价行为存在（彼时为私有），此处仅将可见性提升为 `pub`：纯
/// 追加、向后兼容，不改变签名、行为或任何既有调用方（Requirement 10.5）。
pub fn diagnostic_to_json(d : Diagnostic) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("range", range_to_json(d.range)),
    ("severity", jint(severity_code(d.severity))),
    ("message", @lsp_binding.JStr(d.message)),
  ])
}

///|
/// 将 `ServerCapabilities` 编码为 LSP `initialize` 响应中的 `capabilities`
/// JSON 对象（Requirement 5.4）。
pub fn capabilities_to_json(caps : ServerCapabilities) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("diagnosticProvider", @lsp_binding.JBool(caps.diagnostic_provider)),
    ("completionProvider", @lsp_binding.JBool(caps.completion_provider)),
    ("definitionProvider", @lsp_binding.JBool(caps.definition_provider)),
    ("hoverProvider", @lsp_binding.JBool(caps.hover_provider)),
  ])
}

///|
/// 构造一条 `textDocument/publishDiagnostics` 通知消息（Requirement 5.5）：
/// 携带文档 `uri` 与诊断数组，复用 @lsp_binding 的 `JsonRpcMessage`。
pub fn publish_diagnostics_notification(
  uri : String,
  diagnostics : Array[Diagnostic],
) -> @lsp_binding.JsonRpcMessage {
  let arr : Array[@lsp_binding.Json] = []
  for d in diagnostics {
    arr.push(diagnostic_to_json(d))
  }
  let params = @lsp_binding.JObj([
    ("uri", @lsp_binding.JStr(uri)),
    ("diagnostics", @lsp_binding.JArr(arr)),
  ])
  @lsp_binding.Notification(method_name="textDocument/publishDiagnostics", params~)
}

///|
/// 从 LSP JSON 对象 `{ "line", "character" }` 还原 `Position`；字段缺失或
/// 非整数返回 `None`。供 completion / definition / hover 请求参数解析复用。
pub fn position_from_json(json : @lsp_binding.Json) -> Position? {
  match json {
    @lsp_binding.JObj(fields) => {
      let line = json_int_field(fields, "line")
      let character = json_int_field(fields, "character")
      match (line, character) {
        (Some(l), Some(c)) => Some({ line: l, character: c })
        _ => None
      }
    }
    _ => None
  }
}

///|
/// 在 JSON 对象字段中按 key 取出整数数值字段；缺失/非整数返回 `None`。
fn json_int_field(
  fields : Array[(String, @lsp_binding.Json)],
  key : String,
) -> Int? {
  for kv in fields {
    let (k, v) = kv
    if k == key {
      match v {
        @lsp_binding.JNum(s) => return parse_int(s)
        _ => return None
      }
    }
  }
  None
}

///|
/// 将一个十进制整数字面量文本解析为 `Int`；非整数返回 `None`。
fn parse_int(s : String) -> Int? {
  let cs = line_chars(s)
  if cs.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if cs[0] == '-' {
    neg = true
    i = 1
  } else if cs[0] == '+' {
    i = 1
  }
  if i >= cs.length() {
    return None
  }
  let mut v = 0
  while i < cs.length() {
    let c = cs[i]
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      i = i + 1
    } else {
      return None
    }
  }
  Some(if neg { -v } else { v })
}
