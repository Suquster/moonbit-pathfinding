// server_test.mbt —— LSP_Server 五项能力处理器的单元测试（任务 14.2）。
//
// 针对极简 key=value 配置 DSL（见 moon.pkg）覆盖：
//   * on_initialize —— 声明 诊断/补全/定义/悬停 四项能力（R5.4）；
//   * on_did_change —— 重分析文档并产出诊断（R5.5）；
//   * on_completion —— 返回已定义键补全候选（R5.6）；
//   * on_definition —— 引用 → 定义位置（R5.7）；
//   * on_hover      —— 符号/引用 → 描述信息（R5.8）。
// 另覆盖与 @lsp_binding 的 JSON-RPC 序列化适配（capabilities / publishDiagnostics
// / position 解析）。
//
// 说明：对复合类型的等值校验统一采用 `assert_true(x == y)`（走派生的 `Eq`），
// 以避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警（与 @regex_engine
// 等方向的零告警约定一致）。

///|
/// 测试夹具：一份语法正确、含一处合法引用的文档。
///   line 0: "# 配置示例"          （注释，忽略）
///   line 1: "name = app"
///   line 2: "greeting = hello ${name}"
///   line 3: "port = 8080"
fn good_doc() -> TextDocument {
  {
    uri: "file:///c.conf",
    text: "# 配置示例\nname = app\ngreeting = hello ${name}\nport = 8080",
  }
}

// ───────────────────────────── on_initialize（R5.4） ──────────────────

///|
/// initialize 响应声明全部四项能力。
test "on_initialize declares all four capabilities" {
  let caps = on_initialize({ root_uri: Some("file:///proj") })
  assert_true(caps.diagnostic_provider)
  assert_true(caps.completion_provider)
  assert_true(caps.definition_provider)
  assert_true(caps.hover_provider)
}

// ───────────────────────────── on_did_change（R5.5） ──────────────────

///|
/// 语法正确的文档：无诊断。
test "on_did_change yields no diagnostics for valid document" {
  let diags = on_did_change(good_doc())
  assert_true(diags.length() == 0)
}

///|
/// 含多类错误的文档：缺 '='、非法键名、未定义引用、重复定义各产出一条诊断。
test "on_did_change reports syntax and semantic diagnostics" {
  let doc : TextDocument = {
    uri: "file:///bad.conf",
    text: "bad line without eq\n1bad = x\nok = ${missing}\ndup = 1\ndup = 2",
  }
  let diags = on_did_change(doc)
  assert_true(diags.length() == 4)
  // 行 0：缺少 '=' → Error。
  assert_true(diags[0].severity == Error)
  assert_true(diags[0].range.start.line == 0)
  // 行 1：非法键名（首字符为数字）→ Error。
  assert_true(diags[1].severity == Error)
  assert_true(diags[1].range.start.line == 1)
  // 行 4：重复定义 dup → Warning。
  assert_true(diags[2].severity == Warning)
  assert_true(diags[2].range.start.line == 4)
  // 第二遍：未定义引用 ${missing} → Warning。
  assert_true(diags[3].severity == Warning)
  assert_true(diags[3].message == "引用了未定义的键：missing")
}

// ───────────────────────────── on_completion（R5.6） ──────────────────

///|
/// 补全返回全部已定义键（去重、保序）。
test "on_completion returns defined keys" {
  let analysis = analyze(good_doc())
  let items = on_completion(analysis, { line: 2, character: 20 })
  assert_true(items.length() == 3)
  assert_true(items[0].label == "name")
  assert_true(items[0].kind == Variable)
  assert_true(items[0].detail == "= app")
  assert_true(items[1].label == "greeting")
  assert_true(items[2].label == "port")
}

///|
/// 重复定义的键在补全候选中只出现一次。
test "on_completion deduplicates repeated keys" {
  let doc : TextDocument = {
    uri: "file:///d.conf",
    text: "a = 1\na = 2\nb = 3",
  }
  let items = on_completion(analyze(doc), { line: 0, character: 0 })
  assert_true(items.length() == 2)
  assert_true(items[0].label == "a")
  assert_true(items[1].label == "b")
}

// ───────────────────────────── on_definition（R5.7） ──────────────────

