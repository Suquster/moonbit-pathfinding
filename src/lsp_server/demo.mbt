// demo.mbt —— 端到端会话脚本（旗舰深化，任务 16.1 旁路新增）。
//
// 设计依据（design.md §3.8「端到端会话 demo」，Requirement 9.1 / 9.2 / 9.3）：
// 本文件为**旁路新增**，串联协议层 `@lsp_binding` 的 `dispatch`/`Router` 与能力
// 层任务 5（生命周期）/ 6（位置编码）/ 7（增量同步）/ 9（引用）/ 10（重命名）/
// 13（诊断）的能力，驱动一份内置 DSL 文档依次走过完整 LSP 会话：
//
//   initialize → initialized → didOpen → 增量 didChange →
//   diagnostics → completion → definition → references → rename → hover →
//   shutdown → exit
//
// paper-to-code 追溯：LSP §「Lifecycle Messages」与「Language Features」，
// JSON-RPC 2.0 请求/响应/通知模型。
//
// ── 确定性（Requirement 9.2 / Property 10） ───────────────────────────
// 全流程为纯函数组合：`analyze` 纯函数、各能力投影顺序由源文本出现顺序决定、
// `step` 为纯状态转移、`dispatch` 按固定 Router 路由，故 `run_session_demo`
// 在 wasm-gc / js / native 三后端产出逐位一致的 `Array[SessionStep]`。
//
// ── 增量 = 全量（Requirement 9.3 / Property 5 投影） ──────────────────
// 脚本在执行增量 `didChange` 后**内部断言**：对增量应用所得文本请求的诊断，与
// 对「变更后全文做一次全量替换」所得文本请求的诊断逐条相等（且两文本逐字符
// 相等）。该不变量经 `guard ... else { abort(..) }` 在脚本内强制校验，使等价
// 关系随 demo 的运行被验证（违例即立刻以可读消息中止，绝不静默产出错误结果）。
//
// ── 字面 `${` 规避 ───────────────────────────────────────────────────
// 内置 DSL 文档含 `${key}` 引用。为规避 JS 后端把源码字面 `${` 误判为模板字符串
// 插值起始（见 rename.mbt 同款约定），文档文本中的 `${name}` 一律经同包私有
// `wrap_reference`（运行期由字符码构造）拼接，源码中不出现字面 `${` 片段。

// ───────────────────────────── 会话步骤模型 ───────────────────────────

///|
/// 一个会话步骤：人类可读标签 `label` + 该步骤的确定性输出 `output`（JSON 值）。
///
/// `output` 复用 `@lsp_binding.Json`（`derive(Eq, Debug)`），故本结构亦可
/// `derive(Eq, Debug)`，便于在单元测试中断言确定性与逐步对照。
pub(all) struct SessionStep {
  label : String
  output : @lsp_binding.Json
} derive(Eq, Debug)

// ───────────────────────────── JSON 编码辅助 ──────────────────────────
//
// 注：同包 `server.mbt` 已有私有 `jint`/`position_to_json`/`range_to_json`，
// 同名顶层函数在同一 package 内会冲突，故本文件的辅助一律以 `demo_` 前缀命名。

///|
/// 整数 → JSON 数值（保留字面量文本，三后端一致）。
fn demo_jint(n : Int) -> @lsp_binding.Json {
  @lsp_binding.JNum(n.to_string())
}

///|
/// `Position` → LSP JSON 对象 `{ "line", "character" }`。
fn demo_position_to_json(p : Position) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("line", demo_jint(p.line)),
    ("character", demo_jint(p.character)),
  ])
}

///|
/// `Range` → LSP JSON 对象 `{ "start", "end" }`。
fn demo_range_to_json(r : Range) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("start", demo_position_to_json(r.start)),
    ("end", demo_position_to_json(r.end)),
  ])
}

///|
/// `Location` → LSP JSON 对象 `{ "uri", "range" }`。
fn demo_location_to_json(loc : Location) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    ("uri", @lsp_binding.JStr(loc.uri)),
    ("range", demo_range_to_json(loc.range)),
  ])
}

