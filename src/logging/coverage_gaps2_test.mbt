// 黑盒测试：logging JSON 日志解析器的畸形输入拒绝分支。

///|
test "parse_json_log：顶层键类型不符与非法取值拒绝" {
  // ts 为浮点（parse_int64 失败）。
  assert_true(
    parse_json_log("{\"ts\":1.5,\"level\":\"INFO\",\"fields\":{}}") is None,
  )
  // level 非字符串。
  assert_true(parse_json_log("{\"ts\":1,\"level\":3,\"fields\":{}}") is None)
  // level 未知标签。
  assert_true(
    parse_json_log("{\"ts\":1,\"level\":\"loud\",\"fields\":{}}") is None,
  )
  // fields 非对象。
  assert_true(
    parse_json_log("{\"ts\":1,\"level\":\"INFO\",\"fields\":3}") is None,
  )
  // 未知顶层键被忽略仍可解析。
  assert_true(
    parse_json_log("{\"ts\":1,\"level\":\"INFO\",\"fields\":{},\"extra\":true}")
    is Some(_),
  )
  // 嵌套字段对象与各标量类型往返。
  guard parse_json_log(
      "{\"ts\":2,\"level\":\"WARN\",\"fields\":{\"a\":\"s\",\"b\":true,\"c\":7,\"d\":1.25,\"e\":{\"k\":1}}}",
    )
    is Some(ev)
  assert_true(ev.fields.contains("e"))
}