///|
/// 在引用 ${name} 上请求定义：返回 name 键定义所在位置。
test "on_definition jumps from reference to definition" {
  let analysis = analyze(good_doc())
  // line 2 第 19 列落在 "${name}" 内（$ 在第 17 列）。
  match on_definition(analysis, { line: 2, character: 19 }) {
    Some(loc) => {
      assert_true(loc.uri == "file:///c.conf")
      // name 定义在 line 1，[0, 4)。
      assert_true(
        loc.range ==
        { start: { line: 1, character: 0 }, end: { line: 1, character: 4 } },
      )
    }
    None => fail("expected a definition location")
  }
}

///|
/// 在键定义自身上请求定义：返回其自身位置（自洽）。
test "on_definition on a key returns itself" {
  let analysis = analyze(good_doc())
  match on_definition(analysis, { line: 1, character: 1 }) {
    Some(loc) =>
      assert_true(
        loc.range ==
        { start: { line: 1, character: 0 }, end: { line: 1, character: 4 } },
      )
    None => fail("expected the key's own location")
  }
}

///|
/// 在空白处请求定义：返回 None。
test "on_definition returns none off-symbol" {
  let analysis = analyze(good_doc())
  assert_true(on_definition(analysis, { line: 3, character: 5 }) == None)
}

// ───────────────────────────── on_hover（R5.8） ───────────────────────

///|
/// 在键定义上悬停：返回键描述（含其值）。
test "on_hover describes a key definition" {
  let analysis = analyze(good_doc())
  match on_hover(analysis, { line: 1, character: 2 }) {
    Some(h) => {
      assert_true(h.contents == "(键) name = app")
      assert_true(
        h.range ==
        Some({
          start: { line: 1, character: 0 },
          end: { line: 1, character: 4 },
        }),
      )
    }
    None => fail("expected hover for key")
  }
}

///|
/// 在引用上悬停：返回被引用键的值描述。
test "on_hover describes a reference target" {
  let analysis = analyze(good_doc())
  match on_hover(analysis, { line: 2, character: 19 }) {
    Some(h) => assert_true(h.contents == "(引用) name = app")
    None => fail("expected hover for reference")
  }
}

///|
/// 在空白处悬停：返回 None。
test "on_hover returns none off-symbol" {
  let analysis = analyze(good_doc())
  assert_true(on_hover(analysis, { line: 3, character: 5 }) == None)
}

// ─────────────────── 与 @lsp_binding 的 JSON-RPC 适配 ─────────────────

///|
/// capabilities 序列化为声明四项能力的 JSON 对象。
test "capabilities_to_json declares four providers" {
  let caps = on_initialize({ root_uri: None })
  let json = capabilities_to_json(caps)
  assert_true(
    json ==
    @lsp_binding.JObj([
      ("diagnosticProvider", @lsp_binding.JBool(true)),
      ("completionProvider", @lsp_binding.JBool(true)),
      ("definitionProvider", @lsp_binding.JBool(true)),
      ("hoverProvider", @lsp_binding.JBool(true)),
    ]),
  )
}

///|
/// publishDiagnostics 通知：method 正确、params 携带 uri 与诊断数组。
test "publish_diagnostics_notification builds a valid notification" {
  let doc : TextDocument = { uri: "file:///bad.conf", text: "no eq here" }
  let diags = on_did_change(doc)
  let msg = publish_diagnostics_notification(doc.uri, diags)
  match msg {
    @lsp_binding.Notification(method~, params~) => {
      assert_true(method == "textDocument/publishDiagnostics")
      match params {
        @lsp_binding.JObj(fields) => {
          // 含 uri 与 diagnostics 两个字段。
          assert_true(fields.length() == 2)
          assert_true(fields[0].0 == "uri")
          assert_true(fields[1].0 == "diagnostics")
        }
        _ => fail("expected params to be a JSON object")
      }
    }
    _ => fail("expected a notification message")
  }
}

