// batch_test.mbt —— JSON-RPC 2.0 批量请求（Batch）单元测试（任务 2.2，黑盒）。
//
// 覆盖（Requirement 2.4）：
//   * 混合请求 / 通知经 `dispatch_batch` 后，响应**按出现顺序**汇集为响应数组；
//   * 通知（Notification）不产生响应，从响应数组中略去；
//   * `decode_batch` 中单个非法元素被**就地隔离**标记为该元素 `Err`，不影响其余
//     元素的解码（稳健性见证）；并锁定顶层非数组 / 非法 JSON 的顶层错误码。
//
// 说明：`_test.mbt` 为黑盒测试，仅可见包的公有项；包内私有的字节↔文本转换不可
// 直接调用，故本文件以本地 `bt_bytes`（文本→字节，逐字符低 8 位，ASCII 无损）
// 构造批量 JSON 数组字节，命名以 `bt_` 前缀与同包其它测试文件（`t2b` /`fr_*`）
// 错开，避免重名冲突。

// ───────────────────────────── 测试辅助（本文件私有） ─────────────────

///|
/// 文本 → 字节（逐字符低 8 位，ASCII 无损），等价于包内 text_to_bytes。
fn bt_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 构造一个测试路由表：注册请求处理器 "echo"（回显请求 id、返回固定结果），
/// 与通知处理器 "note"（注册但返回 None，验证通知不产生响应）。
fn bt_router() -> Router {
  let router = Router::new()
  // 请求处理器：命中后返回 id 与请求一致、result 固定为 "echoed" 的响应。
  router.register("echo", fn(msg) {
    match msg {
      Request(id~, ..) =>
        Some(
          JsonRpcMessage::Response(id~, result=Some(JStr("echoed")), error=None),
        )
      _ => None
    }
  })
  // 通知处理器：注册但返回 None（通知无响应）。
  router.register("note", fn(_msg) { None })
  router
}

// ───────────────────── 逐条分发：响应按序汇集 + 通知略去 ───────────────

///|
/// 混合请求 / 通知逐条分发：响应按出现顺序汇集；通知不产生响应（被略去）。
/// 具体见证：输入 [echo#1, note, echo#2, unknown#3] → 响应 [#1, #2, #3]（3 条），
/// note 通知被略去，未注册方法 unknown 合成 method_not_found_code 错误响应。
test "dispatch_batch collects responses in order and skips notifications" {
  let router = bt_router()
  let msgs : Array[JsonRpcMessage] = [
    Request(id=IdNum(1), method_name="echo", params=JObj([])),
    Notification(method_name="note", params=JNull),
    Request(id=IdNum(2), method_name="echo", params=JObj([])),
    Request(id=IdNum(3), method_name="unknown", params=JNull),
  ]
  let responses = dispatch_batch(msgs, router)
  // 通知略去：4 条输入 → 3 条响应。
  assert_eq(responses.length(), 3)
  // 第 1 条：echo#1 的回显响应。
  assert_eq(
    responses[0],
    JsonRpcMessage::Response(
      id=IdNum(1),
      result=Some(JStr("echoed")),
      error=None,
    ),
  )
  // 第 2 条：echo#2 的回显响应（顺序保持，note 已被略去）。
  assert_eq(
    responses[1],
    JsonRpcMessage::Response(
      id=IdNum(2),
      result=Some(JStr("echoed")),
      error=None,
    ),
  )
  // 第 3 条：unknown#3 的方法未找到错误响应，id 与请求一致。
  match responses[2] {
    JsonRpcMessage::Response(id~, error~, ..) => {
      assert_eq(id, IdNum(3))
      match error {
        Some(e) => assert_eq(e.code, method_not_found_code)
        None => fail("expected an error object for unknown method")
      }
    }
    _ => fail("expected an error response for unknown method")
  }
}

///|
/// 通知不产生响应：全为通知的批量分发得到空响应数组。
test "dispatch_batch with only notifications yields empty responses" {
  let router = bt_router()
  let msgs : Array[JsonRpcMessage] = [
    Notification(method_name="note", params=JNull),
    Notification(method_name="note", params=JArr([JNum("1")])),
    // 未注册的通知同样不产生响应。
    Notification(method_name="unregistered", params=JNull),
  ]
  let responses = dispatch_batch(msgs, router)
  assert_eq(responses.length(), 0)
}