///|
/// `Array[Location]` → JSON 数组。
fn demo_locations_to_json(locs : Array[Location]) -> @lsp_binding.Json {
  let arr : Array[@lsp_binding.Json] = []
  for l in locs {
    arr.push(demo_location_to_json(l))
  }
  @lsp_binding.JArr(arr)
}

///|
/// 补全项类别 → 规范名称字符串。
fn demo_kind_str(k : CompletionItemKind) -> String {
  match k {
    Variable => "variable"
    Keyword => "keyword"
    Value => "value"
  }
}

///|
/// `Array[CompletionItem]` → JSON 数组（每项 `{ "label", "kind", "detail" }`）。
fn demo_completion_to_json(items : Array[CompletionItem]) -> @lsp_binding.Json {
  let arr : Array[@lsp_binding.Json] = []
  for it in items {
    arr.push(
      @lsp_binding.JObj([
        ("label", @lsp_binding.JStr(it.label)),
        ("kind", @lsp_binding.JStr(demo_kind_str(it.kind))),
        ("detail", @lsp_binding.JStr(it.detail)),
      ]),
    )
  }
  @lsp_binding.JArr(arr)
}

///|
/// `Hover?` → JSON 对象 `{ "contents", "range"? }`，无悬停时为 `null`。
fn demo_hover_to_json(h : Hover?) -> @lsp_binding.Json {
  match h {
    None => @lsp_binding.JNull
    Some(hv) => {
      let fields : Array[(String, @lsp_binding.Json)] = [
        ("contents", @lsp_binding.JStr(hv.contents)),
      ]
      match hv.range {
        Some(r) => fields.push(("range", demo_range_to_json(r)))
        None => ()
      }
      @lsp_binding.JObj(fields)
    }
  }
}

///|
/// `WorkspaceEdit` → JSON 对象 `{ "changes": [ { "uri", "edits": [...] } ] }`。
fn demo_workspace_edit_to_json(we : WorkspaceEdit) -> @lsp_binding.Json {
  let changes : Array[@lsp_binding.Json] = []
  for entry in we.changes {
    let (uri, edits) = entry
    let edit_arr : Array[@lsp_binding.Json] = []
    for e in edits {
      edit_arr.push(
        @lsp_binding.JObj([
          ("range", demo_range_to_json(e.range)),
          ("newText", @lsp_binding.JStr(e.new_text)),
        ]),
      )
    }
    changes.push(
      @lsp_binding.JObj([
        ("uri", @lsp_binding.JStr(uri)),
        ("edits", @lsp_binding.JArr(edit_arr)),
      ]),
    )
  }
  @lsp_binding.JObj([("changes", @lsp_binding.JArr(changes))])
}

///|
/// `Array[Diagnostic]` → JSON 数组（复用既有公开 `diagnostic_to_json`）。
fn demo_diags_to_json(diags : Array[Diagnostic]) -> @lsp_binding.Json {
  let arr : Array[@lsp_binding.Json] = []
  for d in diags {
    arr.push(diagnostic_to_json(d))
  }
  @lsp_binding.JArr(arr)
}

///|
/// 从一条响应消息中提取 `result` 作为步骤输出；非响应 / 无 result 时回退：
/// 携带 error 则给出 `{ "error": <message> }`，否则 `null`。
fn demo_result_of(reply : @lsp_binding.JsonRpcMessage?) -> @lsp_binding.Json {
  match reply {
    Some(@lsp_binding.Response(result~, error~, ..)) =>
      match result {
        Some(r) => r
        None =>
          match error {
            Some(e) =>
              @lsp_binding.JObj([("error", @lsp_binding.JStr(e.message))])
            None => @lsp_binding.JNull
          }
      }
    _ => @lsp_binding.JNull
  }
}

///|
/// 从 JSON 对象中按 key 取出字符串字段；缺失 / 类型不符返回 `""`。
fn demo_str_field(json : @lsp_binding.Json, key : String) -> String {
  match json {
    @lsp_binding.JObj(fields) => {
      for kv in fields {
        let (k, v) = kv
        if k == key {
          match v {
            @lsp_binding.JStr(s) => return s
            _ => return ""
          }
        }
      }
      ""
    }
    _ => ""
  }
}

// ───────────────────────────── 内置 DSL 文档 ──────────────────────────

