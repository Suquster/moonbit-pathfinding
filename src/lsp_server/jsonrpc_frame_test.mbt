// jsonrpc_frame_test.mbt —— 任务 11.1 内联烟雾测试（极少量；完整属性测试在 11.3）。
//
// 覆盖：encode/decode 往返、`\n` 与 `\r\n` 头兼容、缺 Content-Length 报错、
// Content-Length 非法报错、内容不足报错，以及合法 / 非法 JSON-RPC 结构校验。
//
// 注：统一用 `assert_true(a == b)`（仅依赖 `Eq`），规避 `assert_eq` 经由
// `derive(Debug)` 触发的弃用告警，保证本测试文件 `moon check` 零告警。

///|
/// encode/decode 往返：解码 `encode_frame(body)` 还原 body，rest 为空串
/// （Requirement 10.3）。
test "jsonrpc_frame: encode/decode 往返还原 body 且 rest 为空" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}"
  match decode_frame(encode_frame(body)) {
    Ok((decoded, rest)) => {
      assert_true(decoded == body)
      assert_true(rest == "")
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 含 Unicode（BMP 外）的 body 同样往返（按码位度量与切割）。
test "jsonrpc_frame: 含 Unicode 的 body 往返一致" {
  let body = "héllo-😀-世界"
  match decode_frame(encode_frame(body)) {
    Ok((decoded, rest)) => {
      assert_true(decoded == body)
      assert_true(rest == "")
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 头部使用 `\n`（而非 `\r\n`）亦可解析（Requirement 10.2 换行兼容）。
test "jsonrpc_frame: \\n 头分隔兼容" {
  let frame = "Content-Length: 2\n\nhi"
  match decode_frame(frame) {
    Ok((body, rest)) => {
      assert_true(body == "hi")
      assert_true(rest == "")
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 头部使用 `\r\n` 同样可解析，且多余内容进入 rest。
test "jsonrpc_frame: \\r\\n 头分隔兼容且剩余进入 rest" {
  let frame = "Content-Length: 2\r\n\r\nhiEXTRA"
  match decode_frame(frame) {
    Ok((body, rest)) => {
      assert_true(body == "hi")
      assert_true(rest == "EXTRA")
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 缺失 Content-Length → MissingContentLength。
test "jsonrpc_frame: 缺 Content-Length 报错" {
  let frame = "X-Other: 1\r\n\r\nhi"
  assert_true(decode_frame(frame) == Err(MissingContentLength))
}

///|
/// Content-Length 值非数字 → InvalidContentLength(raw)。
test "jsonrpc_frame: Content-Length 非数字报错" {
  let frame = "Content-Length: abc\r\n\r\nhi"
  assert_true(decode_frame(frame) == Err(InvalidContentLength(raw="abc")))
}

///|
/// 内容不足 N 个码位 → IncompleteBody(need, got)。
test "jsonrpc_frame: 内容不足报错" {
  let frame = "Content-Length: 5\r\n\r\nhi"
  assert_true(decode_frame(frame) == Err(IncompleteBody(need=5, got=2)))
}

///|
/// 合法 JSON-RPC 请求（含 jsonrpc/method/id）→ Ok。
test "jsonrpc: 合法请求校验通过" {
  let req = @lsp_binding.JObj([
    ("jsonrpc", @lsp_binding.JStr("2.0")),
    ("method", @lsp_binding.JStr("initialize")),
    ("id", @lsp_binding.JNum("1")),
  ])
  assert_true(validate_jsonrpc(req) == Ok(()))
}

///|
/// 合法 JSON-RPC 通知（含 method 无 id）→ Ok。
test "jsonrpc: 合法通知校验通过" {
  let notif = @lsp_binding.JObj([
    ("jsonrpc", @lsp_binding.JStr("2.0")),
    ("method", @lsp_binding.JStr("textDocument/didChange")),
  ])
  assert_true(validate_jsonrpc(notif) == Ok(()))
}

///|
/// 合法 JSON-RPC 响应（含 id 与 result）→ Ok。
test "jsonrpc: 合法响应校验通过" {
  let resp = @lsp_binding.JObj([
    ("jsonrpc", @lsp_binding.JStr("2.0")),
    ("id", @lsp_binding.JNum("1")),
    ("result", @lsp_binding.JNull),
  ])
  assert_true(validate_jsonrpc(resp) == Ok(()))
}

///|
/// 非对象输入 → ParseErr。
test "jsonrpc: 非对象输入 ParseErr" {
  assert_true(validate_jsonrpc(@lsp_binding.JStr("oops")) == Err(ParseErr))
}

///|
/// 缺 jsonrpc 字段 → InvalidRequest。
test "jsonrpc: 缺 jsonrpc 字段 InvalidRequest" {
  let bad = @lsp_binding.JObj([("method", @lsp_binding.JStr("x"))])
  assert_true(validate_jsonrpc(bad) == Err(InvalidRequest))
}

///|
/// 响应同时含 result 与 error（违反恰具其一）→ InvalidRequest。
test "jsonrpc: 响应 result/error 并存 InvalidRequest" {
  let bad = @lsp_binding.JObj([
    ("jsonrpc", @lsp_binding.JStr("2.0")),
    ("id", @lsp_binding.JNum("1")),
    ("result", @lsp_binding.JNull),
    ("error", @lsp_binding.JNull),
  ])
  assert_true(validate_jsonrpc(bad) == Err(InvalidRequest))
}
