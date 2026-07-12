// 黑盒测试：覆盖率审计收口（INFRA 第七十七批）——
// 多头部帧切行、头部值尾随空白裁剪、FrameReader 对非法 JSON 正文
// 的错误传播，以及取消登记复制与 id 提取余臂。

///|
fn fg2_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
test "decode_framed：多头部与值尾随空白均正确解析" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"x\",\"params\":[]}"
  let frame = fg2_bytes(
    "Content-Type: application/json\r\nContent-Length: " +
    body.length().to_string() +
    " \t\r\n\r\n" +
    body,
  )
  assert_true(decode_framed(frame) is Ok(_))
}

///|
test "FrameReader：帧完整但正文非法 JSON 时报错" {
  let bad = "not-json"
  let frame = fg2_bytes(
    "Content-Length: " + bad.length().to_string() + "\r\n\r\n" + bad,
  )
  let reader = FrameReader::new().push(frame)
  assert_true(reader.next() is Err(_))
}

///|
test "CancelRegistry：连续取消保留既有登记" {
  let r0 = CancelRegistry::new()
  let r1 = r0.cancel(IdNum(1))
  let r2 = r1.cancel(IdStr("a"))
  assert_true(r2.is_cancelled(IdNum(1)))
  assert_true(r2.is_cancelled(IdStr("a")))
}

///|
test "cancel_id_of：缺 id 字段与非对象参数返回 None" {
  assert_true(cancel_id_of(JObj([("x", JNull)])) is None)
  assert_true(cancel_id_of(JNull) is None)
}
