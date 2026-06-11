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
    Ok(JsonRpcMessage::Request(id~, method~, params~)) => {
      assert_eq(id, IdNum(1))
      assert_eq(method, "initialize")
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
    Ok(JsonRpcMessage::Notification(method~, params~)) => {
      assert_eq(method, "note")
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
    method="textDocument/hover",
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
    method="log",
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
  let req = JsonRpcMessage::Request(id=IdNum(7), method="ping", params=JNull)
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
  let req = JsonRpcMessage::Request(id=IdNum(1), method="unknown", params=JNull)
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
  let note = JsonRpcMessage::Notification(method="didChange", params=JNull)
  assert_eq(dispatch(note, router), None)
}
