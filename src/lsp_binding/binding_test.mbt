// binding_test.mbt —— LSP_Binding 编解码/分发桩的单元测试（任务 14.1）。
//
// 覆盖（Requirement 5.1 / 5.2 / 5.3）：
//   * 合法请求 / 通知 / 响应的解码；
//   * encode → decode 往返（与 Property 11 同向，单元层面先行验证）；
//   * 非法消息（非法 JSON / 顶层非对象 / 缺失 jsonrpc）返回**规范错误**且不终止；
//   * dispatch 命中处理器、方法未找到合成规范错误响应、通知无响应。
//
// 说明：`_test.mbt` 为黑盒测试，仅可见包的公有项；包内私有的字节↔文本转换不可
// 直接调用，故本文件以本地 `t2b`（文本→字节，逐字符低 8 位，ASCII 无损）构造
// 测试输入，与 json.mbt 中的 `text_to_bytes` 等价。

///|
/// 测试辅助：文本 → 字节（逐字符低 8 位，ASCII 无损），等价于包内 text_to_bytes。
fn t2b(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

// ───────────────────────────── 解码：合法消息 ─────────────────────────

///|
/// 合法请求解码：method / id / params 正确还原。
test "decode valid request" {
  let bytes = t2b(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"k\":\"v\"}}",
  )
  match decode_message(bytes) {
    Ok(JsonRpcMessage::Request(id~, method_name~, params~)) => {
      assert_eq(id, IdNum(1))
      assert_eq(method_name, "initialize")
      assert_eq(params, JObj([("k", JStr("v"))]))
    }
    Ok(_) => fail("expected a Request")
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

///|
/// 合法通知解码：无 id → Notification；数组 params 与数值字面量正确还原。
test "decode valid notification with array params" {
  let bytes = t2b("{\"jsonrpc\":\"2.0\",\"method\":\"note\",\"params\":[1,2]}")
  match decode_message(bytes) {
    Ok(JsonRpcMessage::Notification(method_name~, params~)) => {
      assert_eq(method_name, "note")
      assert_eq(params, JArr([JNum("1"), JNum("2")]))
    }
    _ => fail("expected a Notification")
  }
}

///|
/// 合法响应解码：含 result、字符串 id。
test "decode valid response with result" {
  let bytes = t2b("{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"result\":true}")
  match decode_message(bytes) {
    Ok(JsonRpcMessage::Response(id~, result~, error~)) => {
      assert_eq(id, IdStr("abc"))
      assert_eq(result, Some(JBool(true)))
      assert_eq(error, None)
    }
    _ => fail("expected a Response")
  }
}

// ───────────────────────────── 往返 ───────────────────────────────────

///|
/// 请求 encode → decode 往返恒等。
test "encode/decode round-trip for request" {
  let msg = JsonRpcMessage::Request(
    id=IdNum(42),
    method_name="textDocument/hover",
    params=JObj([("line", JNum("3")), ("char", JNum("7"))]),
  )
  match decode_message(encode_message(msg)) {
    Ok(decoded) => assert_eq(decoded, msg)
    Err(e) => fail("round-trip failed: " + e.message)
  }
}

///|
/// 通知与响应 encode → decode 往返恒等（含转义字符串与 null id）。
test "encode/decode round-trip for notification and response" {
  let note = JsonRpcMessage::Notification(
    method_name="log",
    params=JStr("line1\nline2\t\"q\""),
  )
  match decode_message(encode_message(note)) {
    Ok(d) => assert_eq(d, note)
    Err(e) => fail("notification round-trip failed: " + e.message)
  }
  let resp = JsonRpcMessage::Response(
    id=IdNull,
    result=None,
    error=Some(RpcError::new(parse_error_code, "Parse error")),
  )
  match decode_message(encode_message(resp)) {
    Ok(d) => assert_eq(d, resp)
    Err(e) => fail("response round-trip failed: " + e.message)
  }
}

// ───────────────────────────── 解码：非法消息（R5.3） ─────────────────

///|
/// 非法 JSON → 规范的解析错误（parse_error_code），且不终止（返回 Err）。
test "decode invalid json yields parse error" {
  let bytes = t2b("{ this is not json ")
  match decode_message(bytes) {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected a parse error")
  }
}

///|
/// 顶层非对象 → 非法请求（invalid_request_code）。
test "decode non-object top-level yields invalid request" {
  match decode_message(t2b("42")) {
    Err(e) => assert_eq(e.code, invalid_request_code)
    Ok(_) => fail("expected an invalid request error")
  }
}

///|
/// 缺失 / 非法 jsonrpc 字段 → 非法请求。
test "decode missing jsonrpc field yields invalid request" {
  let bytes = t2b("{\"method\":\"x\",\"id\":1}")
  match decode_message(bytes) {
    Err(e) => assert_eq(e.code, invalid_request_code)
    Ok(_) => fail("expected an invalid request error")
  }
}

///|
/// 响应同时含 result 与 error → 非法请求（须恰有其一）。
test "decode response with both result and error yields invalid request" {
  let bytes = t2b(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":1,\"error\":{\"code\":-1,\"message\":\"m\"}}",
  )
  match decode_message(bytes) {
    Err(e) => assert_eq(e.code, invalid_request_code)
    Ok(_) => fail("expected an invalid request error")
  }
}

// ───────────────────────────── 分发 ───────────────────────────────────

///|
/// 请求命中处理器：返回处理器构造的响应。
test "dispatch routes request to registered handler" {
  let router = Router::new()
  router.register("ping", fn(_msg) {
    Some(
      JsonRpcMessage::Response(
        id=IdNum(7),
        result=Some(JStr("pong")),
        error=None,
      ),
    )
  })
  let req = JsonRpcMessage::Request(id=IdNum(7), method_name="ping", params=JNull)
  match dispatch(req, router) {
    Some(JsonRpcMessage::Response(id~, result~, ..)) => {
      assert_eq(id, IdNum(7))
      assert_eq(result, Some(JStr("pong")))
    }
    _ => fail("expected a response from the handler")
  }
}

///|
/// 请求方法未找到：合成规范的「方法未找到」错误响应。
test "dispatch unknown method yields method-not-found error response" {
  let router = Router::new()
  let req = JsonRpcMessage::Request(id=IdNum(1), method_name="unknown", params=JNull)
  match dispatch(req, router) {
    Some(JsonRpcMessage::Response(error~, ..)) =>
      match error {
        Some(e) => assert_eq(e.code, method_not_found_code)
        None => fail("expected an error object")
      }
    _ => fail("expected an error response")
  }
}

///|
/// 通知不产生响应（即便无对应处理器）。
test "dispatch notification yields no response" {
  let router = Router::new()
  let note = JsonRpcMessage::Notification(method_name="didChange", params=JNull)
  assert_eq(dispatch(note, router), None)
}

// ═══════════════════════════════════════════════════════════════════════
// 任务 15.3：协议层既有裸 JSON 行为回归（向后兼容硬约束）
//
// 目的（Requirement 10.1 / 10.2）：以**具体见证**逐字段锁定 `0.1.0` 既有契约，
// 确保深化（framing/batch/cancel/correlate 等旁路新增）未改动既有裸 JSON 正文
// （无 Content-Length 头部帧）下的 `decode_message`/`encode_message`/`dispatch`/
// `error_response` 行为，以及五个标准错误码常量与 `RpcError` 形态保持不变。
//
// 这些断言一旦因任何回归而失败，即表明既有 API 调用方的兼容性被破坏。
// ═══════════════════════════════════════════════════════════════════════

// ───────────────────────── 错误码常量：精确值冻结 ─────────────────────

///|
/// 回归：五个 JSON-RPC 2.0 标准错误码常量的精确整数值与 `0.1.0` 一致。
test "regression: five error-code constants have exact 0.1.0 values" {
  assert_eq(parse_error_code, -32700)
  assert_eq(invalid_request_code, -32600)
  assert_eq(method_not_found_code, -32601)
  assert_eq(invalid_params_code, -32602)
  assert_eq(internal_error_code, -32603)
}

///|
/// 回归：五个错误码两两互异（防止常量被错误折叠为同值）。
test "regression: five error-code constants are pairwise distinct" {
  let codes = [
    parse_error_code, invalid_request_code, method_not_found_code, invalid_params_code,
    internal_error_code,
  ]
  let mut i = 0
  while i < codes.length() {
    let mut j = i + 1
    while j < codes.length() {
      assert_true(codes[i] != codes[j])
      j = j + 1
    }
    i = i + 1
  }
}

// ─────────────────── RpcError 形态：逐字段冻结 ───────────────────────

///|
/// 回归：`RpcError::new` 产出 `{ code, message, data: None }` 的精确形态。
test "regression: RpcError::new shape is unchanged" {
  let e = RpcError::new(invalid_params_code, "bad params")
  assert_eq(e.code, invalid_params_code)
  assert_eq(e.message, "bad params")
  assert_eq(e.data, None)
  // 整体结构相等见证（逐字段一致）。
  assert_eq(e, { code: invalid_params_code, message: "bad params", data: None })
}

///|
/// 回归：`RpcError::with_data` 在 `new` 的基础上仅填充 `data`，其余字段不变。
test "regression: RpcError::with_data shape is unchanged" {
  let e = RpcError::with_data(internal_error_code, "boom", JArr([JNum("1")]))
  assert_eq(e.code, internal_error_code)
  assert_eq(e.message, "boom")
  assert_eq(e.data, Some(JArr([JNum("1")])))
  assert_eq(e, {
    code: internal_error_code,
    message: "boom",
    data: Some(JArr([JNum("1")])),
  })
}

// ─────────────── 裸 JSON 编码：逐字节文本形态冻结 ───────────────────

///|
/// 回归：请求编码为既有确定字段顺序的紧凑裸 JSON 正文（无头部帧），逐字节一致。
test "regression: bare-JSON encode of request is byte-identical to 0.1.0" {
  let req = JsonRpcMessage::Request(
    id=IdNum(1),
    method_name="initialize",
    params=JObj([("k", JStr("v"))]),
  )
  let expected = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"k\":\"v\"}}"
  assert_eq(encode_message(req), t2b(expected))
}

///|
/// 回归：通知编码（无 id 字段）逐字节一致。
test "regression: bare-JSON encode of notification is byte-identical to 0.1.0" {
  let note = JsonRpcMessage::Notification(
    method_name="note",
    params=JArr([JNum("1"), JNum("2")]),
  )
  let expected = "{\"jsonrpc\":\"2.0\",\"method\":\"note\",\"params\":[1,2]}"
  assert_eq(encode_message(note), t2b(expected))
}

///|
/// 回归：含 result 的响应编码逐字节一致（result 在 error 之前、error 缺省略去）。
test "regression: bare-JSON encode of result response is byte-identical to 0.1.0" {
  let resp = JsonRpcMessage::Response(
    id=IdStr("abc"),
    result=Some(JBool(true)),
    error=None,
  )
  let expected = "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"result\":true}"
  assert_eq(encode_message(resp), t2b(expected))
}

///|
/// 回归：含 error 的响应编码逐字节一致（含 code/message 字段顺序、null id）。
test "regression: bare-JSON encode of error response is byte-identical to 0.1.0" {
  let resp = JsonRpcMessage::Response(
    id=IdNull,
    result=None,
    error=Some(RpcError::new(parse_error_code, "Parse error")),
  )
  let expected = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}"
  assert_eq(encode_message(resp), t2b(expected))
}

// ─────────────── 裸 JSON 往返：全 Id 变体逐字段还原 ───────────────────

///|
/// 回归：裸 JSON decode∘encode 往返对三种 Id 变体（IdNum/IdStr/IdNull）逐字段恒等。
test "regression: bare-JSON decode/encode round-trip across all Id variants" {
  let msgs = [
    JsonRpcMessage::Request(id=IdNum(0), method_name="m", params=JNull),
    JsonRpcMessage::Request(
      id=IdStr("req-1"),
      method_name="textDocument/hover",
      params=JObj([("line", JNum("3"))]),
    ),
    JsonRpcMessage::Response(id=IdNull, result=Some(JNull), error=None),
    JsonRpcMessage::Notification(method_name="exit", params=JNull),
  ]
  for m in msgs {
    match decode_message(encode_message(m)) {
      Ok(d) => assert_eq(d, m)
      Err(e) => fail("round-trip failed for a message: " + e.message)
    }
  }
}

// ─────────────── dispatch：路由与 method_not_found 合成（id 一致） ────

///|
/// 回归：`dispatch` 命中已登记处理器时原样返回处理器结果（裸 JSON 语义不变）。
test "regression: dispatch routes to registered handler with handler result" {
  let router = Router::new()
  router.register("ping", fn(_msg) {
    Some(
      JsonRpcMessage::Response(
        id=IdNum(99),
        result=Some(JStr("pong")),
        error=None,
      ),
    )
  })
  let req = JsonRpcMessage::Request(id=IdNum(99), method_name="ping", params=JNull)
  assert_eq(
    dispatch(req, router),
    Some(
      JsonRpcMessage::Response(
        id=IdNum(99),
        result=Some(JStr("pong")),
        error=None,
      ),
    ),
  )
}

///|
/// 回归：未登记 method 合成 method_not_found 错误响应，且 id 与请求一致、message
/// 形态（"Method not found: <method>"）不变。
test "regression: dispatch synthesizes method_not_found with matching id" {
  let router = Router::new()
  let req = JsonRpcMessage::Request(
    id=IdStr("call-7"),
    method_name="no/such",
    params=JNull,
  )
  assert_eq(
    dispatch(req, router),
    Some(
      JsonRpcMessage::Response(
        id=IdStr("call-7"),
        result=None,
        error=Some(
          RpcError::new(method_not_found_code, "Method not found: no/such"),
        ),
      ),
    ),
  )
}

///|
/// 回归：通知不产生响应；服务端不分发响应消息（返回 None）。
test "regression: dispatch yields None for notification and response inputs" {
  let router = Router::new()
  let note = JsonRpcMessage::Notification(method_name="didChange", params=JNull)
  assert_eq(dispatch(note, router), None)
  let resp = JsonRpcMessage::Response(
    id=IdNum(1),
    result=Some(JNull),
    error=None,
  )
  assert_eq(dispatch(resp, router), None)
}

// ─────────────── error_response：合成形态冻结 ───────────────────────

///|
/// 回归：`error_response` 合成 `Response(id, result=None, error=Some(new(code,msg)))`。
test "regression: error_response shape is unchanged" {
  let r = error_response(IdNum(5), invalid_request_code, "Invalid Request")
  assert_eq(
    r,
    JsonRpcMessage::Response(
      id=IdNum(5),
      result=None,
      error=Some(RpcError::new(invalid_request_code, "Invalid Request")),
    ),
  )
}

///|
/// 回归：`error_response` 编码为既有确定形态的裸 JSON 正文，逐字节一致。
test "regression: error_response bare-JSON encoding is byte-identical to 0.1.0" {
  let r = error_response(IdNum(5), invalid_request_code, "Invalid Request")
  let expected = "{\"jsonrpc\":\"2.0\",\"id\":5,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}"
  assert_eq(encode_message(r), t2b(expected))
}
