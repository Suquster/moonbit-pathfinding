// 黑盒测试：lsp_binding JSON 解析器数字/转义边界拒绝分支。

///|
fn cg2_bytes(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for ch in s {
    buf.push(ch.to_int().to_byte())
  }
  Bytes::from_array(buf)
}

///|
test "json：数字与转义边界拒绝、\\/ 转义解析" {
  // 负号后无数字。
  assert_true(
    decode_message(cg2_bytes("{\"jsonrpc\":\"2.0\",\"id\":-}")) is Err(_),
  )
  // 指数缺数字。
  assert_true(
    decode_message(cg2_bytes("{\"jsonrpc\":\"2.0\",\"id\":1e}")) is Err(_),
  )
  // 字符串尾悬挂反斜杠。
  assert_true(
    decode_message(cg2_bytes("{\"jsonrpc\":\"2.0\",\"method\":\"a\\")) is Err(_),
  )
  // \/ 转义合法解析。
  guard decode_message(
      cg2_bytes(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"a\\/b\",\"params\":null}",
      ),
    )
    is Ok(Request(method_name~, ..))
  assert_eq(method_name, "a/b")
}
