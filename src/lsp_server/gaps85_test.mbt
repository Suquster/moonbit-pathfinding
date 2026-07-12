// gaps85_test.mbt —— jsonrpc/dsl/semantic/sync 余臂收口（第八十五批）。

///|
/// validate_jsonrpc：响应的 id 为布尔（非法 id 类型）→ InvalidRequest。
test "validate_jsonrpc：响应非法 id 类型拒绝" {
  let resp = @lsp_binding.JObj([
    ("jsonrpc", @lsp_binding.JStr("2.0")),
    ("id", @lsp_binding.JBool(true)),
    ("result", @lsp_binding.JNum("1")),
  ])
  assert_true(validate_jsonrpc(resp) is Err(InvalidRequest))
}

///|
/// decode_frame：同长度但不同名的头字段不识别为 Content-Length。
test "decode_frame：同长度异名头字段不匹配" {
  // "Content-Weight" 与 "Content-Length" 等长且前缀相同 → 逐字符比较走不等臂。
  match decode_frame("Content-Weight: 2\r\n\r\n{}") {
    Err(MissingContentLength) => ()
    _ => fail("异名头字段应视为缺少 Content-Length")
  }
}

///|
/// analyze：CRLF 换行归一化（\r 被跳过，不进入行内容）。
test "analyze：CRLF 文档行归一化" {
  let a = analyze({ uri: "u", text: "a = 1\r\nb = 2" })
  // \r 被归一化跳过：两行各解析出一个符号，且无诊断。
  assert_eq(a.symbols.length(), 2)
  assert_eq(a.symbols[0].name, "a")
  assert_eq(a.symbols[1].name, "b")
  assert_eq(a.diagnostics.length(), 0)
}

///|
/// folding_ranges：带前导空白的内容行仍计入内容块。
test "folding_ranges：前导空白内容行聚块" {
  let rs = folding_ranges({ uri: "u", text: "  a = 1\n  b = 2" })
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].start.line, 0)
  assert_eq(rs[0].end.line, 1)
}

///|
/// apply_changes：负行号 → invalid_params 拒绝。
test "apply_changes：负行号拒绝" {
  let ch : ContentChange = {
    range: Some({
      start: { line: -1, character: 0 },
      end: { line: 0, character: 0 },
    }),
    text: "x",
  }
  match apply_changes("ab", [ch], Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("负行号应拒绝")
  }
}
