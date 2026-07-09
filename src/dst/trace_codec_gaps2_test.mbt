// trace_codec_gaps2_test.mbt —— 反序列化截断路径收口
// （INFRA 第二十四批）：各事件/故障种别在字段中途截断一律 Malformed。

///|
fn tc2_err(s : String) -> Unit raise {
  assert_true(deserialize_result(s) is Err(_))
}

///|
test "deserialize_result：Failed 原因字符串码点流截断拒绝" {
  // 声称 3 个码点，仅给出 2 个。
  tc2_err("7 1 3 65 66")
}

///|
test "deserialize_result：故障种别字段截断逐一拒绝" {
  // Faulted 事件（code 2）：time=1000 task=5 之后的故障字段截断。
  tc2_err("7 0 1 2 1000 5 6") // ClockSkew 缺 offset（i64 流耗尽）
  tc2_err("7 0 1 2 1000 5 3") // Partition 缺 group
  tc2_err("7 0 1 2 1000 5 3 9") // Partition 缺 until_step
  tc2_err("7 0 1 2 1000 5 8") // DiskFault 缺 lose
}

///|
test "deserialize_result：事件字段中途截断逐一拒绝" {
  tc2_err("7 0 1 1 5") // EvCompleted 缺 task_id
  tc2_err("7 0 1 2 5") // EvFaulted 缺 task_id
  tc2_err("7 0 1 3 5 1 2") // EvSend 缺 id/payload
  tc2_err("7 0 1 4 5 1 2 3") // EvDeliver 缺 payload
}