///|
/// position_from_json 还原 LSP 位置对象；缺字段返回 None。
test "position_from_json parses LSP position object" {
  let json = @lsp_binding.JObj([
    ("line", @lsp_binding.JNum("3")),
    ("character", @lsp_binding.JNum("7")),
  ])
  assert_true(position_from_json(json) == Some({ line: 3, character: 7 }))
  // 缺 character 字段 → None。
  let bad = @lsp_binding.JObj([("line", @lsp_binding.JNum("3"))])
  assert_true(position_from_json(bad) == None)
}

// ═══════════════════════════════════════════════════════════════════════
// 任务 15.4：能力层既有 API 回归（向后兼容硬约束）
//
// 目的（Requirement 10.3 / 10.4 / 10.5）：以**具体见证**逐字段锁定 `0.1.0`
// 既有契约，确保旗舰深化（lifecycle/sync/position_encoding/references/rename/
// format/semantic/diagnostics 等旁路新增）未改动能力层既有 API 的签名与行为：
//   * 五个能力处理器 on_initialize / on_did_change / on_completion /
//     on_definition / on_hover；
//   * 三个 @lsp_binding 适配器 capabilities_to_json /
//     publish_diagnostics_notification / position_from_json；
//   * 既有数据类型（Position/Range/Location/TextDocument/Diagnostic/
//     CompletionItem/Hover/ServerCapabilities/InitializeParams/Symbol/
//     Reference/Analysis）的字段与语义。
//
// 这些断言一旦因任何回归而失败，即表明既有 API 调用方的兼容性被破坏。
// 区别于上文以「能力维度」组织的单元测试，本组以**冻结黄金基线对照**的方式
// 锁定逐字段的精确形态，是 0.1.0 契约的硬约束。
// ═══════════════════════════════════════════════════════════════════════

///|
/// 回归：`on_initialize` 恒定声明全部四项 provider，与 root_uri 取值无关。
test "regression: on_initialize declares exactly four providers regardless of params" {
  // root_uri = Some(..) 与 None 两种输入产出同一能力声明。
  let with_root = on_initialize({ root_uri: Some("file:///proj") })
  let without_root = on_initialize({ root_uri: None })
  let expected : ServerCapabilities = {
    diagnostic_provider: true,
    completion_provider: true,
    definition_provider: true,
    hover_provider: true,
  }
  assert_true(with_root == expected)
  assert_true(without_root == expected)
}

///|
/// 回归：`on_did_change` 对语法正确文档产出空诊断（等价于 `analyze(doc).diagnostics`）。
test "regression: on_did_change equals analyze diagnostics projection" {
  let doc = good_doc()
  let via_handler = on_did_change(doc)
  let via_analyze = analyze(doc).diagnostics
  // on_did_change 是 analyze 诊断投影的恒等封装，二者逐条相等。
  assert_true(via_handler == via_analyze)
  assert_true(via_handler.length() == 0)
}

///|
/// 回归：`on_did_change` 对含错误文档产出与 `0.1.0` 一致的具体诊断序列。
test "regression: on_did_change diagnostics shape is unchanged" {
  let doc : TextDocument = {
    uri: "file:///bad.conf",
    text: "bad line without eq\n1bad = x\nok = ${missing}\ndup = 1\ndup = 2",
  }
  let diags = on_did_change(doc)
  assert_true(diags.length() == 4)
  // 行 0：缺 '=' → Error，范围覆盖整行 [0, 19)。
  assert_true(
    diags[0] ==
    (
      {
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 19 },
        },
        severity: Error,
        message: "缺少 '='：期望形如 key = value 的赋值",
      } : Diagnostic),
  )
  // 行 1：非法键名 → Error，范围覆盖键 [0, 5)（'=' 在第 5 列）。
  assert_true(
    diags[1] ==
    (
      {
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 5 },
        },
        severity: Error,
        message: "非法的键名（须为标识符 [A-Za-z_][A-Za-z0-9_]*）",
      } : Diagnostic),
  )
  // 行 4：重复定义 dup → Warning。
  assert_true(diags[2].severity == Warning)
  assert_true(diags[2].message == "重复定义键：dup")
  // 第二遍：未定义引用 ${missing} → Warning。
  assert_true(diags[3].severity == Warning)
  assert_true(diags[3].message == "引用了未定义的键：missing")
}