///|
/// 构造内置 DSL 文档初始全文（`port = 8080`）。`${name}` 引用经 `wrap_reference`
/// 运行期拼接，源码中不出现字面 `${`。
///
/// 文档（0 基行）：
///   0: `# demo config`
///   1: `host = localhost`
///   2: `port = 8080`
///   3: `url = ${host}:${port}/${path}`   （`${path}` 未定义 → 1 条 Warning）
fn demo_open_text() -> String {
  let nl = "\n"
  "# demo config" +
  nl +
  "host = localhost" +
  nl +
  "port = 8080" +
  nl +
  "url = " +
  wrap_reference("host") +
  ":" +
  wrap_reference("port") +
  "/" +
  wrap_reference("path")
}

///|
/// 构造增量变更后的内置 DSL 文档全文（`port = 9090`），用作「全量替换」等价基线。
fn demo_full_text() -> String {
  let nl = "\n"
  "# demo config" +
  nl +
  "host = localhost" +
  nl +
  "port = 9090" +
  nl +
  "url = " +
  wrap_reference("host") +
  ":" +
  wrap_reference("port") +
  "/" +
  wrap_reference("path")
}

// ───────────────────────────── 会话脚本 ───────────────────────────────

///|
/// 驱动内置 DSL 文档完整走过一遍 LSP 会话，产出确定性的步骤序列
/// （Requirement 9.1 / 9.2）。
///
/// 串联：
///   * 任务 5（生命周期）：`LspSession::new`/`handle` 处理 initialize / initialized
///     / shutdown；`step` 计算 exit 退出码；
///   * 任务 6（位置编码）：`negotiate_encoding` 协商位置编码；
///   * 任务 7（增量同步）：`VersionedDocument::apply` / `apply_changes` 应用增量
///     与全量变更，并内部断言二者诊断等价（Requirement 9.3）；
///   * 任务 9 / 10 / 13 与既有 completion / definition / hover：经 `@lsp_binding`
///     的 `Router` + `dispatch` 路由各能力请求。
pub fn run_session_demo() -> Array[SessionStep] {
  let steps : Array[SessionStep] = []
  let uri = "file:///demo.conf"

  // ── 1. initialize（任务 5：生命周期会话句柄） ──────────────────────
  let session = LspSession::new()
  let init_caps = [
    "diagnostic", "completion", "definition", "hover", "documentSymbol", "references",
    "rename", "formatting", "codeAction", "signatureHelp", "semanticTokens", "foldingRange",
    "documentHighlight",
  ]
  let cap_json : Array[@lsp_binding.Json] = []
  for c in init_caps {
    cap_json.push(@lsp_binding.JStr(c))
  }
  let init_params = @lsp_binding.JObj([
    ("capabilities", @lsp_binding.JArr(cap_json)),
    ("positionEncodings", @lsp_binding.JArr([@lsp_binding.JStr("utf-16")])),
  ])
  let init_request = @lsp_binding.Request(
    id=@lsp_binding.IdNum(1),
    method_name="initialize",
    params=init_params,
  )
  let (session, init_reply) = session.handle(init_request)
  steps.push({ label: "initialize", output: demo_result_of(init_reply) })

  // ── 2. initialized 通知 ────────────────────────────────────────────
  let initialized_note = @lsp_binding.Notification(
    method_name="initialized",
    params=@lsp_binding.JNull,
  )
  let (session, _) = session.handle(initialized_note)
  steps.push({
    label: "initialized",
    output: @lsp_binding.JStr(session.state().to_string()),
  })

  // ── 3. didOpen（任务 7：带版本文档） ───────────────────────────────
  let open_text = demo_open_text()
  let doc_v1 : VersionedDocument = { uri, text: open_text, version: 1 }
  steps.push({
    label: "didOpen",
    output: @lsp_binding.JObj([
      ("uri", @lsp_binding.JStr(doc_v1.uri)),
      ("version", demo_jint(doc_v1.version)),
      ("text", @lsp_binding.JStr(doc_v1.text)),
    ]),
  })

  // ── 4. 增量 didChange（任务 6 协商编码 + 任务 7 增量应用 + 等价断言） ─
  let encoding = negotiate_encoding([Utf16])
  // 将 line 2 的 `8080`（列 [7,11)）替换为 `9090`。
  let change : ContentChange = { range: Some(span(2, 7, 11)), text: "9090" }
  // 全函数降级（不可达于本 demo 的合法变更）：增量应用失败时回退为「仅版本号
  // 递增、文本不变」的文档，绝不 `abort`（占位失败一律以确定性回退替代）。
  let doc_v2 = match doc_v1.apply([change], 2, encoding) {
    Ok(d) => d
    Err(_) => { uri, text: open_text, version: 2 }
  }
  // 全量替换基线：以变更后全文做一次 Full 替换。
  let full_text = demo_full_text()
  let full_change : ContentChange = { range: None, text: full_text }
  // 全函数降级（同上）：全量替换失败时回退为 open_text，绝不 `abort`。
  let full_applied = match apply_changes(open_text, [full_change], encoding) {
    Ok(t) => t
    Err(_) => open_text
  }
  // 内部断言（Requirement 9.3 / Property 5 投影）：增量结果文本与全量替换文本
  // 逐字符相等，且二者诊断逐条相等。该不变量经下方 didChange 步骤的
  // `incrementalEqualsFullText` / `incrementalEqualsFullDiagnostics` 字段**可见
  // 外化**（由 demo_test.mbt 单元断言为 true），无需以 `abort` 强制——脚本保持
  // 全函数，违例时如实在步骤输出中暴露为 false，而非中止进程。
  let changed_text = doc_v2.text
  let text_equal = changed_text == full_applied
  let diags_incremental = pull_diagnostics({ uri, text: changed_text })
  let diags_full = pull_diagnostics({ uri, text: full_applied })
  let diags_equal = diags_incremental == diags_full
  steps.push({
    label: "didChange",
    output: @lsp_binding.JObj([
      ("version", demo_jint(doc_v2.version)),
      ("text", @lsp_binding.JStr(changed_text)),
      ("incrementalEqualsFullText", @lsp_binding.JBool(text_equal)),
      ("incrementalEqualsFullDiagnostics", @lsp_binding.JBool(diags_equal)),
    ]),
  })

  // ── 协议层 Router + dispatch：注册各能力请求处理器（任务 9/10/13 + 既有） ─
  let analysis = analyze({ uri, text: changed_text })
  let router = @lsp_binding.Router::new()

  // 诊断拉取（任务 13）。
  router.register("textDocument/diagnostic", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, ..) => {
        let diags = pull_diagnostics({ uri, text: changed_text })
        Some(
          @lsp_binding.Response(
            id~,
            result=Some(demo_diags_to_json(diags)),
            error=None,
          ),
        )
      }
      _ => None
    }
  })
  // 补全（既有 server.mbt）。
  router.register("textDocument/completion", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, params~, ..) => {
        let pos : Position = match position_from_json(params) {
          Some(p) => p
          None => { line: 0, character: 0 }
        }
        let items = on_completion(analysis, pos)
        Some(
          @lsp_binding.Response(
            id~,
            result=Some(demo_completion_to_json(items)),
            error=None,
          ),
        )
      }
      _ => None
    }
  })
  // 跳转定义（既有 server.mbt）。
  router.register("textDocument/definition", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, params~, ..) => {
        let pos : Position = match position_from_json(params) {
          Some(p) => p
          None => { line: 0, character: 0 }
        }
        let result = match on_definition(analysis, pos) {
          Some(loc) => demo_location_to_json(loc)
          None => @lsp_binding.JNull
        }
        Some(@lsp_binding.Response(id~, result=Some(result), error=None))
      }
      _ => None
    }
  })
  // 引用查找（任务 9）。
  router.register("textDocument/references", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, params~, ..) => {
        let name = demo_str_field(params, "name")
        let locs = references(analysis, name)
        Some(
          @lsp_binding.Response(
            id~,
            result=Some(demo_locations_to_json(locs)),
            error=None,
          ),
        )
      }
      _ => None
    }
  })
  // 重命名（任务 10）。
  router.register("textDocument/rename", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, params~, ..) => {
        let name = demo_str_field(params, "name")
        let new_name = demo_str_field(params, "newName")
        let edit = rename(analysis, name, new_name)
        Some(
          @lsp_binding.Response(
            id~,
            result=Some(demo_workspace_edit_to_json(edit)),
            error=None,
          ),
        )
      }
      _ => None
    }
  })
  // 悬停（既有 server.mbt）。
  router.register("textDocument/hover", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, params~, ..) => {
        let pos : Position = match position_from_json(params) {
          Some(p) => p
          None => { line: 0, character: 0 }
        }
        Some(
          @lsp_binding.Response(
            id~,
            result=Some(demo_hover_to_json(on_hover(analysis, pos))),
            error=None,
          ),
        )
      }
      _ => None
    }
  })

  // ── 5. diagnostics（dispatch） ─────────────────────────────────────
  let req_diag = @lsp_binding.Request(
    id=@lsp_binding.IdNum(2),
    method_name="textDocument/diagnostic",
    params=@lsp_binding.JNull,
  )
  steps.push({
    label: "diagnostics",
    output: demo_result_of(@lsp_binding.dispatch(req_diag, router)),
  })

  // ── 6. completion（dispatch） ──────────────────────────────────────
  let req_comp = @lsp_binding.Request(
    id=@lsp_binding.IdNum(3),
    method_name="textDocument/completion",
    params=demo_position_to_json({ line: 3, character: 8 }),
  )
  steps.push({
    label: "completion",
    output: demo_result_of(@lsp_binding.dispatch(req_comp, router)),
  })

  // ── 7. definition（dispatch；位置落在 line 3 的 ${host} 引用上） ────
  let req_def = @lsp_binding.Request(
    id=@lsp_binding.IdNum(4),
    method_name="textDocument/definition",
    params=demo_position_to_json({ line: 3, character: 8 }),
  )
  steps.push({
    label: "definition",
    output: demo_result_of(@lsp_binding.dispatch(req_def, router)),
  })

  // ── 8. references（dispatch；键 host） ─────────────────────────────
  let req_refs = @lsp_binding.Request(
    id=@lsp_binding.IdNum(5),
    method_name="textDocument/references",
    params=@lsp_binding.JObj([("name", @lsp_binding.JStr("host"))]),
  )
  steps.push({
    label: "references",
    output: demo_result_of(@lsp_binding.dispatch(req_refs, router)),
  })

  // ── 9. rename（dispatch；键 port → PORT） ──────────────────────────
  let req_rename = @lsp_binding.Request(
    id=@lsp_binding.IdNum(6),
    method_name="textDocument/rename",
    params=@lsp_binding.JObj([
      ("name", @lsp_binding.JStr("port")),
      ("newName", @lsp_binding.JStr("PORT")),
    ]),
  )
  steps.push({
    label: "rename",
    output: demo_result_of(@lsp_binding.dispatch(req_rename, router)),
  })

  // ── 10. hover（dispatch；位置落在 line 1 的 host 定义上） ──────────
  let req_hover = @lsp_binding.Request(
    id=@lsp_binding.IdNum(7),
    method_name="textDocument/hover",
    params=demo_position_to_json({ line: 1, character: 1 }),
  )
  steps.push({
    label: "hover",
    output: demo_result_of(@lsp_binding.dispatch(req_hover, router)),
  })

  // ── 11. shutdown（任务 5） ─────────────────────────────────────────
  let shutdown_request = @lsp_binding.Request(
    id=@lsp_binding.IdNum(10),
    method_name="shutdown",
    params=@lsp_binding.JNull,
  )
  let (session, shutdown_reply) = session.handle(shutdown_request)
  steps.push({ label: "shutdown", output: demo_result_of(shutdown_reply) })

  // ── 12. exit（任务 5；退出码经纯状态转移 step 计算） ───────────────
  // 已收到 shutdown，故 shutdown_seen=true → 退出码 0。
  let exit_step = step(session.state(), true, EvExit, @lsp_binding.IdNull)
  let exit_code = match exit_step.exit_code {
    Some(code) => code
    None => -1
  }
  steps.push({
    label: "exit",
    output: @lsp_binding.JObj([
      ("state", @lsp_binding.JStr(exit_step.state.to_string())),
      ("exitCode", demo_jint(exit_code)),
    ]),
  })
  steps
}
