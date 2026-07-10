// report_gaps2_test.mbt —— 报告 JSON 解析防御分支收口
// （INFRA 第四十五批）：空数组值、非数值字段、必需字段缺失。

///|
test "parse_report：空数组与字段错误传播" {
  // backend 字段缺失 → 错误传播。
  assert_true(@infra_bench.parse_report("{\"moon_version\":\"1\"}") is Err(_))
  // backend 非字符串 → 错误传播。
  assert_true(
    @infra_bench.parse_report("{\"moon_version\":\"1\",\"backend\":[]}")
    is Err(_),
  )
}