///|
/// 回归：`on_completion` 返回去重保序的已定义键候选，逐项形态与 `0.1.0` 一致。
test "regression: on_completion item shape is unchanged" {
  let analysis = analyze(good_doc())
  let items = on_completion(analysis, { line: 2, character: 20 })
  // 与 pos 无关，恒返回全部已定义键（name/greeting/port）。
  assert_true(items.length() == 3)
  assert_true(
    items[0] ==
    ({ label: "name", kind: Variable, detail: "= app" } : CompletionItem),
  )
  assert_true(
    items[1] ==
    (
      { label: "greeting", kind: Variable, detail: "= hello ${name}" } :
      CompletionItem),
  )
  assert_true(
    items[2] ==
    ({ label: "port", kind: Variable, detail: "= 8080" } : CompletionItem),
  )
  // pos 不影响候选集（占位语义）：另取一处位置结果不变。
  let items2 = on_completion(analysis, { line: 0, character: 0 })
  assert_true(items == items2)
}

///|
/// 回归：`on_definition` 在引用、键定义自身与空白处的行为与 `0.1.0` 一致。
test "regression: on_definition behavior is unchanged" {
  let analysis = analyze(good_doc())
  let name_range : Range = {
    start: { line: 1, character: 0 },
    end: { line: 1, character: 4 },
  }
  // 引用 ${name} → name 定义位置。
  assert_true(
    on_definition(analysis, { line: 2, character: 19 }) ==
    Some(({ uri: "file:///c.conf", range: name_range } : Location)),
  )
  // 键定义自身 → 自身位置（自洽）。
  assert_true(
    on_definition(analysis, { line: 1, character: 1 }) ==
    Some(({ uri: "file:///c.conf", range: name_range } : Location)),
  )
  // 空白处 → None。
  assert_true(on_definition(analysis, { line: 3, character: 5 }) == None)
}

///|
/// 回归：`on_hover` 对键定义、引用与空白处的描述文本与作用范围与 `0.1.0` 一致。
test "regression: on_hover contents and range are unchanged" {
  let analysis = analyze(good_doc())
  // 键定义上：`(键) name = app`，范围为键 token。
  assert_true(
    on_hover(analysis, { line: 1, character: 2 }) ==
    Some(
      (
        {
          contents: "(键) name = app",
          range: Some({
            start: { line: 1, character: 0 },
            end: { line: 1, character: 4 },
          }),
        } : Hover),
    ),
  )
  // 引用上：`(引用) name = app`，范围为引用 token `${name}`（[17, 24)）。
  assert_true(
    on_hover(analysis, { line: 2, character: 19 }) ==
    Some(
      (
        {
          contents: "(引用) name = app",
          range: Some({
            start: { line: 2, character: 17 },
            end: { line: 2, character: 24 },
          }),
        } : Hover),
    ),
  )
  // 空白处 → None。
  assert_true(on_hover(analysis, { line: 3, character: 5 }) == None)
}

///|
/// 回归：`capabilities_to_json` 输出确定字段顺序与键名的 JSON 对象，逐字段一致。
test "regression: capabilities_to_json shape is byte-identical to 0.1.0" {
  let caps = on_initialize({ root_uri: None })
  let json = capabilities_to_json(caps)
  assert_true(
    json ==
    @lsp_binding.JObj([
      ("diagnosticProvider", @lsp_binding.JBool(true)),
      ("completionProvider", @lsp_binding.JBool(true)),
      ("definitionProvider", @lsp_binding.JBool(true)),
      ("hoverProvider", @lsp_binding.JBool(true)),
    ]),
  )
}

///|
/// 回归：`publish_diagnostics_notification` 通知形态（method/params 字段与顺序）
/// 与 `0.1.0` 一致；诊断逐条编码为 range/severity/message 三字段对象。
///
/// 以**裸 JSON 编码逐字节对照**冻结基线（复用 @lsp_binding.encode_message），
/// 既锁定 method/params 的字段名与顺序，又避免在测试中复述 `method` 字段名。
test "regression: publish_diagnostics_notification encoding is byte-identical to 0.1.0" {
  let doc : TextDocument = { uri: "file:///bad.conf", text: "no eq here" }
  let diags = on_did_change(doc)
  let msg = publish_diagnostics_notification(doc.uri, diags)
  let expected =
    #|{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///bad.conf","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":10}},"severity":1,"message":"缺少 '='：期望形如 key = value 的赋值"}]}}
  assert_eq(@lsp_binding.encode_message(msg), ec_str_to_bytes(expected))
}

