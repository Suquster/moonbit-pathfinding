// trace_codec_gaps_test.mbt —— DST 轨迹编解码器错误分支覆盖收口
// （INFRA 第十七批）：记号级损坏、事件/故障种类全谱、长度前缀与尾部
// 多余记号的确定性反例。

///|
fn tc_err(s : String) -> Bool {
  deserialize_result(s) is Err(_)
}

///|
fn tc_ok(s : String) -> Bool {
  deserialize_result(s) is Ok(_)
}

///|
test "trace_codec 顶层结构损坏拒绝" {
  // 空文本 / 种子非法 / 状态非法 / 状态记号缺失。
  assert_true(tc_err(""))
  assert_true(tc_err("x 0 0 0"))
  assert_true(tc_err("-1 0 0 0"))
  assert_true(tc_err("7 2 0 0"))
  assert_true(tc_err("7"))
  // Failed 状态：原因字符串（字符数 + 码点）非法各形态。
  assert_true(tc_ok("7 1 2 97 98 0 0"))
  assert_true(tc_err("7 1 -1 0 0"))
  assert_true(tc_err("7 1 2 97 0 0"))
  assert_true(tc_err("7 1 2 97 -5 0 0"))
  assert_true(tc_err("7 1 x 0 0"))
  // trace / finals 长度：负数 / 非法 / 缺失。
  assert_true(tc_err("7 0 -1 0"))
  assert_true(tc_err("7 0 0 -1"))
  assert_true(tc_err("7 0 0"))
  // 尾部多余记号。
  assert_true(tc_err("7 0 0 0 9"))
}

///|
test "trace_codec 事件与故障种类全谱" {
  // 事件 tag 0..4 合法解码（Scheduled/Completed/Faulted/Send/Deliver）。
  assert_true(tc_ok("7 0 1 0 5 1 0"))
  assert_true(tc_ok("7 0 1 1 5 1 0"))
  assert_true(tc_ok("7 0 2 3 5 1 2 3 4 4 6 1 2 3 4 0"))
  // 事件 tag 非法 / 字段缺失。
  assert_true(tc_err("7 0 1 9 5 1 0"))
  assert_true(tc_err("7 0 1 0 5 0"))
  assert_true(tc_err("7 0 1 0 x 1 0"))
  assert_true(tc_err("7 0 1 3 5 1 2 3 0"))
  // 故障种类 0..8 全谱（Faulted 事件内嵌）。
  assert_true(tc_ok("7 0 1 2 5 1 0 0"))
  assert_true(tc_ok("7 0 1 2 5 1 1 30 0"))
  assert_true(tc_ok("7 0 1 2 5 1 2 0"))
  assert_true(tc_ok("7 0 1 2 5 1 3 1 9 0"))
  assert_true(tc_ok("7 0 1 2 5 1 4 0"))
  assert_true(tc_ok("7 0 1 2 5 1 5 0"))
  assert_true(tc_ok("7 0 1 2 5 1 6 -12 0"))
  assert_true(tc_ok("7 0 1 2 5 1 7 0"))
  assert_true(tc_ok("7 0 1 2 5 1 8 2 0"))
  // 故障种类非法 / 参数缺失或损坏。
  assert_true(tc_err("7 0 1 2 5 1 9 0"))
  assert_true(tc_err("7 0 1 2 5 1 1 x 0"))
  assert_true(tc_err("7 0 1 2 5 1 3 1 0"))
  assert_true(tc_err("7 0 1 2 5 1 6 - 0"))
  assert_true(tc_err("7 0 1 2 5 1 6 1x 0"))
  assert_true(tc_err("7 0 1 2 5 1 8 0"))
}

///|
test "trace_codec finals 段与字节适配" {
  // finals：单节点（id、log、kv）合法解码与逐级损坏。
  assert_true(tc_ok("7 0 0 1 3 2 10 20 1 1 107 42"))
  assert_true(tc_err("7 0 0 1"))
  assert_true(tc_err("7 0 0 1 3 -1"))
  assert_true(tc_err("7 0 0 1 3 2 10"))
  assert_true(tc_err("7 0 0 1 3 0 -1"))
  assert_true(tc_err("7 0 0 1 3 0 1 1 107"))
  assert_true(tc_err("7 0 0 1 3 0 1 -1 42"))
  // 字节适配：往返一致 / 损坏字节拒绝。
  match deserialize_result("7 1 1 107 1 0 5 1 1 3 2 10 20 1 1 107 42") {
    Ok(r) => {
      assert_true(result_of_bytes(result_to_bytes(r)) is Some(_))
      assert_true(serialize_result(r) != "")
    }
    Err(_) => assert_true(false)
  }
  assert_true(result_of_bytes(b"zz") is None)
}