// ───────────────────── 批量解码：单个非法元素被隔离标记 ────────────────

///|
/// 单个非法元素被隔离：[合法请求, 非法元素(缺 jsonrpc), 合法通知] →
/// 元素 0/2 为 Ok，元素 1 为 Err(invalid_request_code)，互不影响。
test "decode_batch isolates a single invalid element" {
  let bytes = bt_bytes(
    "[" +
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"echo\",\"params\":{}}," +
    "{\"id\":2,\"method\":\"bad\"}," + // 缺 jsonrpc 字段 → 非法
    "{\"jsonrpc\":\"2.0\",\"method\":\"note\",\"params\":[]}" +
    "]",
  )
  match decode_batch(bytes) {
    Ok(results) => {
      assert_eq(results.length(), 3)
      // 元素 0：合法请求。
      match results[0] {
        Ok(JsonRpcMessage::Request(id~, method_name~, ..)) => {
          assert_eq(id, IdNum(1))
          assert_eq(method_name, "echo")
        }
        _ => fail("element 0 should decode as a valid Request")
      }
      // 元素 1：非法（缺 jsonrpc）→ 就地标记为该元素 Err，且不影响其余元素。
      match results[1] {
        Err(e) => assert_eq(e.code, invalid_request_code)
        Ok(_) => fail("element 1 should be isolated as an Err")
      }
      // 元素 2：合法通知（在非法元素之后仍正常解码）。
      match results[2] {
        Ok(JsonRpcMessage::Notification(method_name~, ..)) =>
          assert_eq(method_name, "note")
        _ => fail("element 2 should decode as a valid Notification")
      }
    }
    Err(e) =>
      fail("expected Ok with per-element results, got error: " + e.message)
  }
}

///|
/// 顶层为合法 JSON 但非数组 → 顶层 Err(invalid_request_code)。
test "decode_batch non-array top-level yields invalid request" {
  let bytes = bt_bytes(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"echo\",\"params\":{}}",
  )
  match decode_batch(bytes) {
    Err(e) => assert_eq(e.code, invalid_request_code)
    Ok(_) => fail("expected a top-level invalid request error for a non-array")
  }
}

///|
/// 顶层非法 JSON → 顶层 Err(parse_error_code)。
test "decode_batch invalid json yields parse error" {
  let bytes = bt_bytes("[ this is not json ")
  match decode_batch(bytes) {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected a top-level parse error for invalid JSON")
  }
}

// ───────────────────── 端到端：解码 → 逐条分发按序汇集 ─────────────────

///|
/// 端到端见证：解码混合批量后逐条分发，响应顺序与请求出现顺序一致、通知略去。
test "decode_batch then dispatch_batch preserves request order" {
  let router = bt_router()
  let bytes = bt_bytes(
    "[" +
    "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"echo\",\"params\":{}}," +
    "{\"jsonrpc\":\"2.0\",\"method\":\"note\",\"params\":[]}," +
    "{\"jsonrpc\":\"2.0\",\"id\":\"b\",\"method\":\"echo\",\"params\":{}}" +
    "]",
  )
  let msgs : Array[JsonRpcMessage] = match decode_batch(bytes) {
    Ok(results) => {
      let acc : Array[JsonRpcMessage] = []
      for r in results {
        match r {
          Ok(m) => acc.push(m)
          Err(e) => fail("unexpected element error: " + e.message)
        }
      }
      acc
    }
    Err(e) => {
      fail("unexpected top-level error: " + e.message)
      []
    }
  }
  let responses = dispatch_batch(msgs, router)
  // 两个 echo 请求 → 两条响应，note 通知略去；id 按出现顺序保持。
  assert_eq(responses.length(), 2)
  assert_eq(
    responses[0],
    JsonRpcMessage::Response(
      id=IdStr("a"),
      result=Some(JStr("echoed")),
      error=None,
    ),
  )
  assert_eq(
    responses[1],
    JsonRpcMessage::Response(
      id=IdStr("b"),
      result=Some(JStr("echoed")),
      error=None,
    ),
  )
}