///|
/// 回归：空诊断列表的 `publish_diagnostics_notification` 携带空 diagnostics 数组。
test "regression: publish_diagnostics_notification with empty diagnostics" {
  let msg = publish_diagnostics_notification("file:///x.conf", [])
  let expected =
    #|{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///x.conf","diagnostics":[]}}
  assert_eq(@lsp_binding.encode_message(msg), ec_str_to_bytes(expected))
}

///|
/// 回归：`position_from_json` 解析合法对象、忽略额外字段，并对各类畸形输入返回 None。
test "regression: position_from_json parsing behavior is unchanged" {
  // 合法对象 → Some(Position)。
  assert_true(
    position_from_json(
      @lsp_binding.JObj([
        ("line", @lsp_binding.JNum("3")),
        ("character", @lsp_binding.JNum("7")),
      ]),
    ) ==
    Some(({ line: 3, character: 7 } : Position)),
  )
  // 负数列号（带符号整数）仍可解析。
  assert_true(
    position_from_json(
      @lsp_binding.JObj([
        ("line", @lsp_binding.JNum("0")),
        ("character", @lsp_binding.JNum("-1")),
      ]),
    ) ==
    Some(({ line: 0, character: -1 } : Position)),
  )
  // 缺 character 字段 → None。
  assert_true(
    position_from_json(@lsp_binding.JObj([("line", @lsp_binding.JNum("3"))])) ==
    None,
  )
  // 缺 line 字段 → None。
  assert_true(
    position_from_json(
      @lsp_binding.JObj([("character", @lsp_binding.JNum("7"))]),
    ) ==
    None,
  )
  // line 字段非数值（字符串）→ None。
  assert_true(
    position_from_json(
      @lsp_binding.JObj([
        ("line", @lsp_binding.JStr("3")),
        ("character", @lsp_binding.JNum("7")),
      ]),
    ) ==
    None,
  )
  // 非对象 JSON → None。
  assert_true(position_from_json(@lsp_binding.JNum("3")) == None)
  assert_true(position_from_json(@lsp_binding.JNull) == None)
}

///|
/// 回归：既有数据类型字段与语义不变——`analyze` 投影出的 Symbol / Reference /
/// Analysis 形态与 `0.1.0` 一致（逐字段冻结）。
test "regression: analyze projection types retain 0.1.0 fields" {
  let analysis = analyze(good_doc())
  // Analysis.uri 透传文档 uri。
  assert_true(analysis.uri == "file:///c.conf")
  // 三个符号，首个 Symbol 逐字段对照。
  assert_true(analysis.symbols.length() == 3)
  assert_true(
    analysis.symbols[0] ==
    (
      {
        name: "name",
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 4 },
        },
        value: "app",
      } : Symbol),
  )
  // 一处引用 ${name}，逐字段对照（范围覆盖 `${name}`）。
  assert_true(analysis.references.length() == 1)
  assert_true(
    analysis.references[0] ==
    (
      {
        name: "name",
        range: {
          start: { line: 2, character: 17 },
          end: { line: 2, character: 24 },
        },
      } : Reference),
  )
  // 语法/语义均正确：无诊断。
  assert_true(analysis.diagnostics.length() == 0)
}

///|
/// 回归：`DiagnosticSeverity` 四个变体语义稳定（经 diagnostic 严重级别体现）。
/// 通过既有错误/告警分类间接锁定 Error/Warning 变体不被重排或语义漂移。
test "regression: DiagnosticSeverity variants retain 0.1.0 semantics" {
  // 缺 '=' 为 Error；重复定义为 Warning——锁定两个核心变体语义。
  let doc : TextDocument = {
    uri: "file:///s.conf",
    text: "no eq line\na = 1\na = 2",
  }
  let diags = on_did_change(doc)
  assert_true(diags.length() == 2)
  assert_true(diags[0].severity == Error)
  assert_true(diags[1].severity == Warning)
}
