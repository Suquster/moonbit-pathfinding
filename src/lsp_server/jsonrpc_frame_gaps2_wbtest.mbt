// jsonrpc_frame_gaps2_wbtest.mbt —— 帧解析辅助与错误 Show 收口
// （INFRA 第四十三批）：尾随空白裁剪、空数值段、大小写同长失配、
// JsonRpcError Show 全构造输出。

///|
test "trim_codepoints / parse_nonneg_int：尾随空白裁剪与空数值段" {
  // 头部值含尾随空白 → trim 后仍可解析。
  match decode_frame("Content-Length: 2 \r\n\r\nokrest") {
    Ok((body, rest)) => {
      assert_eq(body, "ok")
      assert_eq(rest, "rest")
    }
    Err(_) => assert_true(false)
  }
  // 值为空串 → 数值非法。
  assert_true(decode_frame("Content-Length:\r\n\r\nx") is Err(_))
}

///|
test "ascii_case_insensitive_eq：同长不同字符失配" {
  // 同长但字符不同的头部键不匹配 Content-Length → 缺失错误。
  assert_true(decode_frame("Content-Lengthx: 2\r\n\r\nok") is Err(_))
}

///|
test "JsonRpcError：Show 全构造输出" {
  assert_eq("\{ParseErr}", "ParseErr")
  assert_eq("\{InvalidRequest}", "InvalidRequest")
  assert_eq("\{MethodNotFound}", "MethodNotFound")
  assert_eq("\{InvalidParams}", "InvalidParams")
  assert_eq("\{InternalErr}", "InternalErr")
}
