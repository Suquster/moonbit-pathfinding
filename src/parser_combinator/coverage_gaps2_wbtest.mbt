// 白盒测试：JSON 组合子解析器的数字/转义/尾随输入分支。

///|
test "json：小写 hex 转义、负指数、尾随输入与非整数打印" {
  // 小写 hex（a-f 分支）。
  guard parse_json("\"\\u00e9\"") is Ok(JString(_))
  // 负指数（json_pow10 e<0 与 sign '-' 分支）。
  guard parse_json("1e-2") is Ok(JNumber(v))
  assert_true(v > 0.009 && v < 0.011)
  // 尾随未消费输入拒绝。
  assert_true(parse_json("1 x") is Err(_))
  // 非整数打印走 Double 渲染分支。
  let s = print_json(JNumber(1.5))
  assert_true(s.contains("1.5"))
}
