// logging_gaps2_test.mbt —— JSON 日志解析器错误分支收口
// （INFRA 第六十一批）：非法值、数组/对象成员失败、坏转义、关键字截断。

///|
test "parse_json_log：语法错误一律返回 None" {
  for
    s in [
      "@", // 非法起始字符。
       "[@]", // 数组成员解析失败。
       "{\"a\":@}", // 对象值解析失败。
       "\"\\x\"", // 非法转义。
       "tru", // 关键字截断。
       "{\"ts\":1}x", // 顶层残留字符。
    ] {
    assert_true(@logging.parse_json_log(s) is None)
  }
}
