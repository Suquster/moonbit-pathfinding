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
