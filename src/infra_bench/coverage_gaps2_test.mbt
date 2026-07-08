// 黑盒测试：BenchReport JSON 解析器字符串转义 / hex 边界分支。

///|
test "report JSON：\\/ 与大写 hex \\u 转义可解析、非法转义拒绝" {
  // 形状不符但字符串扫描分支（\/、大写 hex）先被走到。
  assert_true(parse_report("{\"x\":\"a\\/b\\uABCD\"}") is Err(_))
  // 悬挂反斜杠 / 未知转义 / 截断 \\u / 非 hex 字符拒绝。
  assert_true(parse_report("{\"x\":\"a\\") is Err(_))
  assert_true(parse_report("{\"x\":\"\\q\"}") is Err(_))
  assert_true(parse_report("{\"x\":\"\\u12\"}") is Err(_))
  assert_true(parse_report("{\"x\":\"\\u12G4\"}") is Err(_))
}
