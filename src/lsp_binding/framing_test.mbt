// framing_test.mbt —— LSP Base Protocol 头部帧处理单元测试（任务 1.2）。
//
// 覆盖（Requirement 2.2 / 2.3）：
//   * 畸形帧：缺 `Content-Length` 头、值非非负整数 → `decode_framed` /
//     `FrameReader::next` 返回 `parse_error_code`；
//   * 正文不足：`decode_framed` 返回 `parse_error_code`；`FrameReader::next`
//     返回 `Ok(None)`（数据不足、缓冲保持可继续），补足后再切出；
//   * 单帧：`decode_framed` 与 `FrameReader` 逐条切出与原消息相等；
//   * 连续多帧：`FrameReader` 在拼接缓冲上按出现顺序逐条切出的具体见证。
//
// 说明：`_test.mbt` 为黑盒测试，仅可见包的公有项；包内私有的字节↔文本转换不可
// 直接调用，故本文件以本地 `fr_*` 前缀 helper 构造测试输入（与同包其它测试文件
// 的 `t2b` / `err_text_to_bytes` 命名错开，避免重名冲突）。

// ───────────────────────────── 测试辅助（本文件私有） ─────────────────

///|
/// 文本 → 字节（逐字符低 8 位，ASCII 无损）。
fn fr_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 顺序拼接两段 `Bytes`，返回新 `Bytes`。
fn fr_concat(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < a.length() {
    arr.push(a[i])
    i = i + 1
  }
  i = 0
  while i < b.length() {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// 取字节切片 `[start, end)` 为新 `Bytes`。
fn fr_slice(b : Bytes, start : Int, end : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = start
  while i < end {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

// ───────────────────────────── 畸形帧：缺 / 非法 Content-Length ───────

///|
/// 缺 `Content-Length` 头：`decode_framed` 返回 `parse_error_code`，不产出消息。
test "decode_framed missing Content-Length yields parse error" {
  // 头部块完整（以 \r\n\r\n 终止）但无 Content-Length 字段，正文为合法 JSON。
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"x\",\"params\":[]}"
  let frame = fr_bytes("Content-Type: application/json\r\n\r\n" + body)
  match decode_framed(frame) {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected a parse error for missing Content-Length")
  }
}

///|
/// `Content-Length` 值非非负整数（非数字 / 含负号）：返回 `parse_error_code`。
test "decode_framed non-integer Content-Length yields parse error" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"x\",\"params\":[]}"
  // 值为非数字。
  let frame_abc = fr_bytes("Content-Length: abc\r\n\r\n" + body)
  match decode_framed(frame_abc) {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected a parse error for non-integer Content-Length")
  }
  // 值带负号（非「非负整数」）。
  let frame_neg = fr_bytes("Content-Length: -5\r\n\r\n" + body)
  match decode_framed(frame_neg) {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected a parse error for negative Content-Length")
  }
}

///|
/// 畸形帧经 `FrameReader::next` 同样以 `Err(parse_error_code)` 承载（缺头）。
test "FrameReader next surfaces malformed frame as parse error" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"x\",\"params\":[]}"
  let frame = fr_bytes("X-Foo: bar\r\n\r\n" + body)
  let reader = FrameReader::new().push(frame)
  match reader.next() {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected FrameReader to surface a parse error")
  }
}

// ───────────────────────────── 正文不足 ───────────────────────────────

///|
/// 正文长度不足声明字节数：`decode_framed` 返回 `parse_error_code`，不产出消息。
test "decode_framed insufficient body yields parse error" {
  // 声明 100 字节，实际正文仅 2 字节。
  let frame = fr_bytes("Content-Length: 100\r\n\r\n{}")
  match decode_framed(frame) {
    Err(e) => assert_eq(e.code, parse_error_code)
    Ok(_) => fail("expected a parse error for insufficient body")
  }
}

///|
/// 正文不足时 `FrameReader::next` 返回 `Ok(None)`（缓冲可继续）；补足后切出。
test "FrameReader returns None on insufficient body then cuts after refill" {
  let msg = JsonRpcMessage::Request(
    id=IdNum(1),
    method="initialize",
    params=JObj([("k", JStr("v"))]),
  )
  let frame = encode_framed(msg)
  // 故意只投喂前半段（保证落在正文中部：总长必 > 4，切在末尾前一字节）。
  let cut = frame.length() - 1
  let head = fr_slice(frame, 0, cut)
  let tail = fr_slice(frame, cut, frame.length())

  // 第一次：数据不足 → Ok(None)。
  let reader1 = FrameReader::new().push(head)
  match reader1.next() {
    Ok(None) => ()
    Ok(Some(_)) => fail("expected None: body not yet complete")
    Err(e) => fail("expected Ok(None), got error: " + e.message)
  }

  // 补足剩余字节后：切出完整消息，剩余缓冲为空。
  let reader2 = reader1.push(tail)
  match reader2.next() {
    Ok(Some((decoded, rest))) => {
      assert_eq(decoded, msg)
      match rest.next() {
        Ok(None) => ()
        _ => fail("expected empty reader after the only frame")
      }
    }
    Ok(None) => fail("expected a complete frame after refill")
    Err(e) => fail("unexpected error after refill: " + e.message)
  }
}

// ───────────────────────────── 单帧切分 ───────────────────────────────

///|
/// 单帧：`decode_framed(encode_framed(msg))` 还原为原消息。
test "decode_framed cuts a single valid frame" {
  let msg = JsonRpcMessage::Notification(
    method="textDocument/didChange",
    params=JArr([JNum("1"), JNum("2")]),
  )
  match decode_framed(encode_framed(msg)) {
    Ok(decoded) => assert_eq(decoded, msg)
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

///|
/// 单帧：`FrameReader` 切出唯一一帧后，剩余缓冲再 `next` 为 `Ok(None)`。
test "FrameReader cuts a single frame and then yields None" {
  let msg = JsonRpcMessage::Request(
    id=IdStr("req-1"),
    method="textDocument/hover",
    params=JObj([("line", JNum("3"))]),
  )
  let reader = FrameReader::new().push(encode_framed(msg))
  match reader.next() {
    Ok(Some((decoded, rest))) => {
      assert_eq(decoded, msg)
      match rest.next() {
        Ok(None) => ()
        _ => fail("expected None after consuming the only frame")
      }
    }
    _ => fail("expected exactly one frame")
  }
}

// ───────────────────────────── 连续多帧切分 ──────────────────────────

///|
/// 连续多帧：三帧拼接在同一缓冲，`FrameReader` 按出现顺序逐条切出，最后 None。
test "FrameReader cuts consecutive multiple frames in order" {
  let m1 = JsonRpcMessage::Request(
    id=IdNum(1),
    method="initialize",
    params=JNull,
  )
  let m2 = JsonRpcMessage::Notification(method="initialized", params=JObj([]))
  let m3 = JsonRpcMessage::Response(
    id=IdNum(1),
    result=Some(JBool(true)),
    error=None,
  )
  // 三帧顺序拼接为单一字节缓冲。
  let stream = fr_concat(
    fr_concat(encode_framed(m1), encode_framed(m2)),
    encode_framed(m3),
  )
  let r0 = FrameReader::new().push(stream)

  // 第 1 帧 == m1。
  let r1 = match r0.next() {
    Ok(Some((d, rest))) => {
      assert_eq(d, m1)
      rest
    }
    _ => {
      fail("expected first frame m1")
      r0
    }
  }
  // 第 2 帧 == m2。
  let r2 = match r1.next() {
    Ok(Some((d, rest))) => {
      assert_eq(d, m2)
      rest
    }
    _ => {
      fail("expected second frame m2")
      r1
    }
  }
  // 第 3 帧 == m3。
  let r3 = match r2.next() {
    Ok(Some((d, rest))) => {
      assert_eq(d, m3)
      rest
    }
    _ => {
      fail("expected third frame m3")
      r2
    }
  }
  // 全部切完 → Ok(None)。
  match r3.next() {
    Ok(None) => ()
    _ => fail("expected None after all three frames consumed")
  }
}

///|
/// 多帧 + 末尾出现不完整帧：前两帧正常切出，尾部不完整帧返回 `Ok(None)`。
test "FrameReader cuts complete frames and stops at a trailing partial frame" {
  let m1 = JsonRpcMessage::Notification(method="a", params=JNull)
  let m2 = JsonRpcMessage::Notification(method="b", params=JNull)
  let full = fr_concat(encode_framed(m1), encode_framed(m2))
  // 追加一个不完整的第三帧（仅头部、声明长度未满足）。
  let partial = fr_bytes("Content-Length: 50\r\n\r\n{")
  let r0 = FrameReader::new().push(fr_concat(full, partial))

  let r1 = match r0.next() {
    Ok(Some((d, rest))) => {
      assert_eq(d, m1)
      rest
    }
    _ => {
      fail("expected first frame m1")
      r0
    }
  }
  let r2 = match r1.next() {
    Ok(Some((d, rest))) => {
      assert_eq(d, m2)
      rest
    }
    _ => {
      fail("expected second frame m2")
      r1
    }
  }
  // 尾部不完整帧 → 数据不足，Ok(None)。
  match r2.next() {
    Ok(None) => ()
    Ok(Some(_)) => fail("trailing partial frame must not be cut")
    Err(e) => fail("partial frame should be None, not error: " + e.message)
  }
}
