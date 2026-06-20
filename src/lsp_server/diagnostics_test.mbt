// diagnostics_test.mbt —— 诊断模型单元测试（任务 13.2）。
//
// 针对 diagnostics.mbt（pull 诊断 `pull_diagnostics`）与 server.mbt 的诊断
// 序列化适配（`diagnostic_to_json` / `publish_diagnostics_notification`），
// 覆盖 Requirement 6.1 / 6.2 / 6.4 的**具体见证**：
//   * 规范严重级别码映射 Error=1 / Warning=2 / Information=3 / Hint=4   （R6.4）
//   * `textDocument/publishDiagnostics` 通知携带 uri 与诊断数组          （R6.1）
//   * `textDocument/diagnostic` pull 请求返回当前文档分析所得诊断        （R6.2）
//
// 断言策略：与 server_test.mbt 一致——对复合类型（Json / Diagnostic / Range）
// 的等值校验统一采用 `assert_true(x == y)`（走派生 `Eq`），对标量
// （Int / String）用 `assert_eq`，保持本包零告警约定。

// ───────────────────────────── 测试夹具 ───────────────────────────────

///|
/// 构造单行范围 `[start_col, end_col)`（同一行 `li`）。
fn diag_span(li : Int, a : Int, b : Int) -> Range {
  { start: { line: li, character: a }, end: { line: li, character: b } }
}

///|
/// 构造一条诊断 JSON 的期望值（range + 规范严重级别码 + message），用于在严重
/// 级别码映射测试中与 `diagnostic_to_json` 的输出逐字段比对。
fn expected_diag_json(r : Range, code : Int, msg : String) -> @lsp_binding.Json {
  @lsp_binding.JObj([
    (
      "range",
      @lsp_binding.JObj([
        (
          "start",
          @lsp_binding.JObj([
            ("line", @lsp_binding.JNum(r.start.line.to_string())),
            ("character", @lsp_binding.JNum(r.start.character.to_string())),
          ]),
        ),
        (
          "end",
          @lsp_binding.JObj([
            ("line", @lsp_binding.JNum(r.end.line.to_string())),
            ("character", @lsp_binding.JNum(r.end.character.to_string())),
          ]),
        ),
      ]),
    ),
    ("severity", @lsp_binding.JNum(code.to_string())),
    ("message", @lsp_binding.JStr(msg)),
  ])
}

// ─────────────────────── 严重级别码映射（R6.4） ───────────────────────

///|
/// `diagnostic_to_json` 将四档严重级别映射为规范数值码：
/// Error=1 / Warning=2 / Information=3 / Hint=4，并随同输出范围与消息。
test "diagnostic_to_json maps severity to canonical codes 1/2/3/4" {
  let r = diag_span(0, 0, 3)
  // Error → 1
  assert_true(
    diagnostic_to_json({ range: r, severity: Error, message: "e" }) ==
    expected_diag_json(r, 1, "e"),
  )
  // Warning → 2
  assert_true(
    diagnostic_to_json({ range: r, severity: Warning, message: "w" }) ==
    expected_diag_json(r, 2, "w"),
  )
  // Information → 3
  assert_true(
    diagnostic_to_json({ range: r, severity: Information, message: "i" }) ==
    expected_diag_json(r, 3, "i"),
  )
  // Hint → 4
  assert_true(
    diagnostic_to_json({ range: r, severity: Hint, message: "h" }) ==
    expected_diag_json(r, 4, "h"),
  )
}

// ───────────────── publishDiagnostics push 通知构造（R6.1） ───────────

///|
/// `publish_diagnostics_notification` 构造 `textDocument/publishDiagnostics`
/// 通知，params 携带文档 `uri` 与诊断数组（数组元素为各诊断的规范 JSON 编码）。
test "publish_diagnostics_notification carries uri and diagnostics array" {
  let d1 : Diagnostic = {
    range: diag_span(1, 0, 11),
    severity: Error,
    message: "缺少 '='",
  }
  let d2 : Diagnostic = {
    range: diag_span(0, 4, 8),
    severity: Warning,
    message: "未定义引用",
  }
  let msg = publish_diagnostics_notification("file:///a.conf", [d1, d2])
  match msg {
    @lsp_binding.Notification(method~, params~) => {
      assert_eq(method, "textDocument/publishDiagnostics")
      // params 必为携带 uri 与 diagnostics 数组的对象。
      assert_true(
        params ==
        @lsp_binding.JObj([
          ("uri", @lsp_binding.JStr("file:///a.conf")),
          (
            "diagnostics",
            @lsp_binding.JArr([
              expected_diag_json(diag_span(1, 0, 11), 1, "缺少 '='"),
              expected_diag_json(diag_span(0, 4, 8), 2, "未定义引用"),
            ]),
          ),
        ]),
      )
    }
    _ => fail("expected a publishDiagnostics notification")
  }
}

///|
/// 无诊断时：通知仍携带 uri 与一个空诊断数组。
test "publish_diagnostics_notification carries empty array when no diagnostics" {
  let msg = publish_diagnostics_notification("file:///empty.conf", [])
  match msg {
    @lsp_binding.Notification(method~, params~) => {
      assert_eq(method, "textDocument/publishDiagnostics")
      assert_true(
        params ==
        @lsp_binding.JObj([
          ("uri", @lsp_binding.JStr("file:///empty.conf")),
          ("diagnostics", @lsp_binding.JArr([])),
        ]),
      )
    }
    _ => fail("expected a publishDiagnostics notification")
  }
}

// ──────────────────────── pull 诊断响应（R6.2） ───────────────────────

///|
/// pull 请求返回当前文档分析所得的诊断集合，且与 `analyze(doc).diagnostics`
/// （push 路径同一投影）逐条相等。具体见证：缺 '=' 行 → Error；未定义引用
/// `${b}` → Warning，二者按「先行内诊断、后未定义引用」顺序排列。
test "pull_diagnostics returns current document diagnostics" {
  let doc : TextDocument = {
    uri: "file:///c.conf",
    text: "a = ${b}\nbroken line",
  }
  let pulled = pull_diagnostics(doc)
  // pull 路径与 analyze 投影一致。
  assert_true(pulled == analyze(doc).diagnostics)
  // 具体见证：两条诊断。
  assert_eq(pulled.length(), 2)
  // 第一条：line 1 缺 '=' → Error，范围覆盖整行 [0, 11)。
  assert_true(pulled[0].severity == Error)
  assert_true(pulled[0].range == diag_span(1, 0, 11))
  assert_eq(
    pulled[0].message,
    "缺少 '='：期望形如 key = value 的赋值",
  )
  // 第二条：未定义引用 ${b} → Warning，范围覆盖 line 0 的 ${b} [4, 8)。
  assert_true(pulled[1].severity == Warning)
  assert_true(pulled[1].range == diag_span(0, 4, 8))
  assert_eq(pulled[1].message, "引用了未定义的键：b")
}

///|
/// 语法正确文档的 pull 诊断为空集合（与 analyze 投影一致）。
test "pull_diagnostics returns empty for a valid document" {
  let doc : TextDocument = {
    uri: "file:///ok.conf",
    text: "name = app\ngreeting = hello ${name}",
  }
  let pulled = pull_diagnostics(doc)
  assert_true(pulled == analyze(doc).diagnostics)
  assert_eq(pulled.length(), 0)
}
