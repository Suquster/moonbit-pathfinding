// 黑盒测试：Duration 便捷换算 / 渲染小数填充 / abs 非负分支。

///|
test "duration：总量换算与非负 abs" {
  let d = Duration::of_millis(90_061_500L) // 1d1h1m1.5s
  assert_eq(d.abs().millis, d.millis)
  assert_eq(d.total_seconds(), 90_061L)
  assert_eq(d.total_minutes(), 1_501L)
  assert_eq(d.total_days(), 1L)
}

///|
test "duration：毫秒小数位补零渲染" {
  assert_eq(Duration::of_millis(1_005L).to_string(), "1.005s")
  assert_eq(Duration::of_millis(1_050L).to_string(), "1.050s")
  assert_eq(Duration::of_millis(1_500L).to_string(), "1.500s")
}
